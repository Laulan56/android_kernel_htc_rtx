#Android makefile to build kernel as a part of Android Build
PERL		= perl

KERNEL_TARGET := $(strip $(INSTALLED_KERNEL_TARGET))
ifeq ($(KERNEL_TARGET),)
INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
endif

TARGET_KERNEL_MAKE_ENV := $(strip $(TARGET_KERNEL_MAKE_ENV))
ifeq ($(TARGET_KERNEL_MAKE_ENV),)
KERNEL_MAKE_ENV :=
else
KERNEL_MAKE_ENV := $(TARGET_KERNEL_MAKE_ENV)
endif

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := arm
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

TARGET_KERNEL_HEADER_ARCH := $(strip $(TARGET_KERNEL_HEADER_ARCH))
ifeq ($(TARGET_KERNEL_HEADER_ARCH),)
KERNEL_HEADER_ARCH := $(KERNEL_ARCH)
else
$(warning Forcing kernel header generation only for '$(TARGET_KERNEL_HEADER_ARCH)')
KERNEL_HEADER_ARCH := $(TARGET_KERNEL_HEADER_ARCH)
endif

ifeq ($(shell echo $(KERNEL_DEFCONFIG) | grep vendor),)
KERNEL_DEFCONFIG := vendor/$(KERNEL_DEFCONFIG)
endif

KERNEL_HEADER_DEFCONFIG := $(strip $(KERNEL_HEADER_DEFCONFIG))
ifeq ($(KERNEL_HEADER_DEFCONFIG),)
KERNEL_HEADER_DEFCONFIG := $(KERNEL_DEFCONFIG)
endif

# Force 32-bit binder IPC for 64bit kernel with 32bit userspace
ifeq ($(KERNEL_ARCH),arm64)
ifeq ($(TARGET_ARCH),arm)
KERNEL_CONFIG_OVERRIDE := CONFIG_ANDROID_BINDER_IPC_32BIT=y
endif
endif

TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
ifeq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
KERNEL_CROSS_COMPILE := arm-eabi-
else
KERNEL_CROSS_COMPILE := $(shell pwd)/$(TARGET_TOOLS_PREFIX)
endif

ifeq ($(KERNEL_LLVM_SUPPORT), true)
  ifeq ($(KERNEL_SD_LLVM_SUPPORT), true)  #Using sd-llvm compiler
    ifeq ($(shell echo $(SDCLANG_PATH) | head -c 1),/)
       KERNEL_LLVM_BIN := $(SDCLANG_PATH)/clang
    else
       KERNEL_LLVM_BIN := $(shell pwd)/$(SDCLANG_PATH)/clang
    endif
    $(warning "Using sdllvm" $(KERNEL_LLVM_BIN))
  else
     KERNEL_LLVM_BIN := $(shell pwd)/$(CLANG) #Using aosp-llvm compiler
    $(warning "Using aosp-llvm" $(KERNEL_LLVM_BIN))
  endif
endif

ifeq ($(TARGET_PREBUILT_KERNEL),)

KERNEL_GCC_NOANDROID_CHK := $(shell (echo "int main() {return 0;}" | $(KERNEL_CROSS_COMPILE)gcc -E -mno-android - > /dev/null 2>&1 ; echo $$?))

real_cc :=
ifeq ($(KERNEL_LLVM_SUPPORT),true)
real_cc := REAL_CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=aarch64-linux-gnu-
else
ifeq ($(strip $(KERNEL_GCC_NOANDROID_CHK)),0)
KERNEL_CFLAGS := KCFLAGS=-mno-android
endif
endif

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))
TARGET_KERNEL := msm-$(TARGET_KERNEL_VERSION)
ifeq ($(TARGET_KERNEL),$(current_dir))
    # New style, kernel/msm-version
    BUILD_ROOT_LOC := ../../
    TARGET_KERNEL_SOURCE := kernel/$(TARGET_KERNEL)
    KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/kernel/$(TARGET_KERNEL)
    KERNEL_SYMLINK := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
    KERNEL_USR := $(KERNEL_SYMLINK)/usr
else
    # Legacy style, kernel source directly under kernel
    KERNEL_LEGACY_DIR := true
    BUILD_ROOT_LOC := ../
    TARGET_KERNEL_SOURCE := kernel
    KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
endif

KERNEL_CONFIG := $(KERNEL_OUT)/.config

ifeq ($(KERNEL_DEFCONFIG)$(wildcard $(KERNEL_CONFIG)),)
$(error Kernel configuration not defined, cannot build kernel)
else

ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),true)
$(info Using uncompressed kernel)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image
else
ifeq ($(KERNEL_ARCH),arm64)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image.lz4
else
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/zImage
endif
endif

