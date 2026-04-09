# QEMU Virtual SoC

This repository integrates a split AP/SCP virtual platform built from two
cooperating QEMU processes:

- AP side: `qemu-system-aarch64`, `virt` machine, TF-A + AArch64 baremetal BL33
- SCP side: `qemu-system-arm`, custom `qemu-scp-m7` machine, `SCP-firmware`
  product `qemu_virt_m7`

The current implementation already supports:

- AP/SCP boot in separate QEMU processes
- SCMI BASE traffic from TF-A to SCP-firmware
- shared CMN configuration-space model visible from both AP and SCP
- SCP-side `cmn-cyprus` initialization against the emulated CMN topology
- AP-side dump of the configured CMN register space

## Architecture

```text
+------------------------+                               +------------------------+
| QEMU #1 (AP side)      |                               | QEMU #2 (SCP side)     |
| qemu-system-aarch64    |                               | qemu-system-arm        |
| machine: virt          |                               | machine: qemu-scp-m7   |
| TF-A + BL33 baremetal  |                               | SCP-firmware           |
+-----------+------------+                               +------------+-----------+
            |                                                             |
            | shared CMN config aperture                                  |
            +--------------------------+  +-------------------------------+
                                       |  |
AP CMN base:  0x140000000              |  | SCP CMN base: 0x60000000
size:         1GB                      |  | size:         1GB
                                       v  v
                             +----------------------+
                             | arm-cmn-cfg          |
                             | shared RAM-backed    |
                             | config-space model   |
                             +----------------------+

+------------------------+        host socket + shm        +------------------------+
| AP scmi-mailbox-bridge | <-----------------------------> | SCP scmi-mailbox-bridge|
+------------------------+                                 +------------------------+
            |                                                             |
            | MMIO regs + shared mailbox                                  |
            |                                                             |
AP side TF-A SCMI client                                      SCP side transport/scmi server
```

## Repository Layout

```text
.
|-- ap/                            # AP-side baremetal BL33 payload
|-- qemu/                          # QEMU fork
|-- SCP-firmware/                  # SCP-firmware fork
|-- tf-a/                          # TF-A fork
|-- toolchains/arm-none-eabi-gcc/  # project-local Arm GNU toolchain
|-- Makefile                       # top-level build/run entry
|-- .gitmodules
`-- README.md
```

## Submodules

Current submodules:

```text
qemu                           -> git@github.com:buzhidaojiaoshenm/qemu.git
SCP-firmware                   -> git@github.com:buzhidaojiaoshenm/SCP-firmware.git
tf-a                           -> git@github.com:buzhidaojiaoshenm/arm-trusted-firmware.git
toolchains/arm-none-eabi-gcc   -> git@github.com:buzhidaojiaoshenm/arm-none-eabi-gcc.git
```

Clone with submodules:

```bash
git clone --recurse-submodules <repo-url>
cd qemu_virt_soc
```

If needed:

```bash
git submodule update --init --recursive
```

## Current AP Side

- QEMU machine: `virt`
- CPU: `cortex-a53`
- TF-A platform: `qemu`
- BL33 payload: `ap/hello_aarch64`
- BL33 load address: `0x60000000`
- UART: PL011 at `0x09000000`

Current BL33 behavior:

- prints boot message
- reads CMN discovery registers
- dumps all non-zero 64-bit registers in the seeded/configured CMN space

## Current SCP Side

- QEMU machine: `qemu-scp-m7`
- CPU: `cortex-m7`
- SCP-firmware product: `qemu_virt_m7`

### SCP Memory Map

```text
ITCM   0x00000000 - 0x000bffff
DTCM   0x20000000 - 0x2007ffff
```

### SCP Peripheral Map

```text
GTIMER CNTCTL / control   0x44000000 - 0x44000fff
GTIMER frame              0x44001000 - 0x44001fff
PL011 UART                0x44002000 - 0x44004fff
SP805 watchdog            0x44006000 - 0x44006fff

MHU NS recv / bridge regs 0x45000000 - 0x4500ffff
MHU NS send / mailbox shm 0x45010000 - 0x4501ffff
MHU S recv  reserved      0x45020000 - 0x4502ffff
MHU S send  reserved      0x45030000 - 0x4503ffff

