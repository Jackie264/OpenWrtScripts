#! /bin/sh

# Build luci-app-router-label_<version>-<release>_all.ipk for opkg (OpenWrt
# 23.05 and earlier -- 24.10+ uses apk instead, see build-apk.sh). An .ipk is
# just an `ar` archive of debian-binary + control.tar.gz + data.tar.gz, the
# old Debian package format -- no SDK/opkg-utils needed to produce one, and
# (like the .apk) nothing here is cross-compiled since this package is pure
# JS/JSON. See BUILDING.md.
#
# Runs `ar`/`tar` inside alpine:3.24 rather than on the host, purely to get
# a known-good ar/tar (macOS's BSD ar/tar have enough format quirks -- AppleDouble
# resource-fork entries, differing owner/group flags -- to make hand-rolling
# a binary archive format on the host a bad bet). binutils (for `ar`; alpine
# has no ar otherwise) is installed into the container at run time.

set -e   # stop on first failure instead of producing a half-built package

# Run from anywhere -- always operate relative to this script's own directory.
cd "$(dirname "$0")" || exit 1

PKGNAME=luci-app-router-label
APK_IMAGE=alpine:3.24
OUTDIR="$HOME/openwrt-sdk-build/bin/packages/mips_24kc/base"
JS_VIEW=htdocs/luci-static/resources/view/routerlabel.js

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' Makefile)
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' Makefile)
PKG_MAINTAINER=$(sed -n 's/^PKG_MAINTAINER:=//p' Makefile)
LUCI_DESCRIPTION=$(sed -n 's/^LUCI_DESCRIPTION:=//p' Makefile)
# LUCI_DEPENDS entries are like "+luci-base" -- luci.mk strips the leading
# "+" (it just means "install if not already present") and always adds libc.
LUCI_DEPENDS=$(sed -n 's/^LUCI_DEPENDS:=//p' Makefile | tr -d '+')
VERSION="${PKG_VERSION}-${PKG_RELEASE}"

# routerlabel.js hardcodes its own copy of PKG_VERSION (as APP_VERSION) since
# it's also deployed as a loose file with no build/templating step -- this
# keeps that copy in sync with the Makefile so bumping the version in one
# place is enough. Same logic as build-apk.sh; harmless to run from both.
sync_version() {
	current=$(sed -n "s/^var APP_VERSION = '\\(.*\\)';/\\1/p" "$JS_VIEW")
	if [ "$current" != "$PKG_VERSION" ]; then
		sed "s/^var APP_VERSION = '.*';/var APP_VERSION = '${PKG_VERSION}';/" "$JS_VIEW" > "$JS_VIEW.tmp"
		mv "$JS_VIEW.tmp" "$JS_VIEW"
		echo "Synced APP_VERSION in $JS_VIEW: $current -> $PKG_VERSION"
	fi
}
sync_version

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p \
  "$WORKDIR/data/usr/share/luci/menu.d" \
  "$WORKDIR/data/usr/share/rpcd/acl.d" \
  "$WORKDIR/data/www/luci-static/resources/view" \
  "$WORKDIR/control"

cp root/usr/share/luci/menu.d/luci-app-router-label.json \
  "$WORKDIR/data/usr/share/luci/menu.d/luci-app-router-label.json"
cp root/usr/share/rpcd/acl.d/luci-app-router-label.json \
  "$WORKDIR/data/usr/share/rpcd/acl.d/luci-app-router-label.json"
cp htdocs/luci-static/resources/routerlabel.js \
  "$WORKDIR/data/www/luci-static/resources/routerlabel.js"
cp htdocs/luci-static/resources/view/routerlabel.js \
  "$WORKDIR/data/www/luci-static/resources/view/routerlabel.js"

cat > "$WORKDIR/control/control" <<EOF
Package: ${PKGNAME}
Version: ${VERSION}
Depends: libc, ${LUCI_DEPENDS}
Architecture: all
Maintainer: ${PKG_MAINTAINER}
Description: ${LUCI_DESCRIPTION}
EOF

# postinst runs on both fresh install AND upgrade under opkg -- unlike apk,
# which calls separate post-install/post-upgrade scripts, opkg just exports
# PKG_UPGRADE=1 itself and re-invokes this same postinst. Otherwise identical
# to build-apk.sh's postinst.sh/prerm.sh (standard luci.mk hooks calling
# add_group_and_user/default_postinst/default_prerm from /lib/functions.sh
# on the router).
cat > "$WORKDIR/control/postinst" <<EOF
#!/bin/sh
[ "\${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s \${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="${PKGNAME}"
add_group_and_user
default_postinst
[ -n "\${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
EOF

cat > "$WORKDIR/control/prerm" <<EOF
#!/bin/sh
[ -s \${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="${PKGNAME}"
default_prerm
EOF

chmod 755 "$WORKDIR/control/postinst" "$WORKDIR/control/prerm"
echo "2.0" > "$WORKDIR/debian-binary"

mkdir -p "$OUTDIR"
IPK_NAME="${PKGNAME}_${VERSION}_all.ipk"

docker run --rm \
  -v "$WORKDIR:/work" \
  -v "$OUTDIR:/out" \
  -w /work \
  "$APK_IMAGE" sh -c '
    set -e
    apk add --no-cache binutils >/dev/null
    tar -czf control.tar.gz -C control .
    tar -czf data.tar.gz -C data .
    ar rc "/out/'"$IPK_NAME"'" debian-binary control.tar.gz data.tar.gz
  '

echo "Built: $OUTDIR/$IPK_NAME"
