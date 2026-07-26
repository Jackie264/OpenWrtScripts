#! /bin/sh

# Publish the already-built .apk/.ipk as a GitHub release. Run
# ./build-packages.sh (or build-apk.sh/build-ipk.sh individually) first --
# this script doesn't build. If a release for this version's tag already
# exists (e.g. re-running after a packaging fix, same PKG_VERSION), its
# assets and notes are updated in place instead of failing.

set -e   # stop on first failure instead of leaving a half-published release

# Run from anywhere -- always operate relative to this script's own directory.
cd "$(dirname "$0")" || exit 1

REPO=richb-hanover/OpenWrtScripts
PKGNAME=luci-app-printable-label
OUTDIR="$HOME/openwrt-sdk-build/bin/packages/mips_24kc/base"

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' Makefile)
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' Makefile)

APK="${OUTDIR}/${PKGNAME}-${PKG_VERSION}-r${PKG_RELEASE}.apk"
IPK="${OUTDIR}/${PKGNAME}_${PKG_VERSION}-${PKG_RELEASE}_all.ipk"

for f in "$APK" "$IPK"; do
	if [ ! -f "$f" ]; then
		echo "Not found: $f" >&2
		echo "Run ./build-packages.sh first." >&2
		exit 1
	fi
done

APK_NAME=$(basename "$APK")
IPK_NAME=$(basename "$IPK")
TAG="v${PKG_VERSION}"
TITLE="${PKGNAME} v${PKG_VERSION}"

NOTES="Printable Label LuCI app. Two package formats, built with build-apk.sh / build-ipk.sh (no OpenWrt SDK required):

- \`${APK_NAME}\` -- OpenWrt 24.10+ (apk-tools)
- \`${IPK_NAME}\` -- OpenWrt 23.05 and earlier (opkg)

Install on a router:
\`\`\`
# apk (24.10+)
scp -O ${APK_NAME} root@<router>:/tmp/
ssh root@<router> apk add --allow-untrusted /tmp/${APK_NAME}

# opkg (23.05 and earlier)
scp -O ${IPK_NAME} root@<router>:/tmp/
ssh root@<router> opkg install /tmp/${IPK_NAME}
\`\`\`
Then on either: \`ssh root@<router> rm -f /tmp/luci-indexcache*; ssh root@<router> /etc/init.d/rpcd restart\`"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
	echo "Release $TAG already exists -- updating assets and notes."
	gh release upload "$TAG" "$APK" "$IPK" --repo "$REPO" --clobber
	gh release edit "$TAG" --repo "$REPO" --title "$TITLE" --notes "$NOTES"
else
	gh release create "$TAG" "$APK" "$IPK" \
	  --repo "$REPO" \
	  --title "$TITLE" \
	  --notes "$NOTES"
fi

echo "Published: $TAG -> https://github.com/${REPO}/releases/tag/${TAG}"
