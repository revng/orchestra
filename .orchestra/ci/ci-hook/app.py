#!/usr/bin/env python3

import base64
import hashlib
import hmac
import json
import os
import string
import sys
import time
from datetime import date, datetime, timedelta
from textwrap import dedent
from typing import Optional, Tuple

import dateutil.parser
import gitlab
import jwt
import requests
from cryptography.hazmat.backends import default_backend
from flask import Flask, request

app = Flask(__name__)
config_file = os.environ.get("CONFIG_FILE_PATH", "config.json")


def get_env_or_fail(var_name):
    value = os.getenv(var_name)
    if value is None:
        raise Exception(f"Environment variable {var_name} is not set!")
    return value


GITLAB_SECRET = get_env_or_fail("GITLAB_SECRET")
GITHUB_APP_SECRET = get_env_or_fail("GITHUB_APP_SECRET").encode("utf-8")
revng_push_ci_private_key_b64 = get_env_or_fail("REVNG_PUSH_CI_PRIVATE_KEY_BASE64")
revng_push_ci_private_key = base64.b64decode(revng_push_ci_private_key_b64).decode("utf-8")
github_priv_key_b64 = get_env_or_fail("GITHUB_PRIVATE_KEY_BASE64")
github_priv_key = default_backend().load_pem_private_key(base64.b64decode(github_priv_key_b64), None)
ADMIN_TOKEN = get_env_or_fail("GITLAB_ADMIN_TOKEN")

GITHUB_API_URL = "https://api.github.com"

try:
    with open(config_file) as f:
        config = json.load(f)
except IOError:
    log(f"Could not open configuration file ({config_file})")
    exit(1)

allowed_to_push = config["allowed_to_push"]
GITLAB_URL = config["gitlab_url"]
PROJECT_ID = config["project_id"]
BRANCH = config["branch"]
mapping = config["github_to_gitlab_mapping"]
default_user = config["default_user"]
ci_user = config["ci_user"]
github_app_id = config["github_app_id"]
ci_job_url = config["ci_job_url"]
github_installation_id = config["github_installation_id"]

_installation_token_info = None


def log(*a, **kw):
    return print(*a, **kw, file=sys.stderr)


def log_response(body: str, status_code: int = 400) -> Tuple[str, int]:
    log(body, end="")
    return body, status_code


def installation_token() -> str:
    global _installation_token_info
    should_refresh = _installation_token_info is None
    if not should_refresh:
        expires = dateutil.parser.isoparse(_installation_token_info["expires_at"])
        now = datetime.now(expires.tzinfo)
        should_refresh = (expires - timedelta(minutes=10)) < now

    if should_refresh:
        token = jwt.encode(
            {
                "iat": int(time.time()) + 60,
                "exp": int(time.time()) + 10 * 60,
                "iss": str(github_app_id)
            },
            github_priv_key,
            "RS256"
        )
        r = requests.post(f"{GITHUB_API_URL}/app/installations/{github_installation_id}/access_tokens", headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
        })
        if r.status_code not in (200, 201, 202):
            raise RuntimeError("Unable to retrieve GitHub installation token")
        _installation_token_info = r.json()
    return _installation_token_info["token"]


def github_headers() -> dict:
    result = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"token {installation_token()}",
    }.copy()
    return result


ORCHESTRA_CONFIG_REPO_HTTP_URL = config["orchestra_config_repo_http_url"]
ORCHESTRA_CONFIG_REPO_SSH_URL = config["orchestra_config_repo_ssh_url"]

pusher_user_options = dedent("""
    #@data/values
    ---
    #@overlay/match missing_ok=True
    remote_base_urls:
    - public: git@github.com:revng
    - private: git@rev.ng:revng-private

    #@overlay/match missing_ok=True
    binary_archives:
    - public: git@rev.ng:revng/binary-archives.git
    - private: git@rev.ng:revng-private/binary-archives.git
""")

user_options = dedent("""
    #@data/values
    ---
    #@overlay/match missing_ok=True
    remote_base_urls:
    - source: ${clone_namespace}
    - public: https://github.com/revng
    ${private_sources}

    #@overlay/match missing_ok=True
    binary_archives:
    - public: https://rev.ng/gitlab/revng/binary-archives.git
    ${private_bin_archives}
""")


