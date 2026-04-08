# SPDX-License-Identifier: BSD-3-Clause

SCP_DIR := $(CURDIR)/SCP-firmware
TFA_DIR := $(CURDIR)/tf-a
AP_DIR := $(CURDIR)/ap/hello_aarch64
SCP_PRODUCT ?= qemu_virt_m7
SCP_FIRMWARE ?= fw
SCP_BUILD_DIR ?= $(CURDIR)/build/scp/$(SCP_PRODUCT)
AP_BUILD_DIR ?= $(CURDIR)/build/ap/hello_aarch64
SCP_BUILD_SYSTEM ?= Make
SCP_TOOLCHAIN ?= GNU
SCP_IMAGE ?= $(SCP_BUILD_DIR)/firmware-$(SCP_FIRMWARE)/bin/$(SCP_PRODUCT).elf
AP_CROSS_COMPILE ?= aarch64-linux-gnu-
AP_CC ?= $(AP_CROSS_COMPILE)gcc
AP_OBJCOPY ?= $(AP_CROSS_COMPILE)objcopy
AP_CFLAGS ?= -O2 -g -ffreestanding -fno-builtin -mcpu=cortex-a53 -Wall -Wextra
AP_LDFLAGS ?= -nostdlib -nostartfiles -Wl,-T,$(AP_DIR)/linker.ld -Wl,-Map,$(AP_BUILD_DIR)/ap_hello_aarch64.map
AP_IMAGE ?= $(AP_BUILD_DIR)/ap_hello_aarch64.elf
AP_BINARY ?= $(AP_BUILD_DIR)/ap_hello_aarch64.bin
AP_LOG ?= $(AP_BUILD_DIR)/ap_hello_aarch64.log
AP_LOAD_ADDR ?= 0x60000000
XTERM ?= xterm
XTERM_ARGS ?=
XTERM_SCP_TITLE ?= SCP-QEMU
XTERM_AP_TITLE ?= AP-QEMU
XTERM_AP_BAREMETAL_TITLE ?= AP-BAREMETAL-QEMU
DEMO_BUILD_DIR ?= $(CURDIR)/build/demo
DEMO_SCP_LOG ?= $(DEMO_BUILD_DIR)/scp.log
DEMO_AP_LOG ?= $(DEMO_BUILD_DIR)/ap.log
TFA_PLAT ?= qemu
TFA_BUILD_TYPE ?= debug
TFA_BUILD_DIR ?= $(TFA_DIR)/build/$(TFA_PLAT)/$(TFA_BUILD_TYPE)
TFA_BL1_IMAGE ?= $(TFA_BUILD_DIR)/bl1.bin
TFA_FIP_IMAGE ?= $(TFA_BUILD_DIR)/fip.bin
TFA_FLASH_IMAGE ?= $(TFA_BUILD_DIR)/flash.bin
TFA_LOG_LEVEL ?= 40
TFA_LOG ?= $(AP_BUILD_DIR)/tf_a.log
BRIDGE_SHM_PATH ?= /tmp/qemu_virt_soc.scmi_bridge.shm
BRIDGE_AP_SOCK ?= /tmp/qemu_virt_soc.ap.sock
BRIDGE_SCP_SOCK ?= /tmp/qemu_virt_soc.scp.sock
QEMU_BUILD_DIR ?= $(CURDIR)/qemu/build
QEMU_SYSTEM_ARM ?= $(QEMU_BUILD_DIR)/qemu-system-arm
QEMU_SYSTEM_AARCH64 ?= $(QEMU_BUILD_DIR)/qemu-system-aarch64
QEMU_AARCH64_MEMORY ?= 1024
SCP_LOG ?= $(CURDIR)/build/scp/$(SCP_PRODUCT)/qemu.log

.PHONY: all ap tfa scp run-ap run-ap-baremetal run-scp run-demo scp-clean ap-clean tfa-clean toolchain-check qemu-check-arm qemu-check-aarch64 ap-toolchain-check help

all: ap tfa scp

ap: ap-toolchain-check $(AP_IMAGE) $(AP_BINARY)

$(AP_BUILD_DIR):
	mkdir -p $@

$(AP_IMAGE): $(AP_DIR)/start.S $(AP_DIR)/main.c $(AP_DIR)/linker.ld | $(AP_BUILD_DIR)
	$(AP_CC) $(AP_CFLAGS) $(AP_LDFLAGS) -o $@ $(AP_DIR)/start.S $(AP_DIR)/main.c

$(AP_BINARY): $(AP_IMAGE)
	$(AP_OBJCOPY) -O binary $< $@

