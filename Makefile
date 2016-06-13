# Verbosity
V ?= 0

################################################################################
# Platform / product specific settings
################################################################################
ARCH           := arm
VENDOR         := armada38x
TARGET         := arm-$(VENDOR)-linux-gnueabihf
DTB            := armada-388-clearfog.dtb
TARGET_CFLAGS  := -marm -mabi=aapcs-linux -mno-thumb-interwork -mcpu=cortex-a9 \
                  -mtune=cortex-a9 -mfpu=neon-fp16 -mhard-float \
                  -mfloat-abi=hard -ffast-math -D_FORTIFY_SOURCE=2 \
                  -fstack-protector-strong -ffunction-sections -fdata-sections \
                  -ffat-lto-objects -flto -fpie -O2
TARGET_LDFLAGS := -Wl,-z,relro -Wl,-z,now -Wl,-z,combreloc -Wl,--gc-sections \
                  -pie -fpie -flto -fuse-linker-plugin -fuse-ld=gold -O2
PROJECTS       := libtool dtc util-linux kmod uboot linux busybox libc ctng \
                  libm initrd

################################################################################
# Build directory hierarchy
################################################################################
BUILD          := $(CURDIR)/build
SRC            := $(CURDIR)/src
CFG            := $(CURDIR)/cfg
BOOT           := $(CURDIR)/boot
SKEL           := $(CURDIR)/skel
TARBALLS       := $(CURDIR)/tarballs
OUT            := $(CURDIR)/out
HOSTTOOL       := $(OUT)/host
STAGE          := $(OUT)/stage
ROOT           := $(OUT)/root
IMG            := $(OUT)/img
TOOLCHAIN      := $(HOSTTOOL)/$(TARGET)
CROSS_COMPILE  := $(TOOLCHAIN)/bin/$(TARGET)-
LIBC_SYSROOT   := $(TOOLCHAIN)/$(TARGET)/sysroot

################################################################################
# Special characters
################################################################################
null  :=
space := $(null) $(null)
define newline
$(null)
$(null)
endef

LN      := ln -sf
CP      := cp
INSTALL := install
MKDIR   := mkdir

################################################################################
# Generic macros and variables
################################################################################

export PATH                  := $(HOSTTOOL)/bin:$(TOOLCHAIN)/bin:$(PATH)

ifeq ($(V),0)
AUTOCONF_BUILD_ARGS          := V=0 LIBTOOLFLAGS="--quiet --no-warning"
else
AUTOCONF_BUILD_ARGS          := V=$(V) LIBTOOLFLAGS="--verbose"
endif

HOST_AUTOCONF_CONF_ARGS      := --prefix=$(HOSTTOOL) --host=$(TARGET)
HOST_AUTOCONF_BUILD_ARGS     := $(AUTOCONF_BUILD_ARGS)
HOST_AUTOCONF_INSTALL_ARGS   := $(HOST_AUTOCONF_BUILD_ARGS)

TARGET_CC                    := $(CROSS_COMPILE)gcc
TARGET_CXX                   := $(CROSS_COMPILE)g++
TARGET_AR                    := $(CROSS_COMPILE)gcc-ar
TARGET_AS                    := $(CROSS_COMPILE)as
TARGET_RANLIB                := $(CROSS_COMPILE)gcc-ranlib
TARGET_NM                    := $(CROSS_COMPILE)gcc-nm
TARGET_LD                    := $(CROSS_COMPILE)ld
TARGET_STRIP                 := $(CROSS_COMPILE)strip
TARGET_CPPFLAGS              := -I$(STAGE)/usr/include
TARGET_CFLAGS                += -I$(STAGE)/usr/include
#TARGET_LDFLAGS               += \
#	-L$(STAGE)/usr/lib \
#	-L$(STAGE)/lib \
#	-Wl,-rpath,/usr/lib \
#	-Wl,-rpath,/lib \
#	-Wl,-rpath-link,$(STAGE)/usr/lib \
#	-Wl,-rpath-link,$(STAGE)/lib

TARGET_AUTOCONF_CONF_ARGS    := \
	--host=$(TARGET) \
	--with-sysroot=$(STAGE) \
	--includedir=/usr/include \
	--sysconfdir=/etc \
	--datarootdir=/usr/share \
	--localstatedir=/var
TARGET_AUTOCONF_BUILD_ARGS   := $(AUTOCONF_BUILD_ARGS)
TARGET_AUTOCONF_INSTALL_ARGS := $(TARGET_AUTOCONF_BUILD_ARGS) DESTDIR=$(STAGE)

srcdir   = $(abspath $(SRC)/$(strip $(1)))
builddir = $(abspath $(BUILD)/$(strip $(1)))

define git_clone_branch
	if test ! -d $(call srcdir,$(2)); then \
		cd $(SRC); \
		git clone --branch $(3) $(1) $(2); \
		cd $(call srcdir,$(2)); \
		git fetch --all; \
	fi
