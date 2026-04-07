# QEMU Virtual SoC

This repository hosts a virtual SoC experiment that runs the application
processor side and the system control processor side in two cooperating QEMU
instances.

The top-level repository tracks the integration code and documentation. The
upstream QEMU and SCP-firmware source trees are managed as Git submodules.

## Architecture

```text
+------------------------+        socket/eventfd         +------------------------+
| QEMU #1 (AP side)      | <---------------------------> | QEMU #2 (SCP side)     |
| qemu-system-aarch64    |                               | qemu-system-arm        |
| A-profile board        |        shared memory         | mps2-an500             |
| TF-A / baremetal / OS  | <---------------------------> | SCP-firmware           |
+------------------------+                               +------------------------+
           |                                                         |
           | custom sysbus device                                    | custom sysbus device
           | "scmi-mailbox-bridge"                                   | "scmi-mailbox-bridge"
           +---------------- MMIO regs + IRQ -------------------------+
```

The model is split into two processes:

- `QEMU #1` emulates the AP side with `qemu-system-aarch64`.
- `QEMU #2` emulates the SCP side with `qemu-system-arm` and the `mps2-an500`
  machine.
- Both QEMU instances contain a custom sysbus device named
  `scmi-mailbox-bridge`.
- The bridge exposes MMIO registers and IRQs to the guest firmware/software.
- The two bridge devices exchange mailbox state through host-side
  socket/eventfd signaling and shared memory.
- The AP side can run TF-A, baremetal software, or an OS.
- The SCP side runs SCP-firmware.

The goal is to prototype an SCMI mailbox path where the AP and SCP run in
separate QEMU processes while still behaving like two processors connected by
SoC-level mailbox hardware.

## Repository Layout

```text
.
|-- qemu/           # QEMU source tree, tracked as a submodule
|-- SCP-firmware/   # Arm SCP-firmware source tree, tracked as a submodule
|-- .gitmodules     # Submodule URL and path configuration
`-- README.md       # Project overview
```

## Clone

Clone the repository with submodules:

```bash
git clone --recurse-submodules <repo-url>
cd qemu_virt_soc
```

If the repository was cloned without submodules, initialize them afterwards:

```bash
git submodule update --init --recursive
```

## Submodules

Current submodule configuration:

```text
qemu:
  path: qemu
  url:  git@github.com:buzhidaojiaoshenm/qemu.git

SCP-firmware:
  path: SCP-firmware
  url:  git@github.com:buzhidaojiaoshenm/SCP-firmware.git
```

The top-level repository records the exact commit checked out for each
submodule. When changing QEMU or SCP-firmware, commit the changes inside the
submodule first, then commit the updated submodule pointer in the top-level
repository.

## Build

The exact build commands depend on the target boards, firmware payloads, and
local toolchain paths. At a high level:

1. Build QEMU from `qemu/` with the AArch64 and Arm system targets enabled.
2. Build SCP-firmware from `SCP-firmware/` for the SCP-side target.
3. Build or provide the AP-side payload, such as TF-A, a baremetal image, or an
   OS image.
4. Launch the AP-side and SCP-side QEMU instances with matching
   `scmi-mailbox-bridge` configuration so they connect to the same host-side
   socket/eventfd and shared-memory channel.

Example placeholders:

```bash
# Build QEMU.
cd qemu
# TODO: add project-specific QEMU configure/build command.

# Build SCP-firmware.
cd ../SCP-firmware
# TODO: add project-specific SCP-firmware build command.
```

## Run

The runtime setup requires two QEMU processes:

```bash
# Terminal 1: AP side
# TODO: qemu/build/qemu-system-aarch64 \
#   -machine <ap-board> \
#   -device scmi-mailbox-bridge,...

# Terminal 2: SCP side
# TODO: qemu/build/qemu-system-arm \
#   -machine mps2-an500 \
#   -device scmi-mailbox-bridge,...
```

Both sides must agree on the bridge transport endpoints and shared-memory
layout. The SCP side should boot the SCP-firmware image, while the AP side
should boot the firmware or OS payload that uses the SCMI mailbox.

## Development Notes

- Keep QEMU-specific changes inside the `qemu/` submodule.
- Keep SCP-firmware-specific changes inside the `SCP-firmware/` submodule.
- Keep integration notes, scripts, and top-level documentation in this
  repository.
- After updating a submodule commit, run `git status` at the repository root to
  confirm the top-level submodule pointer changed.