ifeq ($(TARGET_KERNEL_APPEND_DTB), true)
$(info Using appended DTB)
TARGET_PREBUILT_INT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)-dtb
endif

KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
KERNEL_MODULES_INSTALL ?= system
KERNEL_MODULES_OUT ?= $(PRODUCT_OUT)/$(KERNEL_MODULES_INSTALL)/lib/modules

TARGET_PREBUILT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)

KERNEL_ENABLE_EXFAT ?= $(shell cat $(TARGET_KERNEL_SOURCE)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG) | egrep -v "^\s*\#" | egrep "CONFIG_EXFAT_FS" | sed 's/^\s*CONFIG_EXFAT_FS\s*=\s*//' )
KERNEL_EXFAT_PATH ?= $(shell cat $(TARGET_KERNEL_SOURCE)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG) | egrep -v "^\s*\#" | egrep "CONFIG_EXFAT_PATH" | sed 's/^\s*CONFIG_EXFAT_PATH\s*=\s*\"//' | sed 's/\".*//' )
KERNEL_EXFAT_VERSION ?= $(shell cat $(TARGET_KERNEL_SOURCE)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG) | egrep -v "^\s*\#" | egrep "CONFIG_EXFAT_VERSION" | sed 's/^\s*CONFIG_EXFAT_VERSION\s*=\s*\"//' | sed 's/\".*//' )
BUILD_PATH ?= $(shell pwd)