tfa: ap qemu-check-aarch64
	$(MAKE) -C $(TFA_DIR) \
		CROSS_COMPILE=$(AP_CROSS_COMPILE) \
		PLAT=$(TFA_PLAT) \
		DEBUG=$(if $(filter debug,$(TFA_BUILD_TYPE)),1,0) \
		LOG_LEVEL=$(TFA_LOG_LEVEL) \
		BL33=$(AP_BINARY) \
		all fip
	dd if=$(TFA_BL1_IMAGE) of=$(TFA_FLASH_IMAGE) bs=4096 conv=notrunc status=none
	dd if=$(TFA_FIP_IMAGE) of=$(TFA_FLASH_IMAGE) seek=64 bs=4096 conv=notrunc status=none

scp: toolchain-check
	$(MAKE) -C $(SCP_DIR) -f Makefile.cmake \
		PRODUCT=$(SCP_PRODUCT) \
		BUILD_SYSTEM=$(SCP_BUILD_SYSTEM) \
		TOOLCHAIN=$(SCP_TOOLCHAIN) \
		DIRECT_BUILD=y \
		BUILD_PATH=$(SCP_BUILD_DIR) \
		firmware-$(SCP_FIRMWARE)

run-ap: tfa qemu-check-aarch64
	@echo "Launching AP TF-A run in xterm. Close the xterm window to stop QEMU."
	@mkdir -p "$(AP_BUILD_DIR)"
	@$(RM) "$(TFA_LOG)"
	@touch "$(TFA_LOG)"
	@"$(XTERM)" $(XTERM_ARGS) -T "$(XTERM_AP_TITLE)" -e /bin/bash -lc '\
		trap "jobs -pr | xargs -r kill >/dev/null 2>&1 || true; wait >/dev/null 2>&1 || true" EXIT HUP INT TERM; \
		tail -n +1 -F "$(TFA_LOG)" & \
		tail_pid=$$!; \
		"$(QEMU_SYSTEM_AARCH64)" \
			-machine virt,secure=on \
			-cpu cortex-a53 \
			-m $(QEMU_AARCH64_MEMORY) \
			-display none \
			-monitor none \
			-serial file:"$(TFA_LOG)" \
			-bios "$(TFA_FLASH_IMAGE)" & \
		qemu_pid=$$!; \
		wait $$qemu_pid; \
		status=$$?; \
		kill $$tail_pid >/dev/null 2>&1 || true; \
		wait $$tail_pid >/dev/null 2>&1 || true; \
		printf "\n[AP] QEMU exited with status %s\n" "$$status" >> "$(TFA_LOG)"; \
		exit $$status' &

run-ap-baremetal: ap qemu-check-aarch64
	@echo "Launching AP baremetal run in xterm. Close the xterm window to stop QEMU."
	@mkdir -p "$(AP_BUILD_DIR)"
	@$(RM) "$(AP_LOG)"
	@touch "$(AP_LOG)"
	@"$(XTERM)" $(XTERM_ARGS) -T "$(XTERM_AP_BAREMETAL_TITLE)" -e /bin/bash -lc '\
		trap "jobs -pr | xargs -r kill >/dev/null 2>&1 || true; wait >/dev/null 2>&1 || true" EXIT HUP INT TERM; \
		tail -n +1 -F "$(AP_LOG)" & \
		tail_pid=$$!; \
		"$(QEMU_SYSTEM_AARCH64)" \
			-machine virt \
			-cpu cortex-a53 \
			-m $(QEMU_AARCH64_MEMORY) \
			-display none \
			-monitor none \
			-serial file:"$(AP_LOG)" \
			-kernel "$(AP_IMAGE)" & \
		qemu_pid=$$!; \
		wait $$qemu_pid; \
		status=$$?; \
		kill $$tail_pid >/dev/null 2>&1 || true; \
		wait $$tail_pid >/dev/null 2>&1 || true; \
		printf "\n[AP] QEMU exited with status %s\n" "$$status" >> "$(AP_LOG)"; \
		exit $$status' &

run-scp: scp qemu-check-arm
	@echo "Launching SCP run in xterm. Close the xterm window to stop QEMU."
	@mkdir -p "$(dir $(SCP_LOG))"
	@$(RM) "$(SCP_LOG)"
	@touch "$(SCP_LOG)"
	@"$(XTERM)" $(XTERM_ARGS) -T "$(XTERM_SCP_TITLE)" -e /bin/bash -lc '\
		trap "jobs -pr | xargs -r kill >/dev/null 2>&1 || true; wait >/dev/null 2>&1 || true" EXIT HUP INT TERM; \
		tail -n +1 -F "$(SCP_LOG)" & \
		tail_pid=$$!; \
		"$(QEMU_SYSTEM_ARM)" \
			-M mps2-an500 \
			-cpu cortex-m7 \
			-display none \
			-monitor none \
			-serial file:"$(SCP_LOG)" \
			-semihosting \
			-kernel "$(SCP_IMAGE)" & \
		qemu_pid=$$!; \
		wait $$qemu_pid; \
		status=$$?; \
		kill $$tail_pid >/dev/null 2>&1 || true; \
		wait $$tail_pid >/dev/null 2>&1 || true; \
		printf "\n[SCP] QEMU exited with status %s\n" "$$status" >> "$(SCP_LOG)"; \
		exit $$status' &

