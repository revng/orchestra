# Mass Testing tools

## What's this?

This directory contains tools related to handling binaries used in mass
testing. These are mostly concerned with two aspects:
* Manipulating S3 storage for uploading/downloading binaries for mass testing
  (`download-binaries`, `extract-binaries`, `s3`)
* Manipulating local files related to mass-testing (`generate-inclusions`,
  `generate-meta`)

## `S3_ENDPOINT`

The tools `download-binaries`, `extract-binaries` and `s3` use the
`S3_ENDPOINT` environment variable to interact with the S3 storage. The string
follows the following format:

```
s3(s)://<username>:<password>@<region>+<host:port>/<bucket name>/<path>
```

* `s3` | `s3s`: `s3` for plain HTTP, `s3s` for HTTPS
* `username`, `password`: the access_key_id and access_key, respectively
* `region`: the S3 region
* `host:port`: the S3 host, without the bucket prefix
* `bucket name`: the bucket's name (note: the trailing `/` is mandatory)
* `path`: subpath inside the bucket that will be prefixed to all requests

### `extract-binaries`

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
* `macho`: only consider files with a Mach-O or Fat header
* `pe`: only consider files with the PE/COFF header
* `windows`: subset of `pe` which also excludes some file extensions which are
  valid PE/COFF but do not contain any `.text`

#### Example extraction

```bash
# Set the endpoint with an account that can write to S3 arbitrary files
export S3_ENDPOINT="..."
# Needed for the python dependencies and `revng mass-testing dump-sections`
orc install revng

orc shell

# 13_binaries is a directory with executables
./extract-binaries 13_binaries 10_binaries.yml

# Download, extract and upload android images
./extract-binaries --extractor android_sdat --filter elf \
    'https://dl.google.com/dl/android/aosp/shamu-ota-n8i11f-b4de4046.zip' \
    android_7.1.1_armv7h_nexus6.yml

./extract-binaries --extractor android_treble --filter elf \
    'https://dl.google.com/dl/android/aosp/oriole-ota-sq3a.220605.009.b1-e5bb789d.zip' \
    android_12.1.0_aarch64_pixel6.yml

# Download, extract and upload an ubuntu live image
./extract-binaries --extractor linux_live --filter elf \
    'https://www.releases.ubuntu.com/22.04/ubuntu-22.04.4-desktop-amd64.iso' \
    ubuntu_22.04.4_x86_64.yml

# Download, extract and upload a Windows 10 image
./extract-binaries --extractor windows_iso --filter windows windows.iso win10.yml
```

### `download-binaries`

This tool is used to download files given one or more specification `.yml` files.

### `generate-inclusions`

This tool, given a `main.db` database from a report, will generate a CSV file
with all the passed tests and additional (time, max_rss) resource usage
information.

### `generate-meta`

This script generates additional parts of `meta.yml` which will be added on top
of revng's installed `meta.yml` file.
