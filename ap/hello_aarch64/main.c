/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>

#define QEMU_VIRT_UART0_BASE UINT64_C(0x09000000)
#define QEMU_VIRT_SCMI_BRIDGE_BASE UINT64_C(0x090d0000)
#define QEMU_VIRT_SCMI_SHM_BASE UINT64_C(0x090e0000)
#define QEMU_VIRT_CMN_CFG_BASE UINT64_C(0x140000000)
#define QEMU_VIRT_CMN_TRACE_BASE UINT64_C(0x180000000)
#define QEMU_VIRT_CMN_TRACE_REG_MAGIC UINT64_C(0x000)
#define QEMU_VIRT_CMN_TRACE_REG_PRODUCER UINT64_C(0x008)
#define QEMU_VIRT_CMN_TRACE_REG_CONSUMER UINT64_C(0x010)
#define QEMU_VIRT_CMN_TRACE_REG_CAPACITY UINT64_C(0x018)
#define QEMU_VIRT_CMN_TRACE_ENTRY_BASE UINT64_C(0x100)
#define QEMU_VIRT_CMN_TRACE_ENTRY_STRIDE UINT64_C(0x20)
#define QEMU_VIRT_CMN_TRACE_MAGIC UINT64_C(0x434d4e5452414345)
#define QEMU_VIRT_CMN_TRACE_OP_READ UINT64_C(0x0)
#define QEMU_VIRT_CMN_TRACE_OP_WRITE UINT64_C(0x1)
#define QEMU_VIRT_SCMI_CMN_CTRL_PROTOCOL_ID UINT32_C(0x80)
#define QEMU_VIRT_SCMI_CMN_CTRL_MESSAGE_START_CMN_INIT UINT32_C(0x3)
#define QEMU_VIRT_SCMI_MESSAGE_TYPE_COMMAND UINT32_C(0x0)
#define QEMU_VIRT_SCMI_DOORBELL UINT64_C(0x008)
#define QEMU_VIRT_SCMI_IRQ_ACK UINT64_C(0x00c)
#define QEMU_VIRT_SCMI_STATUS UINT64_C(0x004)
#define QEMU_VIRT_SCMI_STATUS_IRQ_PENDING (UINT32_C(1) << 0)
#define QEMU_VIRT_SCMI_MAILBOX_STATUS_FREE (UINT32_C(1) << 0)
#define QEMU_VIRT_SCMI_MESSAGE_ID_POS 0U
#define QEMU_VIRT_SCMI_MESSAGE_TYPE_POS 8U
#define QEMU_VIRT_SCMI_PROTOCOL_ID_POS 10U
#define QEMU_VIRT_SCMI_TOKEN_POS 18U
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

struct qemu_scmi_mailbox {
    uint32_t reserved0;
    volatile uint32_t status;
    uint64_t reserved1;
    uint32_t flags;
    volatile uint32_t length;
    uint32_t message_header;
    uint32_t payload[0];
};

static inline void mmio_write32(uint64_t addr, uint32_t value)
{
    *(volatile uint32_t *)addr = value;
}

static inline uint32_t mmio_read32(uint64_t addr)
{
    return *(volatile uint32_t *)addr;
}

