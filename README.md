# rev.ng orchestra configuration

This repository contains the orchestra configuration for rev.ng.

## Bootstrap

* Install orchestra script
  ```sh
  pip3 install --user git+https://github.com/revng/revng-orchestra.git
  ```
* Make sure `orc` is in PATH
  ```sh
  export PATH="$HOME/.local/bin:$PATH"
  ```
* Clone orchestra
  ```sh
  git clone https://github.com/revng/orchestra
  cd orchestra
  ```
* Initialize default configuration (and list components)
  ```sh
  orc components
  ```

## Configuration for the public

The default configuration gives you read-only access to the rev.ng open source components.

If you have your own fork of certain components on GitHub, you need to customize `.orchestra/config/user_options.yml` as follows (note `$YOUR_GITHUB_USERNAME`):

```yaml
remote_base_urls:
  - $YOUR_GITHUB_USERNAME: "git@github.com:$YOUR_GITHUB_USERNAME"
  ...
```

## Configuration for rev.ng developers

If you have access to rev.ng GitLab, in order to access private components, your configuration should be similar to the following:

```yaml
#@data/values
---
#@overlay/match missing_ok=True
remote_base_urls:
  - $YOUR_GITHUB_USERNAME: "git@github.com:$YOUR_GITHUB_USERNAME"
  - $YOUR_GITLAB_USERNAME: "git@rev.ng:$YOUR_GITLAB_USERNAME"
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
  orc shell revng
  ninja
  ctest -j$(nproc)
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

## Writing components

See `docs/writing_components.md`.