def hub_to_lab(username):
    return mapping.get(username, default_user)


class ImpersonationToken:
    def __init__(self, user):
        self.user = user

    def __enter__(self):
        self.impersonation_token = self.user.impersonationtokens.create({
            "name": "ci-temporary-token",
            "scopes": ["api"],
            "expires_at": (date.today() + timedelta(days=2)).strftime("%Y-%m-%d")
        })
        return self.impersonation_token.token

    def __exit__(self, exc_type, exc_val, exc_tb):
        impersonation_token_id = self.impersonation_token.id
        self.user.impersonationtokens.delete(impersonation_token_id)
        assert not self.user.impersonationtokens.get(impersonation_token_id).active


def impersonate(admin_gl, username):
    """
    Provides a context manager returning a token for the given username.
    """
    matching = admin_gl.users.list(username=username)
    if len(matching) != 1:
        raise Exception("Unexpected number of users matching " + username)
    user_id = matching[0].id

    user = admin_gl.users.get(user_id)
    return ImpersonationToken(user)


def trigger_ci(username, repo_url, base_repo_url, ref, status_update_metadata: Optional[dict] = None):
    # Ignore pushes by the CI itself
    if username == ci_user:
        return

    admin_gl = gitlab.Gitlab(GITLAB_URL, private_token=ADMIN_TOKEN)
    admin_gl.auth()

    with impersonate(admin_gl, username) as token:
        user_gl = gitlab.Gitlab(GITLAB_URL, private_token=token)
        user_gl.auth()
        project = user_gl.projects.get(PROJECT_ID)

        is_anonymous = username == default_user

        variables = {
            "TARGET_COMPONENTS_URL": repo_url,
            "TARGET_COMPONENTS": " ".join(is_anonymous and default_user_target_components or target_components),
            "PUSHED_REF": ref,
            "ORCHESTRA_CONFIG_REPO_HTTP_URL": ORCHESTRA_CONFIG_REPO_HTTP_URL,
            "ORCHESTRA_CONFIG_REPO_SSH_URL": ORCHESTRA_CONFIG_REPO_SSH_URL,
        }

        # status_update_metadata contains info required to send back status updates to the source platform
        # (i.e. comment on GitLab MRs, "checks" on GitHub). It does not contain sensitive info.
        if status_update_metadata is not None:
            variables["REVNG_CI_STATUS_UPDATE_METADATA"] = json.dumps(status_update_metadata)

        if username in allowed_to_push and base_repo_url == repo_url:
            # If the user is allowed to push, and we're triggering the CI for a push to the same repo (as opposed to a
            # push to a fork in a pull request), we additionally want to perform branch promotion. Therefore we need to
            # use SSH git repo remotes and provide an SSH key.
            variables["BASE_USER_OPTIONS_YML"] = pusher_user_options
            variables["SSH_PRIVATE_KEY"] = revng_push_ci_private_key
            variables["PUSH_CHANGES"] = "1"
        else:
            # Otherwise, we will consider two cases:
            # - user is anonymous (i.e. we don't have a matching user on GitLab) => only provide public source repos
            # - user is a revng employee => provide access to private sources using GitLab CI's built-in impersonation
            #   token
            # In both cases we want to make sure the user's namespace is provided in order to clone the PR sources.
            tpl_params = {
                "clone_namespace": "/".join(repo_url.split("/")[:-1]),
                "private_sources": "",
                "private_bin_archives": ""
            }
            if not is_anonymous:
                # Placeholders are replaced in the shell script since we don't want to intentionally introduce shell
                # injection vulnerabilities. This is needed because the shell script will have access to the GitLab
                # token environment variable at runtime.
                tpl_params.update({
                    "private_sources": "- private: %PRIVATE_SOURCES_PLACEHOLDER%",
                    "private_bin_archives": "- private: %PRIVATE_BIN_ARCHIVES_PLACEHOLDER%"
                })

            variables["BASE_USER_OPTIONS_YML"] = \
                string.Template(user_options).substitute(tpl_params)

        parameters = {
            "ref": BRANCH,
            "variables": [{"key": key, "value": value}
                          for key, value
                          in variables.items()]
        }
        log(json.dumps(parameters, indent=2))
        project.pipelines.create(parameters)


