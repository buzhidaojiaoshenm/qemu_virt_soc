/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>

#define QEMU_VIRT_UART0_BASE UINT64_C(0x09000000)
#define QEMU_VIRT_CMN_CFG_BASE UINT64_C(0x140000000)
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

static inline uint64_t mmio_read64(uint64_t addr)
{
    uint64_t low = mmio_read32(addr);
    uint64_t high = mmio_read32(addr + 4);

    return low | (high << 32);
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

static void uart_puthex4(uint32_t value)
{
    value &= 0xfU;
    uart_putc((value < 10U) ? ('0' + (char)value) : ('a' + (char)(value - 10U)));
}

static void uart_puthex32(uint32_t value)
{
    int shift;

    for (shift = 28; shift >= 0; shift -= 4) {
        uart_puthex4(value >> shift);
    }
}

static void uart_puthex64(uint64_t value)
{
    uart_puthex32((uint32_t)(value >> 32));
    uart_puthex32((uint32_t)value);
}

void main(void)
{
    uint64_t cmn_node_info;
    uint64_t cmn_child_info;
    uint64_t cmn_info_global;

    uart_init();
    uart_puts("ap_hello_aarch64: booting on QEMU virt\n");

    cmn_node_info = mmio_read64(QEMU_VIRT_CMN_CFG_BASE + 0x0000);
    cmn_child_info = mmio_read64(QEMU_VIRT_CMN_CFG_BASE + 0x0080);
    cmn_info_global = mmio_read64(QEMU_VIRT_CMN_CFG_BASE + 0x0900);

    uart_puts("ap_hello_aarch64: CMN node_info=0x");
    uart_puthex64(cmn_node_info);
    uart_puts("\n");
    uart_puts("ap_hello_aarch64: CMN child_info=0x");
    uart_puthex64(cmn_child_info);
    uart_puts("\n");
    uart_puts("ap_hello_aarch64: CMN info_global=0x");
    uart_puthex64(cmn_info_global);
    uart_puts("\n");

    for (;;) {
        __asm__ volatile("wfe");
    }
}
