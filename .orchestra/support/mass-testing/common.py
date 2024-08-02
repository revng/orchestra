#
# This file is distributed under the MIT License. See LICENSE.md for details.
#

import os
import re
from dataclasses import asdict, dataclass, field
from hashlib import file_digest
from pathlib import Path
from typing import List

import boto3
from botocore.exceptions import ClientError as S3ClientError
from mypy_boto3_s3 import S3Client as S3ClientOrig


@dataclass
class BinaryEntry:
    name: str
    size: int
    text_size: int
    hash: str  # noqa: A003
    _path: Path
    sources: List[str] = field(default_factory=list)
    tags: List[str] = field(default_factory=list)

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
    def __init__(self, client: S3ClientOrig, bucket: str, path: str):
        self.client = client
        self.bucket = bucket
        self.path = path

    def _get_key(self, name: str) -> str:
        return os.path.join(self.path, name) if name != "" else self.path

    def _object_exists(self, key: str) -> bool:
        try:
            self.client.head_object(Key=key, Bucket=self.bucket)
            return True
        except S3ClientError as ex:
            if ex.response["Error"]["Code"] == "404":
                return False
            raise ex

    def put_object(self, name: str, path: str, skip_if_exists: bool = False):
        key = self._get_key(name)
        if skip_if_exists and self._object_exists(key):
            return

        self.client.upload_file(
            Filename=path, Key=key, Bucket=self.bucket, ExtraArgs={"ACL": "private"}
        )

    def get_object(self, name: str, path: str):
        key = self._get_key(name)
        self.client.download_file(Key=key, Bucket=self.bucket, Filename=path)

    def read_object(self, name: str) -> bytes:
        key = self._get_key(name)
        req = self.client.get_object(Key=key, Bucket=self.bucket)
        return req["Body"].read()


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

    session = boto3.session.Session()
    proto = "https" if match_obj["proto"] == "s3s" else "http"
    client = session.client(
        "s3",
        endpoint_url=f"{proto}://{match_obj['host']}",
        region_name=match_obj["region"],
        aws_access_key_id=match_obj["username"],
        aws_secret_access_key=match_obj["password"],
    )
    return S3Client(client, match_obj["bucket"], match_obj["path"])


def hash_file(path: Path | str) -> str:
    with open(path, "rb") as f:
        digest = file_digest(f, "sha256")
    return digest.hexdigest()
