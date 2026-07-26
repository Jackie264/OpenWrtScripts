# Building the package (.apk / .ipk)

The script `build-packages.sh` builds both the .apk and .ipk.
Use this script after making changes to any of the files.

The script spins up a small
Docker container to use the built-in build tools
to produce the package files.
It retrieves  `PKG_VERSION` and `PKG_RELEASE` from
the _Makefile_ for versioning.

The built packages are saved in:

- apk: $HOME/openwrt-sdk-build/bin/packages/mips_24kc/base/${PKGNAME}-${PKG_VERSION}-r${PKG_RELEASE}.apk

- ipk: $HOME/openwrt-sdk-build/bin/packages/mips_24kc/base/${PKGNAME}_${PKG_VERSION}-${PKG_RELEASE}_all.ipk

## Deploying for testing

The scripts `deploy-ipk.sh` and `deploy-apk.sh`
take a parameter of **root@\<router address>**
and ssh into the device, copy the package to the router,
and then install it.
You'll need to reconnect to the LuCI GUI to seen the update.

## Pushing to Github

There are three steps to publishing the scripts and packages:

1. Commit all the changes, and push to Github normally.
2. Use `build-packages.sh` then...
3. Run `release-to-github.sh` to create an updated
   release on the home page of the Github repo

## Background - old information from development

The remainder of this page may be outdated because
it was created during the development process.
I'm retaining it here so nothing important gets lost.

### build-apk.sh (apk-tools, OpenWrt 24.10+)

Builds a real, installable `luci-app-printable-label-<version>.apk`. Verified
against a real SDK-built `.apk`: identical file tree, install/upgrade/remove
scripts, and metadata (see "How it works" below) -- and installed with `apk
add` on a real router.

#### Requirements

Docker Desktop running. The script uses a tiny `alpine:3.24` image (~7MB,
pulled automatically on first use) to invoke the real `apk mkpkg`
command -- there's no persistent container or volume to set up.

#### Building

```bash
./build-apk.sh
```

**Note:** The packages version is saved in `PKG_VERSION`
in the `Makefile`. Bump that version when you make changes.
The `build-apk.sh` script copies that version number into
`htdocs/luci-static/resources/view/routerlabel.js`.

The `.apk` lands in
`~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-printable-label-<version>.apk`
(same path the old SDK-based workflow used, kept only for continuity with
the install steps below -- the `mips_24kc` subdirectory name isn't
meaningful anymore since the package is `noarch`). Old-version `.apk` files
aren't auto-removed -- delete stale ones so you don't accidentally install
the wrong version.

#### Installing on a router

**Quick path:** `./deploy-apk.sh [user@]router-address` — scp's the
already-built `.apk` and installs it with `apk`, clearing the menu cache
and restarting `rpcd`. The manual
steps below are what it automates.

```bash
APK=~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-printable-label-<version>.apk
scp -O "$APK" root@<router>:/tmp/
ssh root@<router> apk add --allow-untrusted /tmp/$(basename "$APK")
ssh root@<router> rm -f /tmp/luci-indexcache*
ssh root@<router> /etc/init.d/rpcd restart
```

`--allow-untrusted` is needed because this `.apk` isn't signed with a key
the router trusts (it would need to come from a real package repository
for that) -- fine for a locally-built test package.

