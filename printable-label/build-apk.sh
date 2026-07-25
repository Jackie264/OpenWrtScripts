#! /bin/sh

# Build luci-app-printable-label-<version>.apk directly with apk-tools' `mkpkg`,
# skipping the OpenWrt SDK entirely. This package is just 4 JS/JSON files, so
# there is nothing to cross-compile -- the SDK's own package-pack.mk ends up
# calling `apk mkpkg` on those files anyway. See BUILDING.md for how this was
# verified against a real SDK-built .apk (identical file tree, scripts, and
# metadata) before this script replaced that workflow.
#
# Uses alpine:3.24 (pinned, not :latest/:edge) since that's the first stable
# Alpine release shipping apk-tools 3.x, which is required for `apk mkpkg`
# and the v3 .apk format OpenWrt now uses.

set -e   # stop on first failure instead of producing a half-built package

# Run from anywhere -- always operate relative to this script's own directory.
cd "$(dirname "$0")" || exit 1

PKGNAME=luci-app-printable-label
APK_IMAGE=alpine:3.24
OUTDIR="$HOME/openwrt-sdk-build/bin/packages/mips_24kc/base"
JS_VIEW=htdocs/luci-static/resources/view/routerlabel.js

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' Makefile)
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' Makefile)
PKG_LICENSE=$(sed -n 's/^PKG_LICENSE:=//p' Makefile)
PKG_MAINTAINER=$(sed -n 's/^PKG_MAINTAINER:=//p' Makefile)
LUCI_DESCRIPTION=$(sed -n 's/^LUCI_DESCRIPTION:=//p' Makefile)
# LUCI_DEPENDS entries are like "+luci-base" -- luci.mk strips the leading
# "+" (it just means "install if not already present") and always adds libc.
LUCI_DEPENDS=$(sed -n 's/^LUCI_DEPENDS:=//p' Makefile | tr -d '+')
VERSION="${PKG_VERSION}-r${PKG_RELEASE}"

# routerlabel.js hardcodes its own copy of PKG_VERSION (as APP_VERSION) since
# it's also deployed as a loose file with no build/templating step -- this
# keeps that copy in sync with the Makefile so bumping the version in one
# place is enough.
sync_version() {
	current=$(sed -n "s/^var APP_VERSION = '\\(.*\\)';/\\1/p" "$JS_VIEW")
	if [ "$current" != "$PKG_VERSION" ]; then
		sed "s/^var APP_VERSION = '.*';/var APP_VERSION = '${PKG_VERSION}';/" "$JS_VIEW" > "$JS_VIEW.tmp"
		mv "$JS_VIEW.tmp" "$JS_VIEW"
		echo "Synced APP_VERSION in $JS_VIEW: $current -> $PKG_VERSION"
	fi
}

if [ "$1" = "--sync-version" ]; then
	sync_version
	exit 0
fi

sync_version

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p \
  "$WORKDIR/files/usr/share/luci/menu.d" \
  "$WORKDIR/files/usr/share/rpcd/acl.d" \
  "$WORKDIR/files/www/luci-static/resources/view" \
  "$WORKDIR/files/lib/apk/packages" \
  "$WORKDIR/scripts"

cp root/usr/share/luci/menu.d/luci-app-printable-label.json \
  "$WORKDIR/files/usr/share/luci/menu.d/luci-app-printable-label.json"
cp root/usr/share/rpcd/acl.d/luci-app-printable-label.json \
  "$WORKDIR/files/usr/share/rpcd/acl.d/luci-app-printable-label.json"
cp htdocs/luci-static/resources/routerlabel.js \
  "$WORKDIR/files/www/luci-static/resources/routerlabel.js"
cp htdocs/luci-static/resources/view/routerlabel.js \
  "$WORKDIR/files/www/luci-static/resources/view/routerlabel.js"

# apk expects a manifest of the files it's about to own, at this fixed path --
# matches what luci.mk generates for every luci-app-* package.
cat > "$WORKDIR/files/lib/apk/packages/${PKGNAME}.list" <<EOF
/usr/share/luci/menu.d/luci-app-printable-label.json
/usr/share/rpcd/acl.d/luci-app-printable-label.json
/www/luci-static/resources/routerlabel.js
/www/luci-static/resources/view/routerlabel.js
EOF

# Standard luci.mk install/upgrade/remove hooks -- identical for every
# luci-app-* package; add_group_and_user/default_postinst/default_prerm are
# defined in /lib/functions.sh on the router.
cat > "$WORKDIR/scripts/postinst.sh" <<EOF
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

cat > "$WORKDIR/scripts/prerm.sh" <<EOF
#!/bin/sh
[ -s \${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="${PKGNAME}"
default_prerm
EOF

cat > "$WORKDIR/scripts/postupgrade.sh" <<EOF
#!/bin/sh
export PKG_UPGRADE=1
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

mkdir -p "$OUTDIR"

docker run --rm \
  -v "$WORKDIR:/work:ro" \
  -v "$OUTDIR:/out" \
  -w /work \
  "$APK_IMAGE" apk mkpkg \
    --info "name:${PKGNAME}" \
    --info "version:${VERSION}" \
    --info "description:${LUCI_DESCRIPTION}" \
    --info "arch:noarch" \
    --info "license:${PKG_LICENSE}" \
    --info "maintainer:${PKG_MAINTAINER}" \
    --info "depends:libc ${LUCI_DEPENDS}" \
    --info "provides:${PKGNAME}-any" \
    --script "post-install:scripts/postinst.sh" \
    --script "pre-deinstall:scripts/prerm.sh" \
    --script "post-upgrade:scripts/postupgrade.sh" \
    --files files \
    --output "/out/${PKGNAME}-${VERSION}.apk"

echo "Built: $OUTDIR/${PKGNAME}-${VERSION}.apk"