static inline void mmio_write64(uint64_t addr, uint64_t value)
{
    mmio_write32(addr, (uint32_t)value);
    mmio_write32(addr + 4, (uint32_t)(value >> 32));
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

static uint32_t scmi_message_header(
    uint32_t message_id,
    uint32_t message_type,
    uint32_t protocol_id,
    uint32_t token)
{
    return ((message_id << QEMU_VIRT_SCMI_MESSAGE_ID_POS) |
            (message_type << QEMU_VIRT_SCMI_MESSAGE_TYPE_POS) |
            (protocol_id << QEMU_VIRT_SCMI_PROTOCOL_ID_POS) |
            (token << QEMU_VIRT_SCMI_TOKEN_POS));
}

static void scmi_ack_irq_if_pending(void)
{
    if ((mmio_read32(QEMU_VIRT_SCMI_BRIDGE_BASE + QEMU_VIRT_SCMI_STATUS) &
         QEMU_VIRT_SCMI_STATUS_IRQ_PENDING) != 0U) {
        mmio_write32(QEMU_VIRT_SCMI_BRIDGE_BASE + QEMU_VIRT_SCMI_IRQ_ACK, 1);
    }
}

static void drain_cmn_trace_once(void)
{
    uint64_t producer;
    uint64_t consumer;
    uint64_t capacity;

    if (mmio_read64(QEMU_VIRT_CMN_TRACE_BASE + QEMU_VIRT_CMN_TRACE_REG_MAGIC) !=
        QEMU_VIRT_CMN_TRACE_MAGIC) {
        uart_puts("ap_hello_aarch64: CMN trace magic mismatch\n");
        return;
    }

    capacity = mmio_read64(QEMU_VIRT_CMN_TRACE_BASE +
                           QEMU_VIRT_CMN_TRACE_REG_CAPACITY);
    consumer = mmio_read64(QEMU_VIRT_CMN_TRACE_BASE +
                           QEMU_VIRT_CMN_TRACE_REG_CONSUMER);

    producer = mmio_read64(QEMU_VIRT_CMN_TRACE_BASE +
                           QEMU_VIRT_CMN_TRACE_REG_PRODUCER);
    if ((producer - consumer) > capacity) {
        consumer = producer - capacity;
        mmio_write64(QEMU_VIRT_CMN_TRACE_BASE +
                         QEMU_VIRT_CMN_TRACE_REG_CONSUMER,
                     consumer);
    }

    while (consumer != producer) {
        uint64_t index = consumer % capacity;
        uint64_t entry_base = QEMU_VIRT_CMN_TRACE_BASE +
            QEMU_VIRT_CMN_TRACE_ENTRY_BASE +
            (index * QEMU_VIRT_CMN_TRACE_ENTRY_STRIDE);
        uint64_t seq = mmio_read64(entry_base + 0x0);
        uint64_t info = mmio_read64(entry_base + 0x8);
        uint64_t addr = mmio_read64(entry_base + 0x10);
        uint64_t value = mmio_read64(entry_base + 0x18);
        uint64_t op = info & 0xffU;
        uint64_t size = (info >> 8) & 0xffU;

        uart_puts("ap_hello_aarch64: SCP CMN ");
        uart_puts((op == QEMU_VIRT_CMN_TRACE_OP_WRITE) ? "write" : "read");
        uart_puts(" seq=0x");
        uart_puthex64(seq);
        uart_puts(" size=0x");
        uart_puthex64(size);
        uart_puts(" addr=0x");
        uart_puthex64(addr);
        uart_puts(" value=0x");
        uart_puthex64(value);
        uart_puts("\n");

        consumer++;
        mmio_write64(QEMU_VIRT_CMN_TRACE_BASE +
                         QEMU_VIRT_CMN_TRACE_REG_CONSUMER,
                     consumer);
    }
}

static void cmn_trace_sync_to_head(void)
{
    uint64_t producer = mmio_read64(QEMU_VIRT_CMN_TRACE_BASE +
                                    QEMU_VIRT_CMN_TRACE_REG_PRODUCER);

    mmio_write64(QEMU_VIRT_CMN_TRACE_BASE +
                     QEMU_VIRT_CMN_TRACE_REG_CONSUMER,
                 producer);
}

static int scmi_start_cmn_init(void)
{
    volatile struct qemu_scmi_mailbox *mailbox =
        (volatile struct qemu_scmi_mailbox *)QEMU_VIRT_SCMI_SHM_BASE;

    while ((mailbox->status & QEMU_VIRT_SCMI_MAILBOX_STATUS_FREE) == 0U) {
        scmi_ack_irq_if_pending();
        drain_cmn_trace_once();
    }

    mailbox->reserved0 = 0;
    mailbox->reserved1 = 0;
    mailbox->flags = 0;
    mailbox->message_header = scmi_message_header(
        QEMU_VIRT_SCMI_CMN_CTRL_MESSAGE_START_CMN_INIT,
        QEMU_VIRT_SCMI_MESSAGE_TYPE_COMMAND,
        QEMU_VIRT_SCMI_CMN_CTRL_PROTOCOL_ID,
        1);
    mailbox->length = sizeof(mailbox->message_header);
    mailbox->status &= ~QEMU_VIRT_SCMI_MAILBOX_STATUS_FREE;

    mmio_write32(QEMU_VIRT_SCMI_BRIDGE_BASE + QEMU_VIRT_SCMI_DOORBELL, 1);

    while ((mailbox->status & QEMU_VIRT_SCMI_MAILBOX_STATUS_FREE) == 0U) {
        scmi_ack_irq_if_pending();
        drain_cmn_trace_once();
    }

    scmi_ack_irq_if_pending();
    return (int32_t)mailbox->payload[0];
}

static void poll_cmn_trace_forever(void)
{
    uart_puts("ap_hello_aarch64: polling SCP CMN trace\n");

    for (;;) {
        drain_cmn_trace_once();
        scmi_ack_irq_if_pending();
    }
}

void main(void)
{
    uint64_t cmn_node_info;
    uint64_t cmn_child_info;
    uint64_t cmn_info_global;
    int scmi_status;

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

    if (mmio_read64(QEMU_VIRT_CMN_TRACE_BASE + QEMU_VIRT_CMN_TRACE_REG_MAGIC) !=
        QEMU_VIRT_CMN_TRACE_MAGIC) {
        uart_puts("ap_hello_aarch64: CMN trace magic mismatch\n");
        for (;;) {
        }
    }

    cmn_trace_sync_to_head();
    uart_puts("ap_hello_aarch64: sending SCMI start-cmn-init\n");
    scmi_status = scmi_start_cmn_init();
    uart_puts("ap_hello_aarch64: SCMI start-cmn-init status=0x");
    uart_puthex32((uint32_t)scmi_status);
    uart_puts("\n");

    poll_cmn_trace_forever();
}
