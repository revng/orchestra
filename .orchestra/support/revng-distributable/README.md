This document will introduce you to some basic things you can try out with this rev.ng release.

# Installing dependencies

The following command will print the commands you need to run in order to install rev.ng's dependencies:

```sh
./root/bin/install-revng-dependencies --pretend
```

Remove `--pretend` in order to run the commands.

Many Linux distributions are supported out of the box.
If you use Ubuntu derivatives, you can pretend the be on Ubuntu 20.04 as follows:

```sh
./root/bin/install-revng-dependencies --pretend ubuntu 20.04
```

# How to update

Please consider this an unstable release and make sure you're always running the latest version.
In order to update, simply run:

```sh
./revng update
```

# Lifting for decompilation

To lift an exectutable and pre-process it:

```sh
./revng \
  lift \
  -g ll \
  root/share/revng/qa/tests/runtime/x86_64/compiled/calc \
  /tmp/calc.ll

./revng \
  opt \
  -S \
  --detect-abi \
  --isolate \
  --disable-enforce-abi-safety-checks \
  --enforce-abi \
  /tmp/calc.ll \
  -o /tmp/calc.for-decompilation.ll
```

In future releases we will provide handier command line tools.

# Translating for re-execution

To test the static binary translator use `revng-translate`.

```sh
./revng \
  translate \
  -i \
  root/share/revng/qa/tests/runtime/x86_64/compiled/calc \
  -o /tmp/calc.translated

/tmp/calc.translated '(+ 3 5)'
```

# License

This package distributes several distinct software components.

The license of each component is stored in `root/share/orchestra/{component}.license` and covers all the files listed in the corresponding `.idx` file (`root/share/orchestra/{component}.idx`).

All the files not explicitly covered by the licenses listed in `root/share/orchestra` are copyright of rev.ng Srls. All right reserved.
