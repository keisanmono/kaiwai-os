#include "kernel.h"

#define PROCESS_COUNT 2
#define STACK_SIZE 4096
#define UART ((volatile unsigned char *)0x10000000UL)
#define TEST_DEVICE (*(volatile unsigned int *)0x100000UL)
#define SYS_PUTS 2
#define SYS_YIELD 3
#define SYS_EXIT 4

extern void user_alpha(void);
extern void user_beta(void);
extern void enter_user(struct trap_frame *) __attribute__((noreturn));

static unsigned char user_stacks[PROCESS_COUNT][STACK_SIZE] __attribute__((aligned(16)));
static unsigned char kernel_stacks[PROCESS_COUNT][STACK_SIZE] __attribute__((aligned(16)));
static struct process processes[PROCESS_COUNT];
static unsigned int current;
static int failed;

static void putchar_raw(char c)
{
    while (!(UART[5] & 0x20)) { }
    UART[0] = (unsigned char)c;
}

static void puts_raw(const char *s)
{
    while (*s) putchar_raw(*s++);
}

static void hex64(u64 value)
{
    static const char digits[] = "0123456789abcdef";
    puts_raw("0x");
    for (int shift = 60; shift >= 0; shift -= 4)
        putchar_raw(digits[(value >> shift) & 15]);
}

static void finish(int error) __attribute__((noreturn));
static void finish(int error)
{
    /* QEMU virt's SiFive test device: 0x5555 succeeds, 0x3333 fails. */
    TEST_DEVICE = error ? 0x13333 : 0x5555;
    for (;;) __asm__ volatile ("wfi");
}

void kernel_trap(u64 cause, u64 pc, u64 value) __attribute__((noreturn));
void kernel_trap(u64 cause, u64 pc, u64 value)
{
    puts_raw("[kernel] fatal trap: scause="); hex64(cause);
    puts_raw(" sepc="); hex64(pc);
    puts_raw(" stval="); hex64(value); puts_raw("\n");
    finish(1);
}

static void init_process(unsigned int i, const char *name, void (*entry)(void))
{
    struct process *p = &processes[i];
    p->pid = i + 1;
    p->name = name;
    p->state = READY;
    p->user_stack_top = &user_stacks[i][STACK_SIZE];
    p->kernel_stack_top = &kernel_stacks[i][STACK_SIZE];
    p->context = (struct trap_frame *)((char *)p->kernel_stack_top - sizeof(struct trap_frame));
    /* BSS clearing initializes the rest of the first context to zero. */
    p->context->x[2] = (u64)p->user_stack_top;
    p->context->sepc = (u64)entry;
    p->context->sstatus = 0; /* SPP=0, return to U-mode; interrupts disabled. */
}

static void describe(const char *action, const struct process *p)
{
    puts_raw("[sched] "); puts_raw(action); puts_raw(" pid=");
    putchar_raw((char)('0' + p->pid));
    puts_raw(" ("); puts_raw(p->name); puts_raw(")\n");
}

static struct trap_frame *schedule(void)
{
    /* Cooperative round robin: examine each process once, starting after current. */
    for (unsigned int n = 1; n <= PROCESS_COUNT; ++n) {
        unsigned int next = (current + n) % PROCESS_COUNT;
        if (processes[next].state == READY) {
            current = next;
            processes[next].state = RUNNING;
            describe("run", &processes[next]);
            return processes[next].context;
        }
    }
    puts_raw(failed ? "[kernel] all processes exited; FAIL\n" :
                       "[kernel] all processes exited; PASS\n");
    finish(failed);
}

struct trap_frame *handle_trap(struct trap_frame *frame, u64 cause, u64 value)
{
    struct process *p = &processes[current];
    p->context = frame;
    if (cause != 8) {
        puts_raw("[user] fatal trap: scause="); hex64(cause);
        puts_raw(" sepc="); hex64(frame->sepc);
        puts_raw(" stval="); hex64(value); puts_raw("\n");
        finish(1);
    }
    frame->sepc += 4; /* ecall is always 4 bytes. */
    switch (frame->x[17]) {
    case SYS_PUTS:
        /* This teaching kernel trusts its built-in user programs and pointers. */
        puts_raw((const char *)frame->x[10]);
        frame->x[10] = 0;
        return frame;
    case SYS_YIELD:
        frame->x[10] = 0;
        p->state = READY;
        describe("yield", p);
        return schedule();
    case SYS_EXIT:
        if (frame->x[10] != 0) failed = 1;
        p->state = EXITED;
        describe(frame->x[10] ? "exit FAIL" : "exit", p);
        return schedule();
    default:
        frame->x[10] = (u64)-1;
        return frame;
    }
}

void kernel_main(void)
{
    puts_raw("kaiwai-os lab 0-4 | Wang Yunyu | 24281239\n");
    puts_raw("[kernel] cooperative round robin, U-mode processes\n");
    init_process(0, "alpha", user_alpha);
    init_process(1, "beta", user_beta);
    current = 0;
    processes[0].state = RUNNING;
    describe("run", &processes[0]);
    enter_user(processes[0].context);
}
