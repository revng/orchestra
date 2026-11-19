#!/usr/bin/env python3

import argparse
import os
import shlex
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from string import Template
from subprocess import PIPE, STDOUT
from subprocess import run as process_run
from typing import TypedDict

import yaml

CONFIG_FILE = (Path(__file__) / "../multi-encode.yml").resolve()


@dataclass
class ExecutionResult:
    code: int
    output: str


class Config(TypedDict):
    parts: dict[str, str]
    preamble: str
    encodings: list[str]


def run_string(cmd: str) -> ExecutionResult:
    process = process_run(shlex.split(cmd), stdout=PIPE, stderr=STDOUT, text=True)
    return ExecutionResult(process.returncode, process.stdout)


def run(input_: str, output: str) -> int:
    cpu_count = len(os.sched_getaffinity(0))
    with open(CONFIG_FILE) as f:
        config: Config = yaml.safe_load(f)

    encoding_cmds = []
    for idx, encoding in enumerate(config["encodings"]):
        variables = {**config["parts"], "CPU8": str(max(8, min(1, cpu_count)))}
        template = Template(encoding).substitute(variables)
        ext = "webm" if template.endswith("webm") else "mp4"
        string = f"{config['preamble']} {input_} " + template + f" {output}_{idx + 1:02}.{ext} -y"
        encoding_cmds.append(string)

    exit_code = 0
    # NOTE: the '2' below has been empirically determined, the value in reality
    # depends on:
    # * How multi-threaded the encoder is
    # * How memory-hungry
    # These variables are hard to determine without intimate knowledge of the
    # encoders used. Given the current configuration this fixed value should
    # work in most cases
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(run_string, cmd) for cmd in encoding_cmds]
        for completed_future in as_completed(futures):
            result = completed_future.result()
            if result.code != 0:
                sys.stderr.write("Failed encoding! Error log:")
                sys.stderr.write(result.output)
                exit_code = 1

    return exit_code


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input", required=True, help="Input file")
    parser.add_argument("-o", "--output", required=True, help="Output prefix")
    args = parser.parse_args()
    sys.exit(run(args.input, args.output))


if __name__ == "__main__":
    main()
