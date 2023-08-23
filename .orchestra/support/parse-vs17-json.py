#!/usr/bin/env python3

import json
import sys
import re


def log(message):
  sys.stderr.write(message + "\n")

def find_package(packages, id):
  for package in packages:
    if package["id"].lower() == id.lower():
      return package

  return None

def main():
    # Load data
    data = json.load(sys.stdin)

    # Keep only english
    packages = [package
                for package
                in data["packages"]
                if ("language" not in package
                    or package["language"].lower() == "en-us")]
    
    regexps = []
    
    for argument in sys.argv:
      regexps.append(re.compile(argument.lower()))
    
    selected_packages = dict()
    for package in packages:
      for regexp in regexps:
        if regexp.match(package["id"].lower()):
          assert package["id"] not in selected_packages
          selected_packages[package["id"]] = package
    
    missing = set()
    new_package = True
    while new_package:
      new_package = False
    
      for selected_package in list(selected_packages.values()):
        if "dependencies" not in selected_package:
          continue
    
        for dependency, data in selected_package["dependencies"].items():
    
          if type(data) is dict and "id" in data:
            dependency = data["id"]
    
          if dependency not in selected_packages:
            result = find_package(packages, dependency)
            if result is None:
              if dependency not in missing:
                missing.add(dependency)
                log(f"Cannot find package {dependency}")
            else:
              new_package = True
              selected_packages[dependency] = result
    
    total_size = 0
    print("id,file-name,sha256,url")
    for id in selected_packages:
      selected_package = find_package(packages, id)
    
      if "payloads" in selected_package:
        filenames = [payload["fileName"] for payload in selected_package["payloads"]]
        assert len(filenames) == len(set(filenames))
        for payload in selected_package["payloads"]:
          total_size += payload["size"]
          filename = payload["fileName"].replace("\\", "/")
          print(f"""{id},{filename},{payload["sha256"]},{payload["url"]}""")
    
    log(f"We need to download {int(total_size / 1024 ** 2)} MiB")

if __name__ == "__main__":
    sys.exit(main())
