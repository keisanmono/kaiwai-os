
    .section .text.boot
    .globl _start

# ==========================================
# 1. Machine Mode: Initialization
# ==========================================

_start:
    # Set MPP = 01 (Supervisor mode)
    li      t0, 0x1800
    csrc    mstatus, t0
    li      t0, 0x0800
    csrs    mstatus, t0

    # Set Supervisor mode entry
    la      t0, supervisor_entry
    csrw    mepc, t0

    # Configure PMP permissions
    li      t0, -1
    csrw    pmpaddr0, t0

    # TOR mode with R/W/X permissions
    li      t0, 0x0f
    csrw    pmpcfg0, t0

    # Delegate U-mode ecall to S-mode
    li      t0, 0x100
    csrw    medeleg, t0

    # Enter Supervisor mode
    mret


# ==========================================
# 2. Supervisor Mode: Initialization
# ==========================================

supervisor_entry:
    # Configure supervisor trap entry
    la      t0, supervisor_trap
    csrw    stvec, t0

    # Set SPP = 0 (User mode)
    li      t0, 0x100
    csrc    sstatus, t0

    # Set User mode entry
    la      t0, user_entry
    csrw    sepc, t0

    # Initialize kernel stack
    la      t0, kernel_stack_top
    csrw    sscratch, t0

    # Initialize user stack
    la      sp, user_stack_top

    # Enter User mode
    sret


# ==========================================
# 3. User Mode: Application
# ==========================================

user_entry:
    # Load message address
    la      t1, message

print_loop:
    # Read next character
    lbu     t2, 0(t1)
    beqz    t2, done

    # Syscall 1: putchar
    mv      a0, t2
    li      a7, 1
    ecall

    # Continue printing
    addi    t1, t1, 1
    j       print_loop

done:
    # Print an exclamation mark
    li      a7, 1
    li      a0, 33
    ecall

user_halt:
    j       user_halt


# ==========================================
# 4. Supervisor Mode: Trap Handler
# ==========================================

    .balign 4

supervisor_trap:
    # Switch from user stack to kernel stack
    csrrw   sp, sscratch, sp

    # Allocate 32-byte trap frame
    addi    sp, sp, -32

    # Save user registers
    sd      t0, 0(sp)
    sd      ra, 8(sp)
    sd      a0, 16(sp)
    sd      a1, 24(sp)

    # Check trap cause
    # scause = 8 means U-mode ecall
    csrr    t0, scause
    xori    t0, t0, 8
    bnez    t0, trap_unhandled

    # Dispatch syscall number
    # a7 = syscall number
    # a0 = first argument
    li      t0, 1
    bne     a7, t0, trap_return

    # Syscall 1: putchar(a0)
    li      t0, 0x10000000
    sb      a0, 0(t0)

trap_return:
    # Skip the 4-byte ecall instruction
    csrr    t0, sepc
    addi    t0, t0, 4
    csrw    sepc, t0

    # Restore saved user registers
    ld      a1, 24(sp)
    ld      a0, 16(sp)
    ld      ra, 8(sp)
    ld      t0, 0(sp)

    # Release trap frame
    addi    sp, sp, 32

    # Restore user stack pointer
    csrrw   sp, sscratch, sp

    # Return to User mode
    sret


trap_unhandled:
    # Stop on unexpected exceptions
    j       trap_unhandled


# ==========================================
# 5. Read-only Data
# ==========================================

    .section .rodata

message:
    .asciz "kaiwai-os bare metal\nName: Wang Yunyu\nStudent ID: 24281239\n"


# ==========================================
# 6. Stack Memory
# ==========================================

    .section .bss
    .balign 16

# Kernel stack: 4 KiB
kernel_stack:
    .skip 4096
kernel_stack_top:

# User stack: 4 KiB
    .balign 16
user_stack:
    .skip 4096
user_stack_top:
