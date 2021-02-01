#!/usr/bin/env python3

import base64
import hashlib
import hmac
import json
import os

from datetime import date, timedelta
from textwrap import dedent

import gitlab
from flask import Flask, request


app = Flask(__name__)
config_file = os.environ.get("CONFIG_FILE_PATH", "config.json")


def get_env_or_fail(var_name):
    value = os.getenv(var_name)
    if value is None:
        raise Exception(f"Environment variable {var_name} is not set!")
    return value


GITLAB_SECRET = get_env_or_fail("GITLAB_SECRET")
GITHUB_SECRET = get_env_or_fail("GITHUB_SECRET").encode("utf-8")
revng_push_ci_private_key_b64 = get_env_or_fail("REVNG_PUSH_CI_PRIVATE_KEY_BASE64")
revng_push_ci_private_key = base64.b64decode(revng_push_ci_private_key_b64).decode("utf-8")
ADMIN_TOKEN = get_env_or_fail("GITLAB_ADMIN_TOKEN")

try:
    with open(config_file) as f:
        config = json.load(f)
except IOError:
    print(f"Could not open configuration file ({config_file})")
    exit(1)

allowed_to_push = config["allowed_to_push"]
GITLAB_URL = config["gitlab_url"]
PROJECT_ID = config["project_id"]
BRANCH = config["branch"]
mapping = config["github_to_gitlab_mapping"]
default_user = config["default_user"]
ci_user = config["ci_user"]


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


def hub_to_lab(username):
    if username not in mapping:
        return default_user
    else:
        return mapping[username]


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


def trigger_ci(username, repo_url, ref, before, after):
    # Ignore pushes by the CI itself
    if username == ci_user:
        return

    admin_gl = gitlab.Gitlab(GITLAB_URL, private_token=ADMIN_TOKEN)
    admin_gl.auth()

    matching = admin_gl.users.list(username=username)
    if len(matching) != 1:
        raise Exception("Unexpected number of users matching " + username)
    user_id = matching[0].id

    user = admin_gl.users.get(user_id)
    with ImpersonationToken(user) as token:
        user_gl = gitlab.Gitlab(GITLAB_URL, private_token=token)
        user_gl.auth()
        project = user_gl.projects.get(PROJECT_ID)

        variables = {
            "TARGET_COMPONENTS_URL": repo_url,
            "COMMIT_BEFORE": before,
            "COMMIT_AFTER": after,
            "PUSHED_REF": ref
        }

        if username in allowed_to_push:
            variables["BASE_USER_OPTIONS_YML"] = pusher_user_options
            variables["SSH_PRIVATE_KEY"] = revng_push_ci_private_key

        parameters = {
            "ref": BRANCH,
            "variables": [{"key": key, "value": value}
                          for key, value
                          in variables.items()]
        }
        print(json.dumps(parameters, indent=2))
        pipeline = project.pipelines.create(parameters)


@app.route('/ci-hook/gitlab', methods=["POST"])
def gitlab_hook():
    headers = dict(request.headers)
    if headers.get("X-Gitlab-Token", "") != GITLAB_SECRET:
        return "Invalid token\n", 403

    data = request.json
    trigger_ci(data["user_username"],
               data["project"]["git_http_url"] + " " + data["project"]["git_ssh_url"],
               data["ref"],
               data["before"],
               data["after"])
    return "All good\n"


@app.route('/ci-hook/github', methods=["POST"])
def github_hook():
    headers = dict(request.headers)
    signature = 'sha256=' + hmac.new(GITHUB_SECRET, request.data, hashlib.sha256).hexdigest()
    if signature != headers.get("X-Hub-Signature-256"):
        return "Invalid signature\n", 403

    if headers.get("X-Github-Event", "") == "push":
        data = request.json
        trigger_ci(hub_to_lab(data["sender"]["login"]),
                   data["repository"]["clone_url"],
                   data["ref"],
                   data["before"],
                   data["after"])

    return "All good\n"
