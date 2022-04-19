#!/bin/bash

set -e

PYTHON_DEPENDENCIES=(
  "black"
  "cmakelang"
  "flake8"
  "flake8-breakpoint"
  "flake8-builtins"
  "flake8-comprehensions"
  "flake8-eradicate"
  "flake8-plugin-utils"
  "flake8-polyfill"
  "flake8-return"
  "flake8-simplify"
  "Jinja2"
  "grandiso"
  "graphlib-backport"
  "isort"
  "jsonschema"
  # lit version should always match clang-release and llvm version
  "lit==12.0.0"
  "mako"
  "meson==0.56.2"
  "mypy"
  "networkx"
  "pep8-naming"
  "pydot"
  "pyelftools"
  # pydot 3.0.2 introduced an incompatibility with pydot which is supposed to be resolved in a later version,
  # but still causes problems to us (for instance, monotone framework headers generation fails), so we request v2.4.7.
  # See https://github.com/pydot/pydot/issues/277
  "pyparsing==2.4.7"
  "pyyaml"
  "setuptools"
  "types-backports"
  "types-PyYAML"
  "types-requests"
  "types-urllib3"
  "wheel"
)

pip3 -q install --user --upgrade "${PYTHON_DEPENDENCIES[@]}"
