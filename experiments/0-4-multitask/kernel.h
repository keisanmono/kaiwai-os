#ifndef KERNEL_H
#define KERNEL_H

typedef unsigned long u64;

/* x[0] is unused; x[n] holds architectural register xn. */
struct trap_frame {
    u64 x[32];
    u64 sepc;
    u64 sstatus;
};

enum process_state { READY, RUNNING, EXITED };

struct process {
    unsigned int pid;
    const char *name;
    enum process_state state;
    /* All suspended user registers and privilege-return state live here. */
    struct trap_frame *context;
    void *user_stack_top;
    void *kernel_stack_top;
};

#endif
