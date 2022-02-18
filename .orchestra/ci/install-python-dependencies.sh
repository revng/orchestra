#!/bin/bash

set -e

PYTHON_DEPENDENCIES=(
  setuptools
  wheel
  mako
  "meson==0.56.2"
  pyelftools
  # lit version should always match clang-release and llvm version
  "lit==12.0.0"
  # pydot 3.0.2 introduced an incompatibility with pydot which is supposed to be resolved in a later version,
  # but still causes problems to us (for instance, monotone framework headers generation fails), so we request v2.4.7.
  # See https://github.com/pydot/pydot/issues/277
  "pyparsing==2.4.7"
  pydot
  grandiso
  Jinja2
  datamodel-code-generator
)

pip3 -q install --user --upgrade "${PYTHON_DEPENDENCIES[@]}"
