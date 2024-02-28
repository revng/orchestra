This document will introduce you to some basic things you can try out with this rev.ng release.

# Installing dependencies

The binary distribution of rev.ng basically has no dependencies, we ship them all.
If you have been able to fetch and extract this archive, you should be good.

# How to update

Please consider this an unstable release and make sure you're always running the latest version, in particular before reporting problems.
In order to update, simply run:

```sh
./revng update
```

This command will attempt to fetch the latest available binary distribution.
In case of failure, every attempted change should be rolled back.

# Running `revng`

You can run any `revng` command either doing:

```sh
./revng [SUBCOMMAND] [ARGS...]
```

or:

```sh
source ./environment
revng [SUBCOMMAND] [ARGS...]
```

See [the docs](https://docs.rev.ng/) for information about using rev.ng.

# License

This package distributes several distinct software components.

The license of each component is stored in `root/share/orchestra/{component}.license` and covers all the files listed in the corresponding `.idx` file (`root/share/orchestra/{component}.idx`).

All the files not explicitly covered by the licenses listed in `root/share/orchestra` are copyright of rev.ng Srls. All right reserved.
