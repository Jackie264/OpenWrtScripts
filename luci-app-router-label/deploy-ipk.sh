#! /bin/sh

# Deploy the already-built .ipk to an opkg-era router (OpenWrt 23.05 and
# earlier -- see deploy-apk.sh for 24.10+): scp it over, install/upgrade it
# with opkg, clear the menu cache, and restart rpcd so the change shows up
# immediately. Run ./build-ipk.sh first -- this script doesn't build.

set -e   # stop on the first failed scp/ssh instead of leaving a partial deploy

if [ -z "$1" ]; then
	echo "Usage: $0 [user@]router-address" >&2
	exit 1
fi

# Run from anywhere -- always operate relative to this script's own directory,
# since the Makefile/ipk paths below are relative to luci-app-router-label/.
cd "$(dirname "$0")" || exit 1

PKGNAME=luci-app-router-label
ROUTER="$1"

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' Makefile)
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' Makefile)
IPK="$HOME/openwrt-sdk-build/bin/packages/mips_24kc/base/${PKGNAME}_${PKG_VERSION}-${PKG_RELEASE}_all.ipk"

if [ ! -f "$IPK" ]; then
	echo "Not found: $IPK" >&2
	echo "Run ./build-ipk.sh first." >&2
	exit 1
fi

# Remove any loose-file deploy (the README's manual quick-iteration path) so
# there's no ambiguity between package-managed and stray files.
ssh "$ROUTER" '
	rm -f /www/luci-static/resources/routerlabel.js
	rm -f /www/luci-static/resources/view/routerlabel.js
	rm -f /usr/share/luci/menu.d/luci-app-router-label.json
	rm -f /usr/share/rpcd/acl.d/luci-app-router-label.json
'

scp -O "$IPK" "$ROUTER:/tmp/"
ssh "$ROUTER" opkg install "/tmp/$(basename "$IPK")"
ssh "$ROUTER" rm -f /tmp/luci-indexcache* "/tmp/$(basename "$IPK")"
ssh "$ROUTER" /etc/init.d/rpcd restart

echo "Deployed: $IPK -> $ROUTER"