CMN config aperture       0x60000000 - 0x9fffffff
```

### SCP-firmware Modules

`qemu_virt_m7` currently enables:

- `pl011`
- `clock`
- `gtimer`
- `sp805`
- `qemu-sysinfo`
- `system-info`
- `qemu-bridge`
- `timer`
- `transport`
- `scmi`
- `cmn-cyprus`

Key points:

- PL011 is used as the SCP console backend
- GTimer provides the framework timestamp source
- `qemu-bridge` is the transport driver below `transport`
- `scmi` serves TF-A SCMI requests over the shared mailbox
- `cmn-cyprus` initializes against the emulated CMN configuration space

## CMN Model

The repository contains a shared QEMU device:

- device type: `arm-cmn-cfg`
- file: `qemu/hw/misc/arm-cmn-cfg.c`

Current properties:

- one shared 1GB configuration aperture
- AP view base: `0x140000000`
- SCP view base: `0x60000000`
- shared host backing file:
  - `/tmp/qemu_virt_soc.arm_cmn_cfg.shm`

Current scope:

- only configuration-space topology and register storage are modeled
- mesh data is seeded to match the current Cyprus-like 3x3 topology used by
  `cmn-cyprus`
- functional CMN datapath behavior is not implemented

## SCMI Path

The SCMI path currently exercised is:

```text
TF-A BL31
-> AP-side scmi-mailbox-bridge
-> host socket/shared-memory bridge
-> SCP-side qemu-bridge
-> transport
-> scmi
```

Verified today:

- TF-A SCMI BASE requests reach SCP-firmware
- SCP-firmware logs received BASE messages
- TF-A receives valid SCMI BASE responses

## Build

Top-level entrypoints are in [Makefile](/mnt/linux-work/qemu_virt_soc/Makefile).

### Build QEMU

```bash
cd qemu
mkdir -p build
cd build
../configure --target-list=aarch64-softmmu,arm-softmmu
ninja qemu-system-aarch64 qemu-system-arm
```

### Build AP baremetal

```bash
make ap
```

### Build TF-A

```bash
make tfa
```

### Build SCP-firmware

```bash
make scp
```

Notes:

- top-level SCP build defaults to `SCP_LOG_LEVEL=INFO`
- `qemu_virt_m7` disables framework log buffering so dense `cmn-cyprus` logs
  are not folded into `[FWK] ... and N more messages...`

## Run

### Run SCP only

```bash
make run-scp
```

### Run AP baremetal directly

```bash
make run-ap-baremetal
```

### Run AP through TF-A

```bash
make run-ap
```

### Run the integrated AP/SCP demo

```bash
make run-demo
```

The run targets open `xterm` windows and stream per-side logs from files:

- SCP log:
  - `build/scp/qemu_virt_m7/qemu.log`
- AP TF-A log:
  - `build/ap/hello_aarch64/tf_a.log`
- demo logs:
  - `build/demo/scp.log`
  - `build/demo/ap.log`

## Expected Demo Output

### SCP side

Typical SCP-side output includes:

```text
[CMN_CYPRUS] Configuring CMN...
[CMN_CYPRUS] CMN Discovery complete
[CMN_CYPRUS] HN-F SAM setup complete
[CMN_CYPRUS] RNSAM setup complete
[FWK] Module initialization complete!
[SCMI RX] AP: type=0 proto=0x10 msg=0x0 token=0
```

### AP side

Typical AP-side output includes:

```text
INFO:    QEMU SCMI: BASE version 0x20000
INFO:    QEMU SCMI: protocols=0 agents=1
ap_hello_aarch64: booting on QEMU virt
ap_hello_aarch64: dumping non-zero CMN registers
ap_hello_aarch64: CMN[0x0000000000000000] = 0x0000000000000002
```

At the moment, AP dumps the non-zero CMN registers after SCP has already
configured the CMN model.

## Development Notes

- QEMU changes live in the `qemu/` submodule
- SCP firmware changes live in the `SCP-firmware/` submodule
- TF-A changes live in the `tf-a/` submodule
- top-level integration, build/run flow, and documentation live in this repo

When changing submodules:

1. commit inside the submodule
2. push the submodule
3. commit the updated submodule pointer in the top-level repository

## Current Limitations

- CMN is a configuration-space model only; no coherent datapath behavior yet
- secure MHU windows are reserved but not fully modeled as real Arm MHU IP
- AP-side software is still a minimal baremetal dump client, not a full OS
- SCP-side SCMI implementation currently validates the BASE path; more
  protocols can be added later
