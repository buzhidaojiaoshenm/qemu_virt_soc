# SPDX-License-Identifier: BSD-3-Clause

SCP_DIR := $(CURDIR)/SCP-firmware
SCP_PRODUCT ?= qemu_virt_m7
SCP_FIRMWARE ?= fw
SCP_BUILD_DIR ?= $(CURDIR)/build/scp/$(SCP_PRODUCT)
SCP_BUILD_SYSTEM ?= Make
SCP_TOOLCHAIN ?= GNU

.PHONY: all scp scp-clean toolchain-check help

all: scp

scp: toolchain-check
	$(MAKE) -C $(SCP_DIR) -f Makefile.cmake \
		PRODUCT=$(SCP_PRODUCT) \
		BUILD_SYSTEM=$(SCP_BUILD_SYSTEM) \
		TOOLCHAIN=$(SCP_TOOLCHAIN) \
		DIRECT_BUILD=y \
		BUILD_PATH=$(SCP_BUILD_DIR) \
		firmware-$(SCP_FIRMWARE)

scp-clean:
	$(RM) -r $(SCP_BUILD_DIR)

toolchain-check:
	@test -x "$(CURDIR)/toolchains/arm-none-eabi-gcc/bin/arm-none-eabi-gcc" || \
		{ echo "Missing toolchain: toolchains/arm-none-eabi-gcc"; \
		  echo "Run: git submodule update --init --recursive"; \
		  exit 1; }

help:
	@echo "Targets:"
	@echo "  all        Build the default targets"
	@echo "  scp        Build SCP-firmware product $(SCP_PRODUCT)"
	@echo "  scp-clean  Remove SCP build directory"
	@echo ""
	@echo "Variables:"
	@echo "  SCP_PRODUCT=$(SCP_PRODUCT)"
	@echo "  SCP_FIRMWARE=$(SCP_FIRMWARE)"
	@echo "  SCP_BUILD_DIR=$(SCP_BUILD_DIR)"
	@echo "  SCP_BUILD_SYSTEM=$(SCP_BUILD_SYSTEM)"
	@echo "  SCP_TOOLCHAIN=$(SCP_TOOLCHAIN)"