If the router already has the loose-file version deployed (from the main
README's quick-iteration path), remove those first so there's no
ambiguity between package-managed and stray files:

```bash
ssh root@<router> '
  rm -f /www/luci-static/resources/routerlabel.js
  rm -f /www/luci-static/resources/view/routerlabel.js
  rm -f /usr/share/luci/menu.d/luci-app-printable-label.json
  rm -f /usr/share/rpcd/acl.d/luci-app-printable-label.json
'
```

To upgrade to a newer build later: `apk add --allow-untrusted
/tmp/luci-app-printable-label-<new-version>.apk` again -- `apk` handles the
upgrade in place. To remove entirely: `apk del luci-app-printable-label`.

### build-ipk.sh (opkg, OpenWrt 23.05 and earlier)

Builds `luci-app-printable-label_<version>-<release>_all.ipk`. Same source
files as `build-apk.sh`, just packaged in the `.ipk` format opkg expects.

#### Requirements (build-ipk.sh)

Docker Desktop running, same as `build-apk.sh` -- `alpine:3.24` again, for a
known-good `tar`.

#### Building the .ipk

```bash
./build-ipk.sh
```

Also syncs `APP_VERSION` in `routerlabel.js` to the Makefile's
`PKG_VERSION`, same as `build-apk.sh` -- harmless to run both.

The `.ipk` lands in the same directory as the `.apk`,
`~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-printable-label_<version>-<release>_all.ipk`.

#### Installing the .ipk on a router

**Quick path:** `./deploy-ipk.sh [user@]router-address` — scp's the
already-built `.ipk` and installs it with `opkg`, clearing the menu cache
and restarting `rpcd`. The manual steps below are what it automates.

```bash
IPK=~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-printable-label_<version>-<release>_all.ipk
scp -O "$IPK" root@<router>:/tmp/
ssh root@<router> opkg install /tmp/$(basename "$IPK")
ssh root@<router> rm -f /tmp/luci-indexcache*
ssh root@<router> /etc/init.d/rpcd restart
```

Unlike `apk add`, plain `opkg install` also handles upgrades in place (no
separate upgrade flag needed) and doesn't require an `--allow-untrusted`
equivalent for a locally-built, unsigned package -- opkg just isn't
signature-verifying by default the way apk is. To remove: `opkg remove
luci-app-printable-label`.

If the router already has the loose-file version deployed, remove those
first -- same four files, same commands as in the `build-apk.sh` section
above.

### How it works

#### .apk

OpenWrt's current package manager is `apk-tools` v3, and its `.apk` files
are a custom binary format ("ADB", Alpine Dependency Binary) -- not a
zip/tar concatenation like the old `.ipk`/`apk` v2 formats. Hand-writing
that binary format isn't practical, but the OpenWrt SDK doesn't do that
either: for a pure LuCI app (`LUCI_PKGARCH:=all`, no compiled code), the
SDK's build process ultimately just calls `apk mkpkg` on the package's
files, generated control scripts, and metadata. `build-apk.sh` does the
same thing directly:

- Assembles the 4 files this package actually installs (2 `.js`, 2 `.json`)
  into the exact target file tree.
- Generates `lib/apk/packages/luci-app-printable-label.list`, a manifest apk
  expects at that fixed path (this is what `luci.mk` generates for every
  `luci-app-*` package).
- Generates the standard `post-install`/`pre-deinstall`/`post-upgrade`
  scripts that `luci.mk` attaches to every `luci-app-*` package (they call
  `add_group_and_user`/`default_postinst`/`default_prerm` from
  `/lib/functions.sh` on the router).
- Reads name/version/license/maintainer/description/depends straight from
  the `Makefile`, so there's one source of truth.
- Runs `apk mkpkg --info ... --script ... --files ... --output ...` inside
  `alpine:3.24` (the first stable Alpine release with `apk-tools` 3.x) and
  writes the resulting `.apk` to the bind-mounted output directory.

Since there's no compiled code and no cross-compilation, none of the SDK's
toolchain, feeds, or `.config` machinery is actually needed -- it exists to
support packages that do compile something.

#### .ipk

An `.ipk` is much simpler than an `.apk`: it's a gzip-compressed tar of
three members, in order -- `debian-binary` (literally the text `2.0`),
`control.tar.gz` (a `control` metadata file plus `postinst`/`prerm`
scripts), and `data.tar.gz` (the file tree to install). This looks like the
old Debian `ar`-archive package format at a glance (`file(1)` even reports
it as "Debian binary package"), but it isn't one -- OpenWrt's opkg
(`libopkg/pkg_extract.c`'s `deb_extract`) unconditionally pipes the whole
file through `gzip -d` before reading it as a tar stream, so it only works
if the outer container really is `tar.gz`. An `ar`-format outer container
(the actual dpkg/.deb format, and what `opkg-build`'s undocumented default
still produces) fails `gzip -d` silently, extracts to nothing, and opkg
reports `pkg_init_from_file: Malformed package file` -- confirmed by
tracing the failure through opkg's actual source (`libopkg/pkg.c` ->
`pkg_parse.c` -> `pkg_extract.c` -> `libbb/unarchive.c`/`gzip.c`) after a
build using `ar rc` for the outer container failed exactly that way on
real hardware.

`build-ipk.sh` assembles the same file tree and `Makefile`-derived metadata
as `build-apk.sh`, but instead of one purpose-built `postinst` +
`post-upgrade` pair, opkg calls a single `postinst` for both fresh installs
and upgrades (exporting `PKG_UPGRADE=1` itself in the upgrade case) --
so there's one script instead of two, otherwise identical
`add_group_and_user`/`default_postinst`/`default_prerm` logic.

`tar` runs inside `alpine:3.24` rather than on the host: macOS's BSD `tar`
has enough format quirks (AppleDouble resource-fork entries, differing
owner/group flags) to make it worth avoiding entirely for a binary archive
format, even one this simple.

### Architecture note: targets ucode-era LuCI, not classic Lua LuCI

Current OpenWrt (confirmed on a 2026-dated snapshot build, OpenWrt 25.12.5)
has fully migrated LuCI's controller layer from Lua to ucode, and dropped
`/usr/lib/lua/luci` entirely. Third-party apps in this LuCI version don't
ship their own controller code at all — menu entries are plain JSON files
in `/usr/share/luci/menu.d/`, and JS views fetch data directly via LuCI's
existing client-side `fs`, `uci`, and `rpc` JS modules (the same modules
`luci-app-sqm`'s `sqm.js` uses), gated by an ACL file in
`/usr/share/rpcd/acl.d/`. There is no controller in this app for that
reason — all the logic that used to live in a Lua controller now lives in
`htdocs/luci-static/resources/routerlabel.js`, loaded by the view via
`'require routerlabel'`.

An earlier version of this app used a Lua controller + `luasrc/` module;
that approach doesn't work on current OpenWrt and was removed.

### Testing on a router

**Recommended:** `./build-apk.sh && ./deploy-apk.sh [user@]router-address`
from this directory — builds the `.apk` (see [BUILDING.md](./BUILDING.md))
and installs it on the router with `apk`, clearing the menu cache and
restarting `rpcd` for you.

### Mock data for local development

Once the page is deployed and loading, append `?mock=1` to its URL (e.g.
`.../admin/services/routerlabel?mock=1`) to see fixed sample values instead
of real ubus/uci/`/proc/mtd` data. Useful for iterating on layout/styling
without needing to reconfigure wifi or uci each time. No redeploy needed
to toggle it -- just edit the URL. The mock values live in `getMockData()`
in `htdocs/luci-static/resources/view/routerlabel.js`.

This can't eliminate the need for a router entirely: the page still runs
inside LuCI's own JS framework (`E()`, `_()`, `view.extend`, etc.), which
only exists once a real router has loaded it — there's no standalone/local
way to preview this page outside LuCI.

### Running the unit tests locally

`htdocs/luci-static/resources/routerlabel.js` has no LuCI/browser
dependencies and can be tested with plain `node` — no router needed:

```bash
cd ../tests
node test_routerlabel_util.js
```
