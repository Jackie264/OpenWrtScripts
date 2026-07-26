# See /LICENSE for more information.
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

PKG_VERSION:=0.2.0
PKG_RELEASE:=3

LUCI_TITLE:=Printable Label page for OpenWrt routers
LUCI_DESCRIPTION:=Displays the Router model, LAN address, and credentials to make it easy to reconnect, even after years have gone by
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Rich Brown <richb.hanover@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