run-demo: scp tfa qemu-check-arm qemu-check-aarch64
	@echo "Launching separate xterm windows for SCP-side and AP-side QEMU logs."
	@mkdir -p "$(DEMO_BUILD_DIR)"
	@$(RM) "$(BRIDGE_AP_SOCK)" "$(BRIDGE_SCP_SOCK)" "$(BRIDGE_SHM_PATH)" "$(DEMO_SCP_LOG)" "$(DEMO_AP_LOG)"
	@touch "$(DEMO_SCP_LOG)" "$(DEMO_AP_LOG)"
	@"$(XTERM)" $(XTERM_ARGS) -T "$(XTERM_SCP_TITLE)" -e /bin/bash -lc '\
		trap "jobs -pr | xargs -r kill >/dev/null 2>&1 || true; wait >/dev/null 2>&1 || true" EXIT HUP INT TERM; \
		tail -n +1 -F "$(DEMO_SCP_LOG)" & \
		tail_pid=$$!; \
		"$(QEMU_SYSTEM_ARM)" \
			-M mps2-an500 \
			-cpu cortex-m7 \
			-display none \
			-monitor none \
			-serial file:"$(DEMO_SCP_LOG)" \
			-semihosting \
			-kernel "$(SCP_IMAGE)" & \
		qemu_pid=$$!; \
		wait $$qemu_pid; \
		status=$$?; \
		kill $$tail_pid >/dev/null 2>&1 || true; \
		wait $$tail_pid >/dev/null 2>&1 || true; \
		printf "\n[SCP] QEMU exited with status %s\n" "$$status" >> "$(DEMO_SCP_LOG)"; \
		exit $$status' & \
	sleep 1; \
	"$(XTERM)" $(XTERM_ARGS) -T "$(XTERM_AP_TITLE)" -e /bin/bash -lc '\
		trap "jobs -pr | xargs -r kill >/dev/null 2>&1 || true; wait >/dev/null 2>&1 || true" EXIT HUP INT TERM; \
		tail -n +1 -F "$(DEMO_AP_LOG)" & \
		tail_pid=$$!; \
		"$(QEMU_SYSTEM_AARCH64)" \
			-machine virt,secure=on \
			-cpu cortex-a53 \
			-m $(QEMU_AARCH64_MEMORY) \
			-display none \
			-monitor none \
			-serial file:"$(DEMO_AP_LOG)" \
			-bios "$(TFA_FLASH_IMAGE)" & \
		qemu_pid=$$!; \
		wait $$qemu_pid; \
		status=$$?; \
		kill $$tail_pid >/dev/null 2>&1 || true; \
		wait $$tail_pid >/dev/null 2>&1 || true; \
		printf "\n[AP] QEMU exited with status %s\n" "$$status" >> "$(DEMO_AP_LOG)"; \
		exit $$status'

scp-clean:
	$(RM) -r $(SCP_BUILD_DIR)

ap-clean:
	$(RM) -r $(AP_BUILD_DIR)

tfa-clean:
	$(MAKE) -C $(TFA_DIR) PLAT=$(TFA_PLAT) distclean

toolchain-check:
	@test -x "$(CURDIR)/toolchains/arm-none-eabi-gcc/bin/arm-none-eabi-gcc" || \
		{ echo "Missing toolchain: toolchains/arm-none-eabi-gcc"; \
		  echo "Run: git submodule update --init --recursive"; \
		  exit 1; }

ap-toolchain-check:
	@test -x "$$(command -v $(AP_CC))" || \
		{ echo "Missing AP compiler: $(AP_CC)"; \
		  exit 1; }
	@test -x "$$(command -v $(AP_OBJCOPY))" || \
		{ echo "Missing AP objcopy: $(AP_OBJCOPY)"; \
		  exit 1; }

qemu-check-arm:
	@test -x "$(QEMU_SYSTEM_ARM)" || \
		{ echo "Missing QEMU binary: $(QEMU_SYSTEM_ARM)"; \
		  echo "Build QEMU first:"; \
		  echo "  cd qemu && mkdir -p build && cd build"; \
		  echo "  ../configure --target-list=aarch64-softmmu,arm-softmmu"; \
		  echo "  ninja qemu-system-aarch64 qemu-system-arm"; \
		  exit 1; }

