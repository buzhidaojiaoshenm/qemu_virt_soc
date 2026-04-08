/* SPDX-License-Identifier: BSD-3-Clause */

    .section .text.boot, "ax"
    .align  7
    .global _start

_start:
    mrs     x0, mpidr_el1
    and     x0, x0, #0xff
    cbz     x0, 1f

0:
    wfe
    b       0b

1:
    ldr     x0, =__stack_top
    mov     sp, x0

    bl      main

2:
    wfe
    b       2b
