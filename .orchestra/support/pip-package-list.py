#!/usr/bin/env python3

import json
import os
import subprocess
import sys
import yaml

from glob import glob
from pathlib import Path


def log(message):
    sys.stderr.write(message + "\n")


def run(argv):
    return subprocess.run(argv,
                          check=True,
                          stdout=subprocess.PIPE).stdout.decode("utf8")


def run_json(argv):
    return json.loads(run(argv))


def run_yaml(argv):
    return yaml.safe_load(run(argv))


def compute_dependencies(component_name):
    result = set()

    # Get hash mateiral
    hash_material = run_yaml(["orc",
                              "inspect",
                              "component",
                              "hash-material",
                              component_name])

    # Extract all dependencies
    for component in hash_material:
        for build in component["builds"].values():
            for dependency in build["dependencies"] + build["build_dependencies"]:
                result.add(dependency)

    return result


def inspect_installation(component, dependencies):
    to_exclude = set()
    banned = set()
    packages_dir = Path(os.environ["ORCHESTRA_ROOT"]) / "share/orchestra/python-packages"
    for path in map(Path, glob(f"{packages_dir}/*.txt")):
        component_name = path.stem
        if component_name == component:
            continue

        package_set = set(path.read_text().strip().split("\n"))

        if component_name in dependencies:
            to_exclude.update(package_set)
        else:
            banned.update(package_set)

    return to_exclude, banned


def compute_packages(argv):
    result = {}

    report = run_json(["python",
                       "-m", "pip",
                       "install",
                       "--report", "-",
                       "-q",
                       "--dry-run",
                       "--compile",
                       "--ignore-installed"]
                      + argv)

    for package in report["install"]:
        name = package["metadata"]["name"]
        url = package["download_info"]["url"]
        result[name] = url

    return result


def main():
    component = sys.argv[1]
    pip_arguments = sys.argv[2:]

    dependencies = compute_dependencies(component)
    to_exclude, banned = inspect_installation(component, dependencies)
    all_packages = compute_packages(pip_arguments)

    to_install = {
        name: url
        for name, url
        in all_packages.items()
        if name not in to_exclude
    }

    bad = banned & set(to_install.keys())
    if len(bad) > 0:
        log("The following packages are also installed by a non-dependency:")
        log("\n".join(f"  {name}" for name in bad))
        return 1

    print("\n".join([f"{name},{url}"
                     for name, url
                     in to_install.items()]))

    return 0


if __name__ == "__main__":
    sys.exit(main())
