#include "kernel.h"

/*
 * S 态部门经理总管代码（kernel.c）：
 * 在这里用 C 语言管理 2 个 U 态打工人（alpha 与 beta），包括：
 * 独立双栈分配、进程初始化、礼让式（协作式）轮转调度与系统调用分发。
 */

#define PROCESS_COUNT 2
#define STACK_SIZE 4096
#define UART ((volatile unsigned char *)0x10000000UL)
#define TEST_DEVICE (*(volatile unsigned int *)0x100000UL)
/* 系统调用号：2=puts, 3=yield, 4=exit（未实现实验 3 的 1 号 putchar） */
#define SYS_PUTS 2
#define SYS_YIELD 3
#define SYS_EXIT 4

extern void user_alpha(void);
extern void user_beta(void);
extern void enter_user(struct trap_frame *) __attribute__((noreturn));

/* 两个员工各自独立的 4 KiB 用户栈与 4 KiB 内核栈，互不干扰 */
static unsigned char user_stacks[PROCESS_COUNT][STACK_SIZE] __attribute__((aligned(16)));
static unsigned char kernel_stacks[PROCESS_COUNT][STACK_SIZE] __attribute__((aligned(16)));
static struct process processes[PROCESS_COUNT];
static unsigned int current;  /* 当前占有工位的进程下标（0=alpha, 1=beta） */
static int failed;            /* 记录是否有进程以非零退出码结束 */

/* 串口输出单字符：轮询 UART[5] 发送空标志位后写入 UART[0] */
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

/* 向 QEMU virt 的 SiFive 测试设备写入退出状态（0x5555 成功，0x13333 失败） */
static void finish(int error) __attribute__((noreturn));
static void finish(int error)
{
    /* QEMU virt's SiFive test device: 0x5555 succeeds, 0x3333 fails. */
    TEST_DEVICE = error ? 0x13333 : 0x5555;
    for (;;) __asm__ volatile ("wfi");
}

/*
 * 内核态致命异常诊断函数（对应 start.S 的 .Lkernel_trap）：
 * 打印 scause、sepc、stval 后调用 finish(1) 结束运行。
 *
 * TODO: 在这里实现内核异常信息输出与错误退出。
 */
void kernel_trap(u64 cause, u64 pc, u64 value) __attribute__((noreturn));
void kernel_trap(u64 cause, u64 pc, u64 value)
{
    puts_raw("[kernel] fatal trap: scause="); hex64(cause);
    puts_raw(" sepc="); hex64(pc);
    puts_raw(" stval="); hex64(value); puts_raw("\n");
    finish(1);
}

/*
 * 办理员工入职：填写进程控制块，并在该进程内核栈顶下方预留 272 字节初始陷入帧；
 * 由于启动汇编已将 BSS 清零，只需设定用户栈顶 x[2]、入口地址 sepc 与 sstatus=0（U 态、关中断）。
 *
 * TODO: 在这里完成进程初始上下文构建。
 */
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

/*
 * 协作式（礼让式）轮转调度器：
 * 从当前员工下一位起绕圈扫描进程表，选中第一个处于 READY 状态的员工并返回其陷入帧指针；
 * 若所有员工都已 EXITED 下班，则输出 PASS/FAIL 并通过 finish() 自动关闭 QEMU。
 *
 * TODO: 在这里实现循环扫描调度逻辑。
 */
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

/*
 * 陷入总处理函数：
 * 先保存当前进程的 context 指针，检查是否为 U 态 ecall（cause == 8），
 * 随后将 sepc 加 4 跳过 ecall 指令，并按系统调用号 a7（x[17]）分发：
 *   SYS_PUTS (2): 打印字符串，返回 0，不切换任务；
 *   SYS_YIELD (3): 将当前进程置回 READY 并调用 schedule() 切到下一任务；
 *   SYS_EXIT (4): 记录退出码，设为 EXITED 并调用 schedule()。
 *
 * TODO: 在这里实现系统调用分发与任务切换逻辑。
 */
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

/*
 * C 内核入口（部门经理正式上岗）：
 * 打印启动横幅，办理 alpha 和 beta 两个打工人的入职初始化，
 * 将 0 号员工 alpha 设为 RUNNING 并调用 enter_user() 送入 U 态开始执行。
 *
 * TODO: 在这里完成双进程初始化并启动首个用户任务。
 */
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
