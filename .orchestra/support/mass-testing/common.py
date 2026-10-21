#
# This file is distributed under the MIT License. See LICENSE.md for details.
#

import os
import re
from dataclasses import asdict, dataclass, field
from hashlib import file_digest
from pathlib import Path

import httpx2

httpx2.alias_httpx()

from httpx_auth import AWS4Auth  # noqa: E402


@dataclass
class BinaryEntry:
    name: str
    size: int
    text_size: int
    hash: str  # noqa: A003
    _path: Path
    sources: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)

    @staticmethod
    def from_dict(dict_: dict) -> "BinaryEntry":
        return BinaryEntry(
            dict_["name"],
            dict_["size"],
            dict_["text_size"],
            dict_["hash"],
            Path(),
            dict_["sources"],
            dict_.get("tags", []),
        )

    def to_dict(self):
        res = asdict(self)
        del res["_path"]
        if len(res["tags"]) == 0:
            del res["tags"]
        return res


class S3Client:
    def __init__(self, client: httpx2.Client, bucket: str, path: str):
        self.client = client
        self.bucket = bucket
        self.path = path

    def _get_url(self, name: str) -> httpx2.URL:
        key = os.path.join(self.path, name) if name != "" else self.path
        return self.client.base_url.copy_with(path=f"/{self.bucket}/{key}")

    def _object_exists(self, url: httpx2.URL) -> bool:
        response = self.client.head(url)
        if response.status_code == 404:
            return False
        response.raise_for_status()
        return True

    def put_object(self, name: str, path: str, skip_if_exists: bool = False):
        url = self._get_url(name)
        if skip_if_exists and self._object_exists(url):
            return

        with open(path, "rb") as input_file:
            content = input_file.read()

        response = self.client.put(url, content=content, headers={"x-amz-acl": "private"})
        response.raise_for_status()

    def get_object(self, name: str, path: str):
        with self.client.stream("GET", self._get_url(name)) as response:
            response.raise_for_status()
            with open(path, "wb") as output_file:
                for chunk in response.iter_bytes():
                    output_file.write(chunk)

    def read_object(self, name: str) -> bytes:
        response = self.client.get(self._get_url(name))
        response.raise_for_status()
        return response.content


def get_s3_client(endpoint: str | None = None) -> S3Client | None:
    if endpoint is None:
        endpoint = os.environ["S3_ENDPOINT"]

    # Url format is:
    # s3(s)://<username>:<password>@<region>+<host:port>/<bucket name>/<path>
    match_obj = re.match(
        r"^(?P<proto>s3(|s))://(?P<username>[^/]*):(?P<password>[^/]*)@"
        r"(?P<region>[^/]*)\+(?P<host>[^/]*)/(?P<bucket>[^/]+)/(?P<path>.*)$",
        endpoint,
    )
    if match_obj is None:
        raise ValueError("S3 endpoint invalid")

    proto = "https" if match_obj["proto"] == "s3s" else "http"
    client = httpx2.Client(
        base_url=f"{proto}://{match_obj['host']}",
        auth=AWS4Auth(  # type: ignore[arg-type]
            access_id=match_obj["username"],
            secret_key=match_obj["password"],
            region=match_obj["region"],
            service="s3",
        ),
        timeout=httpx2.Timeout(60.0),
    )
    return S3Client(client, match_obj["bucket"], match_obj["path"])


def hash_file(path: Path | str) -> str:
    with open(path, "rb") as f:
        digest = file_digest(f, "sha256")
    return digest.hexdigest()