qemu-check-aarch64:
	@test -x "$(QEMU_SYSTEM_AARCH64)" || \
		{ echo "Missing QEMU binary: $(QEMU_SYSTEM_AARCH64)"; \
		  echo "Build QEMU first:"; \
		  echo "  cd qemu && mkdir -p build && cd build"; \
		  echo "  ../configure --target-list=aarch64-softmmu,arm-softmmu"; \
		  echo "  ninja qemu-system-aarch64 qemu-system-arm"; \
		  exit 1; }

help:
	@echo "Targets:"
	@echo "  all        Build the default targets"
	@echo "  ap         Build the AP-side baremetal image"
	@echo "  tfa        Build TF-A BL31 for the AP side"
	@echo "  scp        Build SCP-firmware product $(SCP_PRODUCT)"
	@echo "  run-ap     Run TF-A BL31 and the AP-side BL33 payload in QEMU"
	@echo "  run-ap-baremetal  Run the AP-side baremetal image directly in QEMU"
	@echo "  run-scp    Run the SCP firmware in QEMU and print live UART output"
	@echo "  run-demo   Run both AP-side and SCP-side QEMU instances together"
	@echo "  ap-clean   Remove AP build directory"
	@echo "  tfa-clean  Remove TF-A build output"
	@echo "  scp-clean  Remove SCP build directory"
	@echo ""
	@echo "Variables:"
	@echo "  TFA_DIR=$(TFA_DIR)"
	@echo "  AP_DIR=$(AP_DIR)"
	@echo "  AP_BUILD_DIR=$(AP_BUILD_DIR)"
	@echo "  AP_CC=$(AP_CC)"
	@echo "  AP_OBJCOPY=$(AP_OBJCOPY)"
	@echo "  AP_IMAGE=$(AP_IMAGE)"
	@echo "  AP_BINARY=$(AP_BINARY)"
	@echo "  AP_LOG=$(AP_LOG)"
	@echo "  AP_LOAD_ADDR=$(AP_LOAD_ADDR)"
	@echo "  XTERM=$(XTERM)"
	@echo "  XTERM_ARGS=$(XTERM_ARGS)"
	@echo "  XTERM_SCP_TITLE=$(XTERM_SCP_TITLE)"
	@echo "  XTERM_AP_TITLE=$(XTERM_AP_TITLE)"
	@echo "  XTERM_AP_BAREMETAL_TITLE=$(XTERM_AP_BAREMETAL_TITLE)"
	@echo "  SCP_PRODUCT=$(SCP_PRODUCT)"
	@echo "  SCP_FIRMWARE=$(SCP_FIRMWARE)"
	@echo "  SCP_BUILD_DIR=$(SCP_BUILD_DIR)"
	@echo "  SCP_BUILD_SYSTEM=$(SCP_BUILD_SYSTEM)"
	@echo "  SCP_TOOLCHAIN=$(SCP_TOOLCHAIN)"
	@echo "  SCP_IMAGE=$(SCP_IMAGE)"
	@echo "  SCP_LOG=$(SCP_LOG)"
	@echo "  DEMO_BUILD_DIR=$(DEMO_BUILD_DIR)"
	@echo "  DEMO_SCP_LOG=$(DEMO_SCP_LOG)"
	@echo "  DEMO_AP_LOG=$(DEMO_AP_LOG)"
	@echo "  TFA_PLAT=$(TFA_PLAT)"
	@echo "  TFA_BUILD_TYPE=$(TFA_BUILD_TYPE)"
	@echo "  TFA_BUILD_DIR=$(TFA_BUILD_DIR)"
	@echo "  TFA_BL1_IMAGE=$(TFA_BL1_IMAGE)"
	@echo "  TFA_FIP_IMAGE=$(TFA_FIP_IMAGE)"
	@echo "  TFA_FLASH_IMAGE=$(TFA_FLASH_IMAGE)"
	@echo "  TFA_LOG_LEVEL=$(TFA_LOG_LEVEL)"
	@echo "  TFA_LOG=$(TFA_LOG)"
	@echo "  BRIDGE_SHM_PATH=$(BRIDGE_SHM_PATH)"
	@echo "  BRIDGE_AP_SOCK=$(BRIDGE_AP_SOCK)"
	@echo "  BRIDGE_SCP_SOCK=$(BRIDGE_SCP_SOCK)"
	@echo "  QEMU_BUILD_DIR=$(QEMU_BUILD_DIR)"
	@echo "  QEMU_SYSTEM_ARM=$(QEMU_SYSTEM_ARM)"
	@echo "  QEMU_SYSTEM_AARCH64=$(QEMU_SYSTEM_AARCH64)"
	@echo "  QEMU_AARCH64_MEMORY=$(QEMU_AARCH64_MEMORY)"
