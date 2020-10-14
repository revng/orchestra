# Writing a component

This document explains the conventions used in this configuration.
Before reading it you should read orchestra documentation
and understand the configuration format used by orchestra.

TL;DR: an orchestra configuration is a collection of **components** and other options.
Components consist mainly of a collection of builds.

```yaml
components:
    component_name:
        builds:
            default:
                configure: |
                    download_sources --to "$SOURCE_DIR"
                    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"
                    "$SOURCE_DIR/configure"
                install: |
                    cd "$BUILD_DIR"
                    make
                    make install
                dependencies:
                    - some_other_component
options:
    some_option: option_value
```

Orchestra preprocesses the configuration using [ytt](https://get-ytt.io/).
To get familiar with `ytt` syntax you can follow the tutorial on the site
and read some of the existing configuration.

## Defining a new component

It is possible to edit `.orchestra/config/components.yml` 
and directly add a component there, however this is discouraged.

To define a new component in a separate file use the following template
and save it in `.orchestra/config/components/<component_name>.yml`.

```yaml
#@ load("@ytt:overlay", "overlay")

#@overlay/match by=overlay.all, expects=1
#@overlay/match-child-defaults missing_ok=True
---
components:
  mycomponent:
    builds:
      default:
        configure: |
          echo "Configure script"
        install: |
          echo "Install script"
```

## Convenience functions

Many components have repetitive patterns,
so they are defined using some functions to factor common parts.

All functions must be explicitly imported using a `load` statement.

### Components with a single build

Components with a single build can be defined using `single_build_component`

Take `elfutils` for example:

```yaml
#@ load("@ytt:overlay", "overlay")
#@ load("/lib/create_component.lib.yml", "single_build_component")

---
#@ def _elfutils_args():
configure: |
  mkdir -p "$BUILD_DIR"
  echo "Rest of the configure script omitted..."
build_system: make
dependencies:
  - toolchain/host/gcc
  - zlib
#@ end

#@overlay/match by=overlay.all, expects=1
#@overlay/match-child-defaults missing_ok=True
---
components:
  elfutils: #@ single_build_component(**_elfutils_args())
``` 

`single_build_component` has many parameters, refer to its definition.

### CMake components

`typical_cmake_builds` will define builds for various optimization levels.

See `caliban` as an example:
```yaml
#@ load("@ytt:overlay", "overlay")

#@ load("/lib/optimization_flavors.lib.yml", "typical_project_flavors")
#@ load("/lib/cmake.lib.yml", "cmake_boost_configuration", "typical_cmake_builds")

#@ load("/global_options.lib.yml", "options")

---
#@ def build_args():
extra_cmake_args: #@ cmake_boost_configuration
build_dependencies:
  - cmake
dependencies:
  - clang-release
  #! rest of the dependencies...
use_asan: false
#@ end

#@overlay/match by=overlay.all, expects=1
#@overlay/match-child-defaults missing_ok=True
---
components:
  caliban:
    repository: caliban
    builds: #@ typical_cmake_builds(**build_args())
```

### Common optimization levels

`.orchestra/config/lib/optimization_flavors.lib.yml` 
contains some common options useful for defining various builds.