LAB_TO_HUB_STATUS_MAP = {
    "created": "queued",
    "waiting_for_resource": "queued",
    "preparing": "queued",
    "pending": "queued",
    "running": "in_progress",
    "success": "completed",
    "failed": "completed",
    "canceled": "completed",
    "skipped": "completed",
    "manual": "queued",
    "scheduled": "queued"
}

LAB_TO_LAB_STATUS_MAP = {
    "created": "started",
    "waiting_for_resource": None,
    "preparing": None,
    "pending": None,
    "running": None,
    "success": "completed",
    "failed": "failed",
    "canceled": "cancelled",
    "skipped": "skipped",
    "manual": None,
    "scheduled": None
}

LAB_TO_HUB_CONCLUSION_MAP = {
    "success": "success",
    "failed": "failure",
    "skipped": "skipped",
    "canceled": "cancelled",
}


def get_pl_metadata(admin_gl, pipeline_id):
    pipeline = admin_gl.projects.get(PROJECT_ID).pipelines.get(pipeline_id)
    variables = pipeline.variables.list()

    for var in variables:
        if var.key == "REVNG_CI_STATUS_UPDATE_METADATA":
            return json.loads(var.value)


@app.route('/ci-hook/ci-job-callback', methods=["POST"])
def gitlab_ci_job_callback_hook():
    headers = dict(request.headers)
    if headers.get("X-Gitlab-Token", "") != GITLAB_SECRET:
        return log_response("Invalid token\n", 403)

    event = headers.get("X-Gitlab-Event", "")
    if event != "Job Hook":
        return log_response(f"Invalid event: {event}\n", 404)

    data = request.json

    # Fetch the status from the pipeline variables
    admin_gl = gitlab.Gitlab(GITLAB_URL, private_token=ADMIN_TOKEN)
    admin_gl.auth()

    metadata = get_pl_metadata(admin_gl, data["pipeline_id"])
    if not metadata:
        return "No action performed\n", 200

    if metadata["platform"] == "github":
        check_params = {
            "details_url": ci_job_url + str(data["build_id"]),
            "status": LAB_TO_HUB_STATUS_MAP[data["build_status"]],
            "external_id": str(data["build_id"]),
            "actions": []
        }
        if data.get("build_started_at"):
            check_params["started_at"] = data["build_started_at"].replace(" UTC", "Z").replace(" ", "T")
        if check_params["status"] == "completed":
            if data.get("build_finished_at"):
                check_params["completed_at"] = data["build_finished_at"].replace(" UTC", "Z").replace(" ", "T")
            check_params["conclusion"] = LAB_TO_HUB_CONCLUSION_MAP[data["build_status"]]

        r = requests.patch(
            f"{GITHUB_API_URL}/repos/{metadata['github_repository_name']}/check-runs/{metadata['github_check_run_id']}",
            headers=github_headers(),
            json=check_params
        )
        if r.status_code not in (200, 201, 202):
            return log_response(f"Github API call failed:\n{r.content.decode(errors='replace')}", r.status_code)

    elif metadata["platform"] == "gitlab":
        sha = metadata['head_sha'][:8]
        messages = {
            "started": f"The CI job for this merge request has been started for commit {sha}.\n\n"
                       f"View the status: {ci_job_url}{data['build_id']}",
            "completed": f"**Success!** The CI job has passed for commit {sha}",
            "failed": f"**Error!** The CI job has failed for commit {sha}",
            "cancelled": f"**Cancelled.** The CI job has been cancelled for commit {sha}",
            "skipped": f"**Skipped.** The CI job was skipped for commit {sha}"
        }
        message = messages.get(LAB_TO_LAB_STATUS_MAP[data["build_status"]])

        if message:
            with impersonate(admin_gl, ci_user) as token:
                user_gl = gitlab.Gitlab(GITLAB_URL, private_token=token)
                user_gl.auth()

                mr_notes = user_gl.projects.get(metadata['gitlab_project_id']).mergerequests.get(
                    metadata['gitlab_mr_iid']).notes
                mr_notes.create({
                    "body": message,
                    "merge_request_diff_sha": metadata['head_sha']
                })
    else:
        return log_response(f"Invalid platform ID: '{metadata['platform']}'\n", 500)

    return "All good\n", 200


