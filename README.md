# rev.ng orchestra config

This repository contains the orchestra configuration for rev.ng.

To get started:

* install orchestra (follow the  instructions in its repo)
* run `orchestra components` to generate the default user configuration
* edit `.orchestra/config/user_remotes.yml` to add your remotes, like so:
  ```
  #@data/values
  ---
  #@overlay/match missing_ok=True
  remote_base_urls:
    - fcremo: "git@rev.ng:fcremo"
    - internal: "git@rev.ng:revng-internal"
    - private: "git@rev.ng:revng-private"
  
  #@overlay/match missing_ok=True
  binary_archives:
    - fcremo: "git@rev.ng:fcremo/binary-archives"
  ```
* run `orchestra update`
* try `orchestra install revng` or `orchestra install ui/cold-revng`

## User configuration

The following options can be set in `.orchestra/config/user_options.yml`:

* `parallelism`: this value is passed as `-j` argument `make` and `ninja`
* `build_from_source`: binary archives will not be used for components in this list
* `nonredistributable_base_url`: used to fetch MacOS-related and spec archives
* `paths`: can be used to override various locations (root, build dir, etc).
  Must be absolute paths. Untested!

## Writing components

See `writing_components.md`.
