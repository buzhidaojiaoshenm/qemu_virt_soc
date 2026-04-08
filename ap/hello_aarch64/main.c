/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>

#define QEMU_VIRT_UART0_BASE UINT64_C(0x09000000)
#define PL011_UARTDR UINT64_C(0x000)
#define PL011_UARTIBRD UINT64_C(0x024)
#define PL011_UARTFBRD UINT64_C(0x028)
#define PL011_UARTLCR_H UINT64_C(0x02c)
#define PL011_UARTCR UINT64_C(0x030)
#define PL011_UARTFR UINT64_C(0x018)

#define PL011_UARTFR_TXFF UINT32_C(1 << 5)
#define PL011_UARTLCR_H_FEN UINT32_C(1 << 4)
#define PL011_UARTLCR_H_WLEN_8 UINT32_C(3 << 5)
#define PL011_UARTCR_UARTEN UINT32_C(1 << 0)
#define PL011_UARTCR_TXE UINT32_C(1 << 8)

static inline void mmio_write32(uint64_t addr, uint32_t value)
{
    *(volatile uint32_t *)addr = value;
}

static inline uint32_t mmio_read32(uint64_t addr)
{
    return *(volatile uint32_t *)addr;
}

static void uart_init(void)
{
    mmio_write32(QEMU_VIRT_UART0_BASE + PL011_UARTCR, 0);
    mmio_write32(QEMU_VIRT_UART0_BASE + PL011_UARTIBRD, 13);
    mmio_write32(QEMU_VIRT_UART0_BASE + PL011_UARTFBRD, 1);
    mmio_write32(
        QEMU_VIRT_UART0_BASE + PL011_UARTLCR_H,
        PL011_UARTLCR_H_FEN | PL011_UARTLCR_H_WLEN_8);
    mmio_write32(
        QEMU_VIRT_UART0_BASE + PL011_UARTCR,
        PL011_UARTCR_UARTEN | PL011_UARTCR_TXE);
}

static void uart_putc(char ch)
{
    while ((mmio_read32(QEMU_VIRT_UART0_BASE + PL011_UARTFR) &
            PL011_UARTFR_TXFF) != 0U) {
    }

    mmio_write32(QEMU_VIRT_UART0_BASE + PL011_UARTDR, (uint32_t)ch);
}

static void uart_puts(const char *str)
{
    while (*str != '\0') {
        if (*str == '\n') {
            uart_putc('\r');
        }

        uart_putc(*str++);
    }
}

void main(void)
{
    uart_init();
    uart_puts("ap_hello_aarch64: booting on QEMU virt\n");

    for (;;) {
        __asm__ volatile("wfe");
    }
}