endef

define git_clone_tag
	if test ! -d $(call srcdir,$(2)); then \
		cd $(SRC); \
		git clone --branch $(3) $(1) $(2); \
		cd $(call srcdir,$(2)); \
		git fetch --all; \
	fi
endef

define git_clone_sha1
	if test ! -d $(call srcdir,$(2)); then \
		cd $(SRC); \
		git clone $(1) $(2); \
		cd $(call srcdir,$(2)); \
		git checkout --detach $(3); \
		git fetch --all; \
	fi
endef

define host_autoconf_configure
	cd $(call builddir,$(1)) && \
		$(call srcdir,$(1))/configure $(HOST_AUTOCONF_CONF_ARGS) $(2)
endef

define host_autoconf_build
	$(MAKE) -C $(call builddir,$(1)) $(HOST_AUTOCONF_BUILD_ARGS)
endef

define host_autoconf_install
	$(MAKE) -C $(call builddir,$(1)) $(HOST_AUTOCONF_INSTALL_ARGS) install
endef

define host_autoconf_clean
	$(MAKE) -C $(call builddir,$(1)) $(HOST_AUTOCONF_BUILD_ARGS) clean
endef

define host_autoconf_uninstall
	$(MAKE) -C $(call builddir,$(1)) $(HOST_AUTOCONF_INSTALL_ARGS) \
		uninstall
endef

define target_autoconf_env
	CC="$(TARGET_CC)" \
	CXX="$(TARGET_CXX)" \
	AR="$(TARGET_AR)" \
	AS="$(TARGET_AS)" \
	RANLIB="$(TARGET_RANLIB)" \
	NM="$(TARGET_NM)" \
	LD="$(TARGET_LD)" \
	STRIP="$(TARGET_STRIP)" \
	PKG_CONFIG_LIBDIR="" \
	PKG_CONFIG_PATH="$(STAGE)/usr/lib/pkgconfig:$(STAGE)/usr/share/pkgconfig:$(STAGE)/lib/pkgconfig:$(STAGE)/share/pkgconfig:$(TOOLCHAIN)/share/pkgconfig" \
	PKG_CONFIG_SYSROOT_DIR="$(STAGE)" \
	ACLOCAL_PATH="$(STAGE)/usr/share/aclocal:$(STAGE)/share/aclocal:$(HOSTTOOL)/share/aclocal:$(TOOLCHAIN)/share/aclocal:$(TOOLCHAIN)/share/aclocal-1.15:$(call srcdir,$(1))/m4" \
	CPPFLAGS="$(TARGET_CPPFLAGS)" \
	CFLAGS="$(TARGET_CFLAGS)" \
	CXXFLAGS="$(TARGET_CFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS)"
endef

define target_autoconf_autogen
	cd $(call srcdir,$(1)) && \
	env $(call target_autoconf_env,$(1)) NOCONFIGURE=y ./autogen.sh
endef

define target_autoconf_configure
	cd $(call builddir,$(1)) && \
	env $(call target_autoconf_env,$(1)) \
		$(call srcdir,$(1))/configure $(TARGET_AUTOCONF_CONF_ARGS) $(2)
endef

define target_autoconf_build
	$(MAKE) -C $(call builddir,$(1)) $(TARGET_AUTOCONF_BUILD_ARGS)
endef

define target_autoconf_install
	$(MAKE) -C $(call builddir,$(1)) $(TARGET_AUTOCONF_INSTALL_ARGS) install
endef

define target_autoconf_clean
	$(MAKE) -C $(call builddir,$(1)) $(TARGET_AUTOCONF_BUILD_ARGS) clean
endef

define target_autoconf_uninstall
	$(MAKE) -C $(call builddir,$(1)) $(TARGET_AUTOCONF_INSTALL_ARGS) \
		uninstall
endef

define stage_install
	$(INSTALL) -D -m755 $(call builddir,$(1))/$(2) $(STAGE)/$(3)
endef

define root_install_bin
	$(INSTALL) -D -m755 $(STAGE)/$(1) $(ROOT)/$(2)
	$(TARGET_STRIP) --strip-all $(ROOT)/$(2)
endef

define _root_install_lib
	$(INSTALL) -D -m755 $(1) $(2)
	$(TARGET_STRIP) --strip-unneeded $(2)
endef

define deps
	$(call builddir,$(1))/.$(2): $(call builddir,$(3))/.$(4)
endef

define generic_targets
	$(foreach t,$(filter-out $(custom_projects),$(PROJECTS)),$(1)-$(t))
endef

.PHONY: all
all: install

###############################################################################
# crosstool-ng
###############################################################################

