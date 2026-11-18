#ifndef KERNEL_H
#define KERNEL_H

typedef unsigned long u64;

/*
 * 多任务陷入帧（272 字节储物柜）：
 * 相比单任务的 256 字节帧，多出最后 16 字节用于保存 sepc 与 sstatus。
 * 因为多进程轮流执行时，每个打工人挂起都必须记住自己上次停在哪条指令（sepc）以及特权状态（sstatus），
 * 下次调度回来时才能从原位置继续运行。
 *
 * TODO: 在这里定义 struct trap_frame、enum process_state 与进程控制块 struct process。
 */
/* x[0] is unused; x[n] holds architectural register xn. */
struct trap_frame {
    u64 x[32];    /* 32 个通用寄存器槽位（256 字节，x[2] 存用户栈指针 sp） */
    u64 sepc;     /* 挂起时的程序计数器（下次恢复后的执行地址） */
    u64 sstatus;  /* 挂起时的特权级与中断开关状态 */
};

/* 员工状态：排队待命 / 正在运行 / 已退出下班 */
enum process_state { READY, RUNNING, EXITED };

/* 进程控制块 PCB（员工档案）：记录工号、状态、专属储物柜指针以及独立双栈顶 */
struct process {
    unsigned int pid;             /* 工号（alpha=1, beta=2） */
    const char *name;             /* 员工名称 */
    enum process_state state;     /* 当前状态 */
    /* All suspended user registers and privilege-return state live here. */
    struct trap_frame *context;   /* 指向该员工内核栈内的 272 字节陷入帧 */
    void *user_stack_top;         /* U 态用户办公桌栈顶（4 KiB） */
    void *kernel_stack_top;       /* S 态内核办公桌栈顶（4 KiB） */
};

#endif
