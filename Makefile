# SPDX-License-Identifier: BSD-3-Clause

SCP_DIR := $(CURDIR)/SCP-firmware
SCP_PRODUCT ?= qemu_virt_m7
SCP_FIRMWARE ?= fw
SCP_BUILD_DIR ?= $(CURDIR)/build/scp/$(SCP_PRODUCT)
SCP_BUILD_SYSTEM ?= Make
SCP_TOOLCHAIN ?= GNU
SCP_IMAGE ?= $(SCP_BUILD_DIR)/firmware-$(SCP_FIRMWARE)/bin/$(SCP_PRODUCT).elf
QEMU_BUILD_DIR ?= $(CURDIR)/qemu/build
QEMU_SYSTEM_ARM ?= $(QEMU_BUILD_DIR)/qemu-system-arm
QEMU_SYSTEM_AARCH64 ?= $(QEMU_BUILD_DIR)/qemu-system-aarch64
QEMU_TIMEOUT ?= 5s
QEMU_UART_FIFO ?= $(CURDIR)/build/scp/$(SCP_PRODUCT)/uart.fifo

.PHONY: all scp run-scp scp-clean toolchain-check qemu-check help

all: scp

scp: toolchain-check
	$(MAKE) -C $(SCP_DIR) -f Makefile.cmake \
		PRODUCT=$(SCP_PRODUCT) \
		BUILD_SYSTEM=$(SCP_BUILD_SYSTEM) \
		TOOLCHAIN=$(SCP_TOOLCHAIN) \
		DIRECT_BUILD=y \
		BUILD_PATH=$(SCP_BUILD_DIR) \
		firmware-$(SCP_FIRMWARE)

run-scp: scp qemu-check
	@echo "Running $(SCP_IMAGE) on QEMU. UART output follows:"
	@$(RM) "$(QEMU_UART_FIFO)"
	@mkfifo "$(QEMU_UART_FIFO)"
	@cat "$(QEMU_UART_FIFO)" & cat_pid=$$!; \
	status=0; \
	timeout $(QEMU_TIMEOUT) $(QEMU_SYSTEM_ARM) \
		-M mps2-an500 \
		-cpu cortex-m7 \
		-display none \
		-monitor none \
		-serial file:$(QEMU_UART_FIFO) \
		-semihosting \
		-kernel $(SCP_IMAGE) || status=$$?; \
	kill $$cat_pid >/dev/null 2>&1 || true; \
	$(RM) "$(QEMU_UART_FIFO)"; \
	if [ "$$status" -ne 0 ] && [ "$$status" -ne 124 ]; then \
		exit $$status; \
	fi

scp-clean:
	$(RM) -r $(SCP_BUILD_DIR)

toolchain-check:
	@test -x "$(CURDIR)/toolchains/arm-none-eabi-gcc/bin/arm-none-eabi-gcc" || \
		{ echo "Missing toolchain: toolchains/arm-none-eabi-gcc"; \
		  echo "Run: git submodule update --init --recursive"; \
		  exit 1; }

qemu-check:
	@test -x "$(QEMU_SYSTEM_ARM)" || \
		{ echo "Missing QEMU binary: $(QEMU_SYSTEM_ARM)"; \
		  echo "Build QEMU first:"; \
		  echo "  cd qemu && mkdir -p build && cd build"; \
		  echo "  ../configure --target-list=aarch64-softmmu,arm-softmmu"; \
		  echo "  ninja qemu-system-aarch64 qemu-system-arm"; \
		  exit 1; }

help:
	@echo "Targets:"
	@echo "  all        Build the default targets"
	@echo "  scp        Build SCP-firmware product $(SCP_PRODUCT)"
	@echo "  run-scp    Run the SCP firmware in QEMU and print live UART output"
	@echo "  scp-clean  Remove SCP build directory"
	@echo ""
	@echo "Variables:"
	@echo "  SCP_PRODUCT=$(SCP_PRODUCT)"
	@echo "  SCP_FIRMWARE=$(SCP_FIRMWARE)"
	@echo "  SCP_BUILD_DIR=$(SCP_BUILD_DIR)"
	@echo "  SCP_BUILD_SYSTEM=$(SCP_BUILD_SYSTEM)"
	@echo "  SCP_TOOLCHAIN=$(SCP_TOOLCHAIN)"
	@echo "  SCP_IMAGE=$(SCP_IMAGE)"
	@echo "  QEMU_BUILD_DIR=$(QEMU_BUILD_DIR)"
	@echo "  QEMU_SYSTEM_ARM=$(QEMU_SYSTEM_ARM)"
	@echo "  QEMU_SYSTEM_AARCH64=$(QEMU_SYSTEM_AARCH64)"
	@echo "  QEMU_TIMEOUT=$(QEMU_TIMEOUT)"
	@echo "  QEMU_UART_FIFO=$(QEMU_UART_FIFO)"
