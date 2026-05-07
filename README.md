# soem-deb

This repository manages the upstream SOEM source as a git submodule (pinned to v2.0.0) and builds the Debian development package `libsoem-dev`.

## Directory Structure

- `SOEM/`: Upstream source code (submodule).
- `debian/`: Debian packaging configurations (control, rules, etc.).

## Synchronizing Submodules

When cloning for the first time or after updating `.gitmodules`, execute:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## Local Build

Ensure you have installed the required build dependencies, then use the standard Debian packaging command:

```bash
dpkg-buildpackage -us -uc -b
```

## Artifact Location

Final `.deb` artifacts are generated in the parent directory (sibling to `soem-deb`):

```bash
../libsoem-dev_<version>_<arch>.deb
```

## GitHub Actions

The GitHub Actions workflow now natively calls `dpkg-buildpackage` to automate multi-architecture builds. All logic for compilation and packaging has been thoroughly standardized into the `debian/` directory.

## Integration via CMake / pkg-config

This package installs SOEM into directories that comply with the Linux standard library layout:

- **Libraries**: `/usr/lib/<triplet>/libsoem.so`
- **CMake Config**: `/usr/lib/<triplet>/cmake/soem/`
- **Compatibility Symlink**: `/usr/lib/cmake/soem`
- **pkg-config**: `/usr/lib/<triplet>/pkgconfig/soem.pc`

During the packaging phase, the CMake export files are rewritten to ensure the library paths correctly point to the multiarch directory, rather than the default non-Debian layout used upstream.

### Preferred Integration (CMake)

It is highly recommended to use the config-mode search:

```cmake
find_package(soem CONFIG QUIET)
```

### Fallback Integration (pkg-config)

If the environment only supports `pkg-config`, use:

```cmake
find_package(PkgConfig QUIET)
pkg_check_modules(SOEM QUIET soem)
```