@app.route('/ci-hook/gitlab', methods=["POST"])
def gitlab_hook():
    headers = dict(request.headers)
    if headers.get("X-Gitlab-Token", "") != GITLAB_SECRET:
        return log_response("Invalid token\n", 403)

    event = headers.get("X-Gitlab-Event", "")
    data = request.json
    attributes = data.get("object_attributes", {})

    if event == "Push Hook":
        trigger_ci(
            data["user_username"],
            data["project"]["git_http_url"] + " " + data["project"]["git_ssh_url"],
            data["project"]["git_http_url"] + " " + data["project"]["git_ssh_url"],
            data["ref"]
        )

    elif event == "Merge Request Hook" and attributes.get("action", "") in ("open", "update") \
            and attributes.get("state", "") == "opened":
        trigger_ci(
            data["user"]["username"],
            attributes["source"]["git_http_url"] + " " + attributes["source"]["git_ssh_url"],
            attributes["target"]["git_http_url"] + " " + attributes["target"]["git_ssh_url"],
            f'refs/heads/{attributes["source_branch"]}',
            {
                "platform": "gitlab",
                "gitlab_project_id": data['project']['id'],
                "gitlab_mr_iid": attributes['iid'],
                "gitlab_mr_web_url": attributes["url"],
                "head_sha": attributes['last_commit']['id']
            }
        )

    return "All good\n", 200


@app.route('/ci-hook/github', methods=["POST"])
def github_hook():
    """
    GitHub workflow:

    1. User does one of the following actions:
        - Pushes to a managed repo
        - Pushes to a pull-request targeting a managed repo
        - Presses the re-run button on a failed job
    2. GitHub sends respectively the following webhooks:
        - check_suite, action=requested
        - pull_request, action=opened/synchronize
        - check_suite or check_run, action=rerequested
    3. We create a new check run with the GitHub API (this implicitly creates a check suite as well)
    4. We start the CI and link it to the check run ID; gitlab_ci_hook() will then update the check run status.
    """

    headers = dict(request.headers)

    signature = 'sha256=' + hmac.new(GITHUB_APP_SECRET, request.data, hashlib.sha256).hexdigest()
    if signature != headers.get("X-Hub-Signature-256"):
        return log_response("Invalid signature\n", 403)

    data = request.json

    event = headers.get("X-Github-Event", "")

    if event == "pull_request" and data.get("action", "") in ('opened', 'synchronize'):
        pull_request = data["pull_request"]

        username = data["sender"]["login"]
        branch = pull_request["head"]["ref"]
        head_sha = pull_request["head"]["sha"]
        clone_url = pull_request["head"]["repo"]["clone_url"]
        base_url = pull_request["base"]["repo"]["clone_url"]

    elif event in ("check_suite", "check_run") and data.get("action", "") in ('requested', 'rerequested'):
        check_suite = data["check_suite"] if event == "check_suite" else data["check_run"]["check_suite"]

        username = data["sender"]["login"]
        branch = check_suite["head_branch"]
        head_sha = check_suite["head_sha"]
        clone_url = data["repository"]["clone_url"]
        base_url = clone_url

    else:
        return "Unsupported event\n", 202

    assert branch is not None

    r = requests.post(
        f"{GITHUB_API_URL}/repos/{data['repository']['full_name']}/check-runs",
        headers=github_headers(),
        json={
            "name": "rev.ng CI",
            "head_sha": head_sha
        }
    )
    if r.status_code not in (200, 201, 202):
        return log_response(f"Check run creation failed:\n{r.content.decode(errors='replace')}\n", r.status_code)

    check_run = r.json()

    trigger_ci(
        hub_to_lab(username),
        clone_url,
        base_url,
        f'refs/heads/{branch}',
        {
            "platform": "github",
            "github_repository_name": data['repository']['full_name'],
            "github_check_run_id": check_run['id'],
            "triggering_user": username
        }
    )

    return "All good\n", 200
