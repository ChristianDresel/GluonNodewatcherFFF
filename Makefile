include $(TOPDIR)/rules.mk

PKG_NAME:=gluon-ffol-nodewatcher
PKG_VERSION:=30
PKG_RELEASE:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include ../gluon.mk

define Package/gluon-ffol-nodewatcher
  SECTION:=daemon
  CATEGORY:=Freifunk Oldenburg
  TITLE:=Provides status data for netmon
endef

define Package/gluon-ffol-nodewatcher/description
	Provides status data for netmon
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/gluon-ffol-nodewatcher/install
	$(INSTALL_DIR) $(1)/usr/lib/micron.d/
	$(INSTALL_DATA) files/lib/gluon/cron/nodewatcher $(1)/usr/lib/micron.d/nodewatcher
	$(INSTALL_DIR) $(1)/lib/ffol/nodewatcher/
	$(INSTALL_BIN) files/lib/ffol/nodewatcher/nodewatcher.sh $(1)/lib/ffol/nodewatcher/
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) files/nodewatcher.config $(1)/etc/config/nodewatcher
endef

$(eval $(call BuildPackage,gluon-ffol-nodewatcher))
