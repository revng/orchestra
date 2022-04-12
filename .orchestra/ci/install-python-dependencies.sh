#!/bin/bash

set -e

PYTHON_DEPENDENCIES=(
  "black"
  "cmakelang"
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
  "pydot"
  "pyelftools"
  "pylint"
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