define clone-ctng
	$(call git_clone_branch, \
	  https://github.com/crosstool-ng/crosstool-ng.git,ctng,1.22)
endef

define autogen-ctng
	rsync -delete --exclude '.cloned' --archive $(call srcdir,ctng) $(BUILD)
	cd $(call builddir,ctng) && ./bootstrap
endef

define config-ctng
	cd $(call builddir,ctng) && \
		$(call builddir,ctng)/configure --prefix=$(HOSTTOOL)
endef

define build-ctng
	+$(call host_autoconf_build,ctng) MAKELEVEL=0
endef

define install-ctng
	+$(call host_autoconf_install,ctng) MAKELEVEL=0
endef

define clean-ctng
	+$(call host_autoconf_clean,ctng) MAKELEVEL=0
endef

define uninstall-ctng
	+$(call host_autoconf_uninstall,ctng) MAKELEVEL=0
endef

###############################################################################
# host libtool
###############################################################################

define clone-libtool
	$(call git_clone_branch,git@github.com:grgbr/libtool,libtool,v2.4.2-oe)
endef

define autogen-libtool
	cd $(call srcdir,libtool) && ./bootstrap
endef

define config-libtool
	$(call host_autoconf_configure,libtool)
endef

define build-libtool
	$(call host_autoconf_build,libtool)
endef

define install-libtool
	$(call host_autoconf_install,libtool)
endef

define clean-libtool
	$(call host_autoconf_clean,libtool)
endef

define uninstall-libtool
	$(call host_autoconf_uninstall,libtool)
endef

$(call deps,libtool,configured,libc,built)

###############################################################################
# host dtc
###############################################################################

define clone-dtc
	$(call git_clone_tag, \
	  git://git.kernel.org/pub/scm/utils/dtc/dtc.git, \
	  dtc, \
	  v1.4.1)
endef

define build-dtc
	rsync -delete --exclude '.*' --archive $(call srcdir,dtc) $(BUILD)
	+$(MAKE) -C $(call builddir,dtc) PREFIX=$(HOSTTOOL)
endef

define install-dtc
	+$(MAKE) -C $(call builddir,dtc) install-bin PREFIX=$(HOSTTOOL)
endef

define clean-dtc
	+$(MAKE) -C $(call builddir,dtc) clean PREFIX=$(HOSTTOOL)
endef

define uninstall-dtc
	$(RM) $(HOSTTOOL)/bin/dtdiff \
	      $(HOSTTOOL)/bin/convert-dtsv0 \
	      $(HOSTTOOL)/bin/fdtput \
	      $(HOSTTOOL)/bin/fdtget \
	      $(HOSTTOOL)/bin/dtc \
	      $(HOSTTOOL)/bin/fdtdump
endef

###############################################################################
# libc based on crosstool-ng
###############################################################################

custom_projects += libc
libc_config     := $(CFG)/ctng.config
libc_envflags   := BUILD="$(call builddir,libc)" \
                   ROOT="$(HOSTTOOL)" \
                   VENDOR="$(VENDOR)" \
                   LINUX_SRC="$(call srcdir,linux)" \
                   DOWNLOAD="$(TARBALLS)" \
                   DEFCONFIG="$(libc_config)"
ifneq ($(V),0)
libc_envflags   += V=2
endif

$(call builddir,libc): | $(BUILD)
	$(MKDIR) $@

$(call builddir,libc)/.config: | $(call builddir,libc)
	+if test ! -f $(libc_config); then \
		echo "missing libc configuration file \"$(libc_config)\""; \
		exit 1; \
	fi; \
	if test ! -f $@; then \
		cd $(call builddir,libc); \
		env $(libc_envflags) $(HOSTTOOL)/bin/ct-ng defconfig; \
	fi

.PHONY: defconfig-libc
defconfig-libc: | $(call builddir,libc)
	+if test ! -f $(libc_config); then \
		echo "missing libc configuration file \"$(libc_config)\""; \
		exit 1; \
	fi; \
	if test ! -f $@; then \
		cd $(call builddir,libc); \
		env $(libc_envflags) $(HOSTTOOL)/bin/ct-ng defconfig; \
	fi


.PHONY: saveconfig-libc
saveconfig-libc: | $(CFG)
	+if test -f "$(call builddir,libc)/.config"; then \
		cd $(call builddir,libc); \
		env $(libc_envflags) $(HOSTTOOL)/bin/ct-ng savedefconfig; \
	fi

.PHONY: build-libc
build-libc: $(call builddir,libc)/.built
$(call builddir,libc)/.built: $(call builddir,libc)/.config | $(TARBALLS)
	+cd $(call builddir,libc); \
	env $(libc_envflags) $(HOSTTOOL)/bin/ct-ng build
	touch $@

.PHONY: install-libc
install-libc: $(call builddir,libc)/.installed
$(call builddir,libc)/.installed: $(call builddir,libc)/.built
	$(call _root_install_lib, \
	  $(LIBC_SYSROOT)/lib/libc.so.6, \
	  $(ROOT)/lib/libc.so.6)
	$(call _root_install_lib, \
	  $(LIBC_SYSROOT)/lib/libgcc_s.so.1, \
	  $(ROOT)/lib/libgcc_s.so.1)
	$(call _root_install_lib, \
	  $(LIBC_SYSROOT)/lib/ld-linux-armhf.so.3, \
	  $(ROOT)/lib/ld-linux-armhf.so.3)
	touch $@

.PHONY: clean-libc
clean-libc: uninstall-libc
	+if test -f "$(call builddir,libc)/.config" -a \
		-f "$(call builddir,libc)/.built"; then \
		cd $(call builddir,libc); \
		env $(libc_envflags) $(HOSTTOOL)/bin/ct-ng clean; \
	fi
	$(RM) $(call builddir,libc)/.built

.PHONY: uninstall-libc
uninstall-libc:
	$(RM) $(ROOT)/lib/libc.6.so $(ROOT)/lib/libgcc_s.so.1 \
		$(ROOT)/lib/ld-linux-armhf.so.3
	$(RM) $(call builddir,libc)/.installed

.PHONY: libc-%
libc-%: $(call builddir,ctng)/.installed
	+cd $(call builddir,libc); \
	env $(libc_envflags) $(HOSTTOOL)/bin/ct-ng $(subst libc-,,$@)

$(call deps,libc,config,ctng,installed)
$(call deps,libc,config,linux,cloned)

###############################################################################
# libm
###############################################################################

define install-libm
	$(call _root_install_lib, \
	  $(LIBC_SYSROOT)/lib/libm.so.6, \
	  $(ROOT)/lib/libm.so.6)
endef

define uninstall-libm
	$(RM) $(ROOT)/lib/libm.so.6
endef

$(call deps,libm,installed,libc,installed)

################################################################################
# U-boot
################################################################################

custom_projects += uboot
uboot_envsz     := 65536
uboot_config    := $(CFG)/uboot.config
uboot_defconfig := clearfog_defconfig
uboot_mkflags   := ARCH=$(ARCH) \
                   CROSS_COMPILE=$(CROSS_COMPILE) \
                   DTC=$(HOSTTOOL)/bin/dtc \
                   O=$(call builddir,uboot) \
                   V=$(V)

$(call builddir,uboot): | $(BUILD)
	$(MKDIR) $@

$(call builddir,uboot)/.cloned: | $(call builddir,uboot) $(SRC)
	$(call git_clone_sha1, \
	  git://git.denx.de/u-boot.git, \
	  u-boot, \
	  cf77f6ffd96a243d2e4f81fe8bc0aa4fe8fef623)
	touch $@

.PHONY: defconfig-uboot
defconfig-uboot: $(call builddir,uboot)/.cloned
	if test -f $(uboot_config); then \
		$(CP) $(uboot_config) $(call builddir,uboot)/.config; \
	else \
		$(MAKE) -C $(call srcdir,u-boot) $(uboot_mkflags) \
			$(uboot_defconfig); \
	fi

.PHONY: saveconfig-uboot
saveconfig-uboot: | $(CFG)
	if test -f "$(call builddir,uboot)/.config"; then \
		$(CP) $(call builddir,uboot)/.config $(uboot_config); \
		touch $(call builddir,uboot)/.config; \
	fi

$(call builddir,uboot)/.config: $(call builddir,uboot)/.cloned
	if test ! -f $@ -a -f $(uboot_config); then \
		$(CP) $(uboot_config) $@; \
	elif test ! -f $@; then \
		$(MAKE) -C $(call srcdir,u-boot) $(uboot_mkflags) \
			$(uboot_defconfig); \
	else \
		:; \
	fi

.PHONY: build-uboot
build-uboot: $(call builddir,uboot)/.built
$(call builddir,uboot)/.built: $(call builddir,uboot)/.config
	$(MAKE) -C $(call srcdir,u-boot) $(uboot_mkflags) all
	touch $@

$(IMG)/uboot.env: $(BOOT)/uboot.env  $(call builddir,uboot)/.built | $(IMG)
	$(call builddir,uboot)/tools/mkenvimage -s $(uboot_envsz) -o $@ $<

.PHONY: install-uboot
install-uboot: $(call builddir,uboot)/.installed
$(call builddir,uboot)/.installed: $(IMG)/uboot.env
	$(LN) $(call builddir,uboot)/u-boot-dtb.bin $(IMG)/u-boot-dtb.bin
	$(LN) $(call builddir,uboot)/u-boot-nodtb.bin $(IMG)/u-boot-nodtb.bin
	$(LN) $(call builddir,uboot)/u-boot-spl.kwb $(IMG)/u-boot-spl.kwb
	touch $@

.PHONY: clean-uboot
clean-uboot: uninstall-uboot
	if test -f "$(call builddir,uboot)/.config" -a \
		-f "$(call builddir,uboot)/.built"; then \
		$(MAKE) -C $(call srcdir,u-boot) $(uboot_mkflags) clean; \
	fi
	$(RM) $(call builddir,uboot)/.built

.PHONY: uninstall-uboot
uninstall-uboot:
	$(RM) $(IMG)/u-boot-dtb.bin $(IMG)/u-boot-nodtb.bin \
		$(IMG)/u-boot-spl.kwb $(IMG)/uboot.env
	$(RM) $(call builddir,uboot)/.installed

.PHONY: uboot-%
uboot-%: $(call builddir,uboot)/.cloned
	$(MAKE) -C $(call srcdir,u-boot) $(uboot_mkflags) $(subst uboot-,,$@)

$(call deps,uboot,config,libc,built)
$(call deps,uboot,config,dtc,installed)

################################################################################
# kmod
################################################################################

define clone-kmod
	$(call git_clone_tag, \
	  git://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git, \
	  kmod, \
	  v22)
endef

define autogen-kmod
	$(call target_autoconf_autogen,kmod)
endef

define config-kmod
	$(call target_autoconf_configure, \
	  kmod, \
	  --prefix= \
	  --bindir=/sbin \
	  --disable-maintainer-mode \
	  --disable-test-modules \
	  --without-xz \
	  --without-zlib)
endef

define build-kmod
	$(call target_autoconf_build,kmod)
endef

define install-kmod
	$(call target_autoconf_install,kmod)
	$(call root_install_bin,sbin/kmod,sbin/kmod)
	$(LN) kmod $(ROOT)/sbin/insmod
	$(LN) kmod $(ROOT)/sbin/rmmod
	$(LN) kmod $(ROOT)/sbin/modprobe
endef

define clean-kmod
	$(call target_autoconf_clean,kmod)
endef

define uninstall-kmod
	$(call target_autoconf_uninstall,kmod)
	$(RM) $(ROOT)/sbin/insmod $(ROOT)/sbin/rmmod $(ROOT)/sbin/modprobe
	$(RM) $(ROOT)/sbin/kmod
endef

$(call deps,kmod,configured,libtool,installed)

################################################################################
# util-linux
################################################################################

define clone-util-linux
	$(call git_clone_branch, \
	  git://git.kernel.org/pub/scm/utils/util-linux/util-linux.git, \
	  util-linux, \
	  stable/v2.27)
endef

define autogen-util-linux
	$(call target_autoconf_autogen,util-linux)
endef

define config-util-linux
	$(call target_autoconf_configure, \
	  util-linux, \
	  --prefix=/usr \
	  --enable-schedutils \
	  --disable-assert \
	  --disable-nls \
	  --disable-libuuid \
	  --disable-libblkid \
	  --disable-libmount \
	  --disable-libsmartcols \
	  --disable-libfdisk \
	  --disable-losetup \
	  --disable-zramctl \
	  --disable-fsck \
	  --disable-partx \
	  --disable-uuidd \
	  --disable-mountpoint \
	  --disable-fallocate \
	  --disable-unshare \
	  --disable-nsenter \
	  --disable-setpriv \
	  --disable-eject \
	  --disable-agetty \
	  --disable-cramfs \
	  --disable-bfs \
	  --disable-minix \
	  --disable-fdformat \
	  --disable-wdctl \
	  --disable-cal \
	  --disable-switch_root \
	  --disable-pivot_root \
	  --disable-tunelp \
	  --disable-kill \
	  --disable-last \
	  --disable-utmpdump \
	  --disable-line \
	  --disable-mesg \
	  --disable-raw \
	  --disable-rename \
	  --disable-reset \
	  --disable-vipw \
	  --disable-newgrp \
	  --disable-chfn-chsh \
	  --disable-login \
	  --disable-nologin \
	  --disable-sulogin \
	  --disable-su \
	  --disable-runuser \
	  --disable-ul \
	  --disable-more \
	  --disable-pg \
	  --disable-setterm \
	  --disable-wall \
	  --disable-write \
	  --disable-bash-completion \
	  --disable-pylibmount \
	  --disable-pg-bell \
	  --without-util \
	  --without-termcap \
	  --without-selinux \
	  --without-audit \
	  --without-udev \
	  --without-ncurses \
	  --without-slang \
	  --without-tinfo \
	  --without-readline \
	  --without-utempter \
	  --without-capng \
	  --without-libz \
	  --without-user \
	  --without-systemd \
	  --without-smack \
	  --without-python)
endef

define build-util-linux
	$(MAKE) -C $(call builddir,util-linux) $(TARGET_AUTOCONF_BUILD_ARGS) \
		chrt ionice taskset
endef

define install-util-linux
	$(call stage_install,util-linux,chrt,usr/bin/chrt)
	$(call stage_install,util-linux,ionice,usr/bin/ionice)
	$(call stage_install,util-linux,taskset,usr/bin/taskset)
	$(call root_install_bin,usr/bin/chrt,usr/bin/chrt)
	$(call root_install_bin,usr/bin/ionice,usr/bin/ionice)
	$(call root_install_bin,usr/bin/taskset,usr/bin/taskset)
endef

define clean-util-linux
	$(call target_autoconf_clean,util-linux)
endef

define uninstall-util-linux
	$(RM) $(STAGE)/usr/bin/chrt
	$(RM) $(STAGE)/usr/bin/ionice
	$(RM) $(STAGE)/usr/bin/taskset
	$(RM) $(ROOT)/usr/bin/chrt
endef

$(call deps,util-linux,configured,libtool,installed)

################################################################################
# Linux
################################################################################

custom_projects += linux
linux_config    := $(CFG)/linux.config
linux_defconfig := mvebu_v7_defconfig
linux_mkflags   := ARCH=$(ARCH) \
                   CROSS_COMPILE=$(CROSS_COMPILE) \
                   O=$(call builddir,linux) \
                   INSTALL_PATH=$(ROOT) \
                   INSTALL_MOD_PATH=$(ROOT) \
                   V=$(V)

$(call builddir,linux): | $(BUILD)
	$(MKDIR) $@

$(call builddir,linux)/.cloned: | $(call builddir,linux) $(SRC)
	$(call git_clone_branch, \
	  git@github.com:grgbr/linux-net, \
	  linux, \
	  next-mvneta)
	touch $@

.PHONY: defconfig-linux
defconfig-linux: $(call builddir,linux)/.cloned
	if test -f $(linux_config); then \
		$(CP) $(linux_config) $(call builddir,linux)/.config; \
	else \
		$(MAKE) -C $(call srcdir,linux) $(linux_mkflags) \
			$(linux_defconfig); \
	fi

.PHONY: saveconfig-linux
saveconfig-linux: | $(CFG)
	if test -f "$(call builddir,linux)/.config"; then \
		$(CP) $(call builddir,linux)/.config $(linux_config); \
		touch $(call builddir,linux)/.config; \
	fi

$(call builddir,linux)/.config: | $(call builddir,linux)/.cloned
	if test ! -f $@ -a -f $(linux_config); then \
		$(CP) $(linux_config) $@; \
	elif test ! -f $@; then \
		$(MAKE) -C $(call srcdir,linux) $(linux_mkflags) \
			$(linux_defconfig); \
	else \
		:; \
	fi

.PHONY: build-linux
build-linux: $(call builddir,linux)/.built
$(call builddir,linux)/.built: $(call builddir,linux)/.config
	$(MAKE) -C $(call srcdir,linux) $(linux_mkflags) all
	touch $@

.PHONY: install-linux
install-linux: $(call builddir,linux)/.installed
$(call builddir,linux)/.installed: $(call builddir,linux)/.built | \
                                   $(ROOT) $(IMG)
	$(MAKE) -C $(call srcdir,linux) $(linux_mkflags) modules_install
	$(LN) $(call builddir,linux)/arch/$(ARCH)/boot/zImage $(IMG)/zImage
	$(LN) $(call builddir,linux)/arch/$(ARCH)/boot/Image $(IMG)/Image
	$(LN) $(call builddir,linux)/arch/$(ARCH)/boot/dts/$(DTB) $(IMG)/$(DTB)
	touch $@

.PHONY: clean-linux
clean-linux: uninstall-linux
	if test -f "$(call builddir,linux)/.config" -a \
		-f "$(call builddir,linux)/.built"; then \
		$(MAKE) -C $(call srcdir,linux) $(linux_mkflags) clean; \
	fi
	$(RM) $(call builddir,linux)/.built

.PHONY: uninstall-linux
uninstall-linux:
	$(RM) -r $(ROOT)/lib/modules/ $(ROOT)/lib/firmware
	$(RM) $(IMG)/zImage $(IMG)/Image $(IMG)/$(DTB)
	$(RM) $(call builddir,linux)/.installed

.PHONY: linux-%
linux-%: $(call builddir,linux)/.cloned
	$(MAKE) -C $(call srcdir,linux) $(linux_mkflags) $(subst linux-,,$@)

$(call deps,linux,config,libc,built)
$(call deps,linux,config,dtc,installed)

################################################################################
# Busybox
################################################################################

custom_projects += busybox
busybox_config  := $(CFG)/busybox.config
busybox_mkflags := ARCH=$(ARCH) \
                   CROSS_COMPILE=$(CROSS_COMPILE) \
                   O=$(call builddir,busybox) \
                   CONFIG_PREFIX=$(ROOT) \
                   DESTDIR=$(STAGE) \
                   V=$(V)

$(call builddir,busybox): | $(BUILD)
	$(MKDIR) $@

$(call builddir,busybox)/.cloned: | $(call builddir,busybox) $(SRC)
	$(call git_clone_branch, \
	  git://git.busybox.net/busybox, \
	  busybox, \
	  1_24_stable)
	touch $@

.PHONY: defconfig-busybox
defconfig-busybox: $(call builddir,busybox)/.cloned
	if test -f $(busybox_config); then \
		$(CP) $(busybox_config) $(call builddir,busybox)/.config; \
	else \
		$(MAKE) -C $(call srcdir,busybox) $(busybox_mkflags) \
			defconfig; \
	fi

.PHONY: saveconfig-busybox
saveconfig-busybox: | $(CFG)
	if test -f "$(call builddir,busybox)/.config"; then \
		$(CP) $(call builddir,busybox)/.config $(busybox_config); \
		touch $(call builddir,busybox)/.config; \
	fi

$(call builddir,busybox)/.config: $(call builddir,busybox)/.cloned
	if test ! -f $@ -a -f $(busybox_config); then \
		$(CP) $(busybox_config) $@; \
	elif test ! -f $@; then \
		$(MAKE) -C $(call srcdir,busybox) $(busybox_mkflags) \
			defconfig; \
	else \
		:; \
	fi

.PHONY: build-busybox
build-busybox: $(call builddir,busybox)/.built
$(call builddir,busybox)/.built: $(call builddir,busybox)/.config
	$(MAKE) -C $(call srcdir,busybox) $(busybox_mkflags)
	touch $@

.PHONY: install-busybox
install-busybox: $(call builddir,busybox)/.installed
$(call builddir,busybox)/.installed: $(call builddir,busybox)/.built | $(ROOT)
	$(MAKE) -C $(call srcdir,busybox) $(busybox_mkflags) install
	touch $@

.PHONY: clean-busybox
clean-busybox: uninstall-busybox
	if test -f "$(call builddir,busybox)/.config" -a \
		-f "$(call builddir,busybox)/.built"; then \
		$(MAKE) -C $(call srcdir,busybox) $(busybox_mkflags) clean; \
	fi
	$(RM) $(call builddir,busybox)/.built

.PHONY: uninstall-busybox
uninstall-busybox:
	if test -f "$(call builddir,busybox)/.config" -a \
		-f "$(call builddir,busybox)/.installed"; then \
		$(MAKE) -C $(call srcdir,busybox) $(busybox_mkflags) \
			uninstall; \
	fi
	$(RM) $(call builddir,busybox)/.installed

.PHONY: busybox-%
busybox-%: $(call builddir,busybox)/.cloned
	$(MAKE) -C $(call srcdir,busybox) $(busybox_mkflags) \
		$(subst busybox-,,$@)

$(call deps,busybox,config,libc,built)
$(call deps,busybox,installed,libm,installed)

################################################################################
# Make bootable SD
################################################################################

BLK_ROOT := /media/greg/BB93-5E48

ifneq ($(BLK_ROOT),)
.PHONY: blk-boot
blk-boot: install-linux install-uboot
	blk_dev=$$(lsblk --raw --output NAME,MOUNTPOINT,RM | \
	           awk '/$(subst /,\/,$(BLK_ROOT)) 1/{print $$1}'); \
	if test -n "$$blk_dev"; then \
		read -p "Copy to /dev/$$blk_dev under $(BLK_ROOT) ? (y,[n]): " \
		     reply; \
		if test "$$reply" = "y"; then \
			sudo dd if=$(IMG)/u-boot-spl.kwb of=/dev/$$blk_dev bs=512 seek=1; \
			$(CP) $(IMG)/zImage $(BLK_ROOT)/zImage; \
			$(CP) $(IMG)/$(DTB) $(BLK_ROOT)/$(DTB); \
		fi \
	else \
		echo "$(BLK_ROOT) does not match a removable block device"; \
	fi
endif

################################################################################
# Generic rules
################################################################################

$(BUILD)/%/.cloned: | $(SRC)
	$(MKDIR) -p $(subst /.cloned,,$@)
	$(clone-$(patsubst $(BUILD)/%/.cloned,%,$@))
	touch $@

$(BUILD)/%/.autogened: $(BUILD)/%/.cloned
	$(autogen-$(patsubst $(BUILD)/%/.autogened,%,$@))
	touch $@

.PHONY: config config-%
config: $(addprefix config-, $(PROJECTS))
$(call generic_targets,config): config-%: $(BUILD)/%/.configured ;
$(BUILD)/%/.configured: $(BUILD)/%/.autogened
	$(config-$(patsubst $(BUILD)/%/.configured,%,$@))
	touch $@

.PHONY: build build-%
build: $(addprefix build-, $(PROJECTS))
$(call generic_targets,build): build-%: $(BUILD)/%/.built ;
$(BUILD)/%/.built: $(BUILD)/%/.configured
	$(build-$(patsubst $(BUILD)/%/.built,%,$@))
	touch $@

.PHONY: install install-%
install: $(addprefix install-, $(PROJECTS))
$(call generic_targets,install): install-%: $(BUILD)/%/.installed ;
$(BUILD)/%/.installed: $(BUILD)/%/.built
	$(install-$(patsubst $(BUILD)/%/.installed,%,$@))
	touch $@

.PHONY: clean clean-%
clean: $(addprefix clean-, $(PROJECTS))
$(call generic_targets,clean): clean-%: uninstall-%
	proj=$(patsubst clean-%,%,$@); \
	if test -f "$(BUILD)/$$proj/.configured" -a -f "$(BUILD)/$$proj/.built"; then \
		$(if $(clean-$(subst clean-,,$@)),\
		  $(subst $(newline),;,$(clean-$(subst clean-,,$@))),\
		  :); \
	fi; \
	$(RM) $(BUILD)/$$proj/.built

.PHONY: uninstall uninstall-%
uninstall: $(addprefix uninstall-, $(PROJECTS))
$(call generic_targets,uninstall): uninstall-%:
	proj=$(subst uninstall-,,$@); \
	if test -f "$(BUILD)/$$proj/.configured" -a -f "$(BUILD)/$$proj/.installed"; then \
		$(if $(uninstall-$(subst uninstall-,,$@)),\
		  $(subst $(newline),;,$(uninstall-$(subst uninstall-,,$@))),\
		  :); \
	fi; \
	$(RM) $(BUILD)/$$proj/.installed

.PHONY: remk-%
$(foreach t,$(PROJECTS),remk-$(t)): remk-%: uninstall-%
	$(RM) $(BUILD)/$(subst remk-,,$@)/.built
	$(MAKE) install-$(subst remk-,,$@)

.PHONY: clobber clobber-%
clobber:
	$(RM) -r $(BUILD) $(OUT)
$(foreach t,$(PROJECTS),clobber-$(t)): clobber-%: uninstall-%
	proj=$(patsubst clobber-%,%,$@); \
	$(RM) -r $(BUILD)/$$proj

# Disable .cloned .autogened .configured, .built, .installed intermediate file
# removal default rule
.PRECIOUS: $(BUILD)/%/.cloned \
           $(BUILD)/%/.autogened \
           $(BUILD)/%/.configured \
           $(BUILD)/%/.built \
           $(BUILD)/%/.installed

$(ROOT) $(IMG): | $(OUT)
$(CFG) $(BUILD) $(ROOT) $(IMG) $(OUT) $(SRC) $(TARBALLS):
	$(MKDIR) -p $@

################################################################################
# Populate root fs with skeleton content then build complete initramfs
################################################################################

define install-initrd
	$(CP) -a $(SKEL)/* $(ROOT)
	cd $(ROOT) && find . | cpio -o -H newc | gzip > $(IMG)/rootfs.cpio.gz
	$(call builddir,uboot)/tools/mkimage -A arm -C none -T ramdisk \
		-n "uInitramfs" -d $(IMG)/rootfs.cpio.gz $(IMG)/uInitramfs
endef

define uninstall-initrd
	$(RM) $(IMG)/uInitramfs $(IMG)/rootfs.cpio.gz
	find $(SKEL) -type f -printf '$(ROOT)/%P\n' | xargs $(RM)
endef

$(call builddir,initrd)/.installed: $(foreach p, \
                                      $(filter-out initrd,$(PROJECTS)), \
                                      $(call builddir,$(p))/.installed)

################################################################################
# Make bootable SD
################################################################################

.PHONY: sdcard
sdcard: $(call builddir,uboot)/.installed
	scripts/flash_sdcard.sh $(IMG)/u-boot-spl.kwb $(IMG)/uboot.env

###############################################################################
# xz
###############################################################################
#
#autogen-xz = $(call target_autoconf_autogen,xz)
#config-xz = $(call target_autoconf_configure,xz,\
#              --prefix= \
#              --disable-scripts \
#              --disable-nls)
#build-xz = $(call target_autoconf_build,xz)
#install-xz = $(call target_autoconf_install,xz)
#clean-xz = $(call target_autoconf_clean,xz)
#uninstall-xz = $(call target_autoconf_uninstall,xz)

################################################################################
# Barebox
################################################################################
#
#barebox_config := rpi2_defconfig
#barebox_src    := $(HOME)/dev/barebox
#barebox_build  := $(BUILD)/barebox
#barebox_mkflags:= ARCH=$(ARCH) \
#                  CROSS_COMPILE=$(CROSS_COMPILE) \
#                  O=$(barebox_build) \
#                  V=$(V)
#
#.PHONY: defconfig-barebox %config-barebox
#defconfig-barebox $(barebox_build)/.config:
#	$(MAKE) -C $(barebox_src) $(barebox_mkflags) $(barebox_config)
#
#%config-barebox:
#	$(MAKE) -C $(barebox_src) $(barebox_mkflags) $(@:-barebox=)
#
#.PHONY: build-barebox
#build-barebox $(barebox_build)/barebox.bin: $(barebox_build)/.config
#	$(MAKE) -C $(barebox_src) $(barebox_mkflags)
#
#.PHONY: clobber-barebox
#clobber-barebox:
#	$(RM) -r $(barebox_build)
