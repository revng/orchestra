# Status of revng-distributable tests

## How to run the tests

To run revng-distributable tests, use `orc install --test revng-distributable`.
By default, tests are run on all supported distros using podman and xvfb.
The test mode can be changed by adding the following to `user_options.yml`:

```yml
#@overlay/replace
cold_revng_test_method: podman-xvfb
```

See the supported test modes in `revng_distributable.yml`.

## Known-working test modes

The tests work on the following distros (podman+xvfb):

- Archlinux
- Centos {7,8}
- Debian {7,8,9,10}
- Fedora {29,30,31,32}
- Opensuse 15.2
- Ubuntu {16,18,20}.04
- Voidlinux

The tests also work running revng-ui directly on the host, using the running X11 server (`host-x11` test mode)

## Broken distros

- gentoo: need to revise the scripts which install dependencies
- opensuse 15.{0,1}: zypper segfaults
