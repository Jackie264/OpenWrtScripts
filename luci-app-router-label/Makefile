# See /LICENSE for more information.
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

PKG_VERSION:=0.1.3
PKG_RELEASE:=1

LUCI_TITLE:=Printable Label page for OpenWrt routers
LUCI_DESCRIPTION:=Displays the same router-identification label as print-router-label.sh, printable from the LuCI web GUI
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Rich Brown <richb.hanover@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
