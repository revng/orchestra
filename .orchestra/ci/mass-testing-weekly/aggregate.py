#!/usr/bin/env python3

# This script aggregates multiple results of `mass-testing` in a single json
# file. It takes an input directory, which is expected to contain
# subdirectories, each one being a different run of mass-testing. It will read
# the `main.db` file of each one and then output a json file which has the
# following structure:
#
# ```
# <directory basename>: {
#   "OK": <number of inputs that have status "OK">
#   "FAILED": <number of inputs that have status "FAILED">
#   etc.
# }
# ```

import argparse
import json
import re
import sqlite3
from pathlib import Path


def get_data(input_dir: Path):
    connection = sqlite3.connect(input_dir / "main.db")
    cursor = connection.cursor()
    cursor.execute("SELECT status, count(*) FROM main GROUP BY status")
    return dict(cursor.fetchall())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output")
    args = parser.parse_args()

    result = {}
    for entry in args.input_dir.iterdir():
        if (
            entry.is_dir()
            and re.match(r"^\d+$", entry.name) is not None
            and (entry / "main.db").is_file()
        ):
            result[entry.name] = get_data(entry)

    with open(args.output, "w") as f:
        json.dump(result, f)


if __name__ == "__main__":
    main()
