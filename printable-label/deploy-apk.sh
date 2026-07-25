#! /bin/sh

# Deploy the already-built .apk to the router: scp it over, install/upgrade
# it with apk, clear the menu cache, and restart rpcd so the change shows up
# immediately. Run ./build-apk.sh first -- this script doesn't build.
#
# Usage: ./deploy-apk.sh [user@]router-address
#
# Renamed from copy-package-files.sh, which copied the 4 loose files
# directly (no package involved). See README.md for that manual fallback.

set -e   # stop on the first failed scp/ssh instead of leaving a partial deploy

if [ -z "$1" ]; then
	echo "Usage: $0 [user@]router-address" >&2
	exit 1
fi

# Run from anywhere -- always operate relative to this script's own directory,
# since the Makefile/apk paths below are relative to printable-label/.
cd "$(dirname "$0")" || exit 1

PKGNAME=luci-app-printable-label
ROUTER="$1"

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' Makefile)
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' Makefile)
APK="$HOME/openwrt-sdk-build/bin/packages/mips_24kc/base/${PKGNAME}-${PKG_VERSION}-r${PKG_RELEASE}.apk"

if [ ! -f "$APK" ]; then
	echo "Not found: $APK" >&2
	echo "Run ./build-apk.sh first." >&2
	exit 1
fi

# Remove any loose-file deploy (the README's manual quick-iteration path) so
# there's no ambiguity between package-managed and stray files.
ssh "$ROUTER" '
	rm -f /www/luci-static/resources/routerlabel.js
	rm -f /www/luci-static/resources/view/routerlabel.js
	rm -f /usr/share/luci/menu.d/luci-app-printable-label.json
	rm -f /usr/share/rpcd/acl.d/luci-app-printable-label.json
'

scp -O "$APK" "$ROUTER:/tmp/"
ssh "$ROUTER" apk add --allow-untrusted "/tmp/$(basename "$APK")"
ssh "$ROUTER" rm -f /tmp/luci-indexcache* "/tmp/$(basename "$APK")"
ssh "$ROUTER" /etc/init.d/rpcd restart

echo "Deployed: $APK -> $ROUTER"