BOARD_VENDOR_KERNEL_MODULES += $(shell ls $(KERNEL_MODULES_OUT)/*.ko)

define mv-modules
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.dep`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`;\
ko=`find $$mpath/kernel -type f -name *.ko`;\
for i in $$ko; do mv $$i $(KERNEL_MODULES_OUT)/; done;\
fi
endef

define clean-module-folder
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.dep`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`; rm -rf $$mpath;\
fi
endef

ifneq ($(KERNEL_LEGACY_DIR),true)
$(KERNEL_USR): $(KERNEL_HEADERS_INSTALL)
	rm -rf $(KERNEL_SYMLINK)
	ln -s kernel/$(TARGET_KERNEL) $(KERNEL_SYMLINK)

$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_USR)
endif

$(KERNEL_OUT):
	mkdir -p $(KERNEL_OUT)

$(KERNEL_CONFIG): $(KERNEL_OUT)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_DEFCONFIG) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME)
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) oldconfig; fi

$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_OUT) $(KERNEL_HEADERS_INSTALL)
	$(hide) echo "Building kernel..."
	$(hide) rm -rf $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/dts
ifeq ($(KERNEL_ENABLE_EXFAT), m)
	cp vendor/tuxera/exfat/tuxera_update_htc.sh $(TARGET_KERNEL_SOURCE)/
	cp vendor/tuxera/exfat/update_tuxera.sh $(TARGET_KERNEL_SOURCE)/
	cp vendor/tuxera/exfat/build_exfat.sh $(TARGET_KERNEL_SOURCE)/
	cp -rf vendor/tuxera/exfat/texfat $(TARGET_KERNEL_SOURCE)/fs/
	cp -rf vendor/tuxera/exfat/$(KERNEL_EXFAT_PATH) $(TARGET_KERNEL_SOURCE)/fs/
	mkdir -p $(KERNEL_OUT)/fs/$(KERNEL_EXFAT_PATH)
endif

	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME)
ifeq ($(KERNEL_ENABLE_EXFAT), m)
ifeq ($(HTC_DEBUG_FLAG), DEBUG)
ifeq ($(strip $(KERNEL_EXFAT_VERSION)),)
	./$(TARGET_KERNEL_SOURCE)/update_tuxera.sh -p $(KERNEL_EXFAT_PATH) -t target/htc.d/htc -o $(KERNEL_OUT)
else
	./$(TARGET_KERNEL_SOURCE)/update_tuxera.sh -p $(KERNEL_EXFAT_PATH) -t $(KERNEL_EXFAT_VERSION) -o $(KERNEL_OUT)
endif
else
ifeq ($(TARGET_BUILD_VARIANT), user)
	$(warning "User-Release")
ifeq ($(strip $(KERNEL_EXFAT_VERSION)),)
	./$(TARGET_KERNEL_SOURCE)/update_tuxera.sh -p $(KERNEL_EXFAT_PATH) -t target/htc.d/htc -o $(KERNEL_OUT) -r
else
	./$(TARGET_KERNEL_SOURCE)/update_tuxera.sh -p $(KERNEL_EXFAT_PATH) -t $(KERNEL_EXFAT_VERSION) -o $(KERNEL_OUT) -r
endif
else
	$(warning "NonUser-Release")
ifeq ($(strip $(KERNEL_EXFAT_VERSION)),)
	./$(TARGET_KERNEL_SOURCE)/update_tuxera.sh -p $(KERNEL_EXFAT_PATH) -t target/htc.d/htc -o $(KERNEL_OUT) -u
else
	./$(TARGET_KERNEL_SOURCE)/update_tuxera.sh -p $(KERNEL_EXFAT_PATH) -t $(KERNEL_EXFAT_VERSION) -o $(KERNEL_OUT) -u
endif
endif

endif
endif
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) modules
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) INSTALL_MOD_PATH=$(BUILD_ROOT_LOC)../$(KERNEL_MODULES_INSTALL) INSTALL_MOD_STRIP=1 $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) modules_install
ifeq ($(KERNEL_ENABLE_EXFAT), m)
ifeq ($(HTC_DEBUG_FLAG), DEBUG)
	# Build exfat modules for DEBUG
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) SUBDIRS=$(BUILD_PATH)/$(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/objects modules
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) SUBDIRS=fs/$(KERNEL_EXFAT_PATH)/objects INSTALL_MOD_PATH=$(BUILD_ROOT_LOC)../$(KERNEL_MODULES_INSTALL) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) modules_install
	cp $(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/objects/texfat.ko $(KERNEL_MODULES_OUT)/
	mkdir -p $(TARGET_OUT)/bin/
	cp -rf $(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/bin/* $(TARGET_OUT)/bin/
else
ifeq ($(TARGET_BUILD_VARIANT), user)
	# Build exfat modules for NonDebug-USER
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) SUBDIRS=$(BUILD_PATH)/$(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/objects-user modules
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) SUBDIRS=fs/$(KERNEL_EXFAT_PATH)/objects-user INSTALL_MOD_PATH=$(BUILD_ROOT_LOC)../$(KERNEL_MODULES_INSTALL) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) modules_install
	cp $(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/objects-user/texfat.ko $(KERNEL_MODULES_OUT)/
	mkdir -p $(TARGET_OUT)/bin/
	cp -rf $(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/bin/* $(TARGET_OUT)/bin/
else
	# Build exfat modules for NonDebug-USERDEBUG
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) SUBDIRS=$(BUILD_PATH)/$(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/objects-userdebug modules
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) SUBDIRS=fs/$(KERNEL_EXFAT_PATH)/objects-userdebug INSTALL_MOD_PATH=$(BUILD_ROOT_LOC)../$(KERNEL_MODULES_INSTALL) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) PRIVATE_RCMS_NAME=$(PRIVATE_RCMS_NAME) PRIVATE_SKU_NAME=$(PRIVATE_SKU_NAME) modules_install
	cp $(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/objects-userdebug/texfat.ko $(KERNEL_MODULES_OUT)/
	mkdir -p $(TARGET_OUT)/bin/
	cp -rf $(TARGET_KERNEL_SOURCE)/fs/$(KERNEL_EXFAT_PATH)/bin/* $(TARGET_OUT)/bin/
endif
endif
endif
	$(mv-modules)
	$(clean-module-folder)

ifeq ($(KERNEL_ENABLE_EXFAT), m)
	rm $(TARGET_KERNEL_SOURCE)/tuxera_update_htc.sh
	rm $(TARGET_KERNEL_SOURCE)/update_tuxera.sh
	rm $(TARGET_KERNEL_SOURCE)/build_exfat.sh
	rm -rf $(TARGET_KERNEL_SOURCE)/fs/texfat*
endif

$(KERNEL_HEADERS_INSTALL): $(KERNEL_OUT)
	$(hide) if [ ! -z "$(KERNEL_HEADER_DEFCONFIG)" ]; then \
			rm -f $(BUILD_ROOT_LOC)$(KERNEL_CONFIG); \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_HEADER_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_HEADER_DEFCONFIG); \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_HEADER_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) headers_install;\
			if [ -d "$(KERNEL_HEADERS_INSTALL)/include/bringup_headers" ]; then \
				cp -Rf  $(KERNEL_HEADERS_INSTALL)/include/bringup_headers/* $(KERNEL_HEADERS_INSTALL)/include/ ;\
			fi ;\
			fi
	$(hide) if [ "$(KERNEL_HEADER_DEFCONFIG)" != "$(KERNEL_DEFCONFIG)" ]; then \
			echo "Used a different defconfig for header generation"; \
			rm -f $(BUILD_ROOT_LOC)$(KERNEL_CONFIG); \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_DEFCONFIG); fi
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) oldconfig; fi

.PHONY: kerneltags
kerneltags: $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) tags

.PHONY: kernelconfig
kernelconfig: $(KERNEL_OUT) $(KERNEL_CONFIG)
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) menuconfig
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) savedefconfig
	cp $(KERNEL_OUT)/defconfig $(TARGET_KERNEL_SOURCE)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG)

endif
endif
