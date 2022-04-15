# rev.ng orchestra configuration

This repository contains the orchestra configuration for rev.ng.

## Bootstrap

* Clone orchestra
  ```sh
  git clone https://github.com/revng/orchestra
  cd orchestra
  ```
* Install dependencies (currently Ubuntu-only):
  ```sh
  ./.orchestra/ci/install-dependencies.sh
  ```
* Install orchestra script
  ```sh
  pip3 cache remove orchestra
  pip3 install --user --force-reinstall https://github.com/revng/revng-orchestra/archive/master.zip
  ```
* Make sure `orc` is in PATH
  ```sh
  export PATH="$HOME/.local/bin:$PATH"
  ```
* Initialize default configuration (and list components)
  ```sh
  orc components
  ```

## Configuration for the public

The default configuration gives you read-only access to the rev.ng open source components.

If you want to work a fork of certain components the suggested workflow is to add your remote to the
repository as cloned by orchestra.
For example, to fork the `revng` project do the following:

```bash
# Ensure the revng component is cloned
orchestra clone revng
cd sources/revng
git remote add myremote <your-remote-url>
```

## Configuration for rev.ng developers

If you have access to rev.ng GitLab, in order to access private components, your configuration should be similar to the following:

```yaml
#@data/values
---
#@overlay/match missing_ok=True
remote_base_urls:
  - public: "git@github.com:revng"
  - private: "git@rev.ng:revng-private"

#@overlay/match missing_ok=True
binary_archives:
  - origin: "git@rev.ng:revng/binary-archives.git"
  - private: "git@rev.ng:revng-private/binary-archives.git"
```

## Installing from binary-archives

* Update `binary-archives` and information about remote repositories:
  ```sh
  orc update
  ```
* Install `revng`
  ```sh
  orc install revng
  ```

## Building from source

In order to build from source certain components, as opposed to fetch them from binary-archives, you need to list them in `.orchestra/config/user_options.yml`:

```yaml
#@overlay/replace
build_from_source:
  - revng
```

* Install and test `revng`
  ```sh
  orc install --test revng
  ```
* Manually build:
  ```sh
  orc shell -c revng
  ninja
  ctest -j$(nproc)
  ```

## Building from a fork

The recommended workflow is:

* Clone the component you want to fork
  ```sh
  orc clone <component>
  ```
* Add a remote to the component
  ```sh
  cd sources/<component>
  git remote add <myremotename> <remote-url>
  git fetch --all
  ```
* Switch to your branch
  ```sh
  cd sources/<component>
  git switch <myremotename>/<branch>
  git checkout -b <branch> <myremotename>/<branch>
  ```
* Update orchestra
  ```sh
  orc update
  ```

## How do I...

* **Q**: How do I set the number of parallel jobs for `make`/`ninja`?

  **A**: In `.orchestra/config/user_options.yml`:
  ```yaml
  parallelism: 4
  ```
* **Q**: How do I print the dependency graph to build a component?

  **A**: `orc graph $COMPONENT | xdot -`

* **Q**: How do I uninstall a component?

  **A**: `orc uninstall $COMPONENT`

* **Q**: Does orchestra leave files around my `$HOME` or elsewhere?

  **A**: No! By default orchestra places *everything* inside the folder containing the configuration

## Writing components

See `docs/writing_components.md`.
