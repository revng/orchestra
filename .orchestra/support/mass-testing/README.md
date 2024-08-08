# Mass Testing tools

## What's this?

This directory contains tools related to handling binaries used in mass testing

### `extract_binaries`

This tool is used to extract binaries from various sources and upload them to S3.
The two main parameters that control the behavior:
* `--extractor`: the script that will take care of extracting files from the
  source (e.g. unpacking files from an iso image). The extractor can be omitted
  if the input is a directory.
* `--filter`: a filtering mechanism to only consider some files. Omitting it
  will result in all files being uploaded to S3.

#### Currently implemented `extractor`s

* `android_sdat`: extract android zip files from Lollipop (5.0) onwards.
  Requires [`sdat2img.py`](https://github.com/xpirt/sdat2img) and `p7zip` to
  be present on `PATH`
* `android_treble`: extract android zip files which use Project Treble format.
  Requires [`android-ota-extractor`](https://github.com/tobyxdd/android-ota-payload-extractor)
  and `p7zip` to be present on `PATH`
* `linux_live`: extract files from most linux live isos, including squashfs images and snaps.
  Requires `p7zip`
* `windows_iso`: extract files from a windows installation iso. Requires
  [`wimlib`](https://wimlib.net/) and `p7zip` to be installed.

#### Currently implemented `filter`s

* `elf`: only consider files with the ELF header
* `macho`: only consider files with the Mach-O header
* `pe`: only consider files with the PE/COFF header
* `windows`: subset of `pe` which also excludes some file extensions which are
  valid PE/COFF but do not contain any `.text`


### `download_binaries`

This tool is used to download files given one or more specification `.yml` files.

### `generate_inclusions`

This tool, given a `main.db` database from a report, will generate a YAML file
which includes all tests which passed.
