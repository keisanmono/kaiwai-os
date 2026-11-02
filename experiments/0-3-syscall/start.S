
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

    # Set Supervisor entry
    la      t0, supervisor_entry
    csrw    mepc, t0

    # Configure PMP permissions
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, 0x0f
    csrw    pmpcfg0, t0

    # Delegate exceptions to S-mode
    # Bit 2: Illegal instruction
    # Bit 8: U-mode ecall
    li      t0, 0x104
    csrw    medeleg, t0

    # Delegate supervisor interrupts
    # Bit 1: Supervisor software interrupt
    # Bit 5: Supervisor timer interrupt
    # Bit 9: Supervisor external interrupt
    li      t0, 0x222
    csrs    mideleg, t0

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
    # Test preservation of t3
    li      t3, 0x55aa

    # Syscall 2: puts(message)
    la      a0, message
    li      a7, 2
    ecall

    # Save returned string length
    mv      s0, a0

    # Syscall 1: putchar('!')
    li      a0, 33
    li      a7, 1
    ecall

    # Syscall 99: unsupported
    li      a7, 99
    ecall

    # Save error return value
    mv      s1, a0

user_halt:
    j       user_halt


# ==========================================
# 4. Supervisor Mode: Trap Entry
# ==========================================

    .balign 4

supervisor_trap:
    # Exchange user SP with kernel SP
    csrrw   sp, sscratch, sp

    # Detect unexpected kernel trap
    beqz    sp, supervisor_kernel_trap

    # Allocate 256-byte trap frame
    addi    sp, sp, -256

    # Save integer registers
    sd      ra, 8(sp)
    sd      gp, 24(sp)
    sd      tp, 32(sp)
    sd      t0, 40(sp)
    sd      t1, 48(sp)
    sd      t2, 56(sp)
    sd      s0, 64(sp)
    sd      s1, 72(sp)
    sd      a0, 80(sp)
    sd      a1, 88(sp)
    sd      a2, 96(sp)
    sd      a3, 104(sp)
    sd      a4, 112(sp)
    sd      a5, 120(sp)
    sd      a6, 128(sp)
    sd      a7, 136(sp)
    sd      s2, 144(sp)
    sd      s3, 152(sp)
    sd      s4, 160(sp)
    sd      s5, 168(sp)
    sd      s6, 176(sp)
    sd      s7, 184(sp)
    sd      s8, 192(sp)
    sd      s9, 200(sp)
    sd      s10, 208(sp)
    sd      s11, 216(sp)
    sd      t3, 224(sp)
    sd      t4, 232(sp)
    sd      t5, 240(sp)
    sd      t6, 248(sp)

    # Save original user SP
    csrr    t0, sscratch
    sd      t0, 16(sp)

    # Mark kernel execution
    csrw    sscratch, zero

    # Check U-mode ecall (scause = 8)
    csrr    t0, scause
    li      t1, 8
    bne     t0, t1, user_trap_unhandled

    # Dispatch syscall number
    li      t0, 1
    beq     a7, t0, handle_putchar

    li      t0, 2
    beq     a7, t0, handle_puts

    # Unknown syscall returns -1
    li      a0, -1
    j       syscall_done


# ==========================================
# 5. System Call Dispatch
# ==========================================

handle_putchar:
    call    sys_putchar
    li      a0, 1
    j       syscall_done

handle_puts:
    call    sys_puts
    j       syscall_done


# ==========================================
# 6. System Call Return
# ==========================================

syscall_done:
    # Save syscall return value
    sd      a0, 80(sp)

    # Skip the 4-byte ecall instruction
    csrr    t0, sepc
    addi    t0, t0, 4
    csrw    sepc, t0

    # Restore integer registers
    ld      ra, 8(sp)
    ld      gp, 24(sp)
    ld      tp, 32(sp)
    ld      t1, 48(sp)
    ld      t2, 56(sp)
    ld      s0, 64(sp)
    ld      s1, 72(sp)
    ld      a0, 80(sp)
    ld      a1, 88(sp)
    ld      a2, 96(sp)
    ld      a3, 104(sp)
    ld      a4, 112(sp)
    ld      a5, 120(sp)
    ld      a6, 128(sp)
    ld      a7, 136(sp)
    ld      s2, 144(sp)
    ld      s3, 152(sp)
    ld      s4, 160(sp)
    ld      s5, 168(sp)
    ld      s6, 176(sp)
    ld      s7, 184(sp)
    ld      s8, 192(sp)
    ld      s9, 200(sp)
    ld      s10, 208(sp)
    ld      s11, 216(sp)
    ld      t3, 224(sp)
    ld      t4, 232(sp)
    ld      t5, 240(sp)
    ld      t6, 248(sp)

    # Prepare user SP restoration
    ld      t0, 16(sp)
    csrw    sscratch, t0

    # Restore original user t0
    ld      t0, 40(sp)

    # Release kernel trap frame
    addi    sp, sp, 256

    # Exchange stack pointers back
    csrrw   sp, sscratch, sp

    # Return to User mode
    sret


# ==========================================
# 7. Unexpected Trap Diagnostics
# ==========================================

user_trap_unhandled:
    # User-mode trap: kernel stack active
    la      a0, diag_user_header
    j       trap_diagnostic

supervisor_kernel_trap:
    # Restore kernel SP after failed exchange
    csrrw   sp, sscratch, sp

    # Report kernel trap
    la      a0, diag_kernel_header
    j       trap_diagnostic

trap_diagnostic:
    # Print diagnostic header
    call    kernel_puts_raw

    # Print scause
    la      a0, diag_scause
    call    kernel_puts_raw
    csrr    a0, scause
    call    kernel_print_hex64

    # Print sepc
    la      a0, diag_sepc
    call    kernel_puts_raw
    csrr    a0, sepc
    call    kernel_print_hex64

    # Print stval
    la      a0, diag_stval
    call    kernel_puts_raw
    csrr    a0, stval
    call    kernel_print_hex64

    # Finish with newline
    la      a0, diag_newline
    call    kernel_puts_raw

trap_halt:
    # Stop after reporting a fatal trap
    j       trap_halt


# ==========================================
# 8. Kernel System Calls
# ==========================================

# Syscall 1: putchar
# Input: a0 = character

sys_putchar:
    li      t3, 0x10000000
    sb      a0, 0(t3)
    ret


# Syscall 2: puts
# Input: a0 = string address
# Output: a0 = character count

sys_puts:
    # Preserve function context
    addi    sp, sp, -32
    sd      ra, 24(sp)
    sd      s2, 16(sp)
    sd      s3, 8(sp)

    # s2 = string pointer
    # s3 = character count
    mv      s2, a0
    li      s3, 0

sys_puts_loop:
    # Load next character
    lbu     a0, 0(s2)
    beqz    a0, sys_puts_done

    # Print current character
    call    sys_putchar

    # Advance pointer and count
    addi    s2, s2, 1
    addi    s3, s3, 1
    j       sys_puts_loop

sys_puts_done:
    # Return character count
    mv      a0, s3

    # Restore function context
    ld      s3, 8(sp)
    ld      s2, 16(sp)
    ld      ra, 24(sp)
    addi    sp, sp, 32
    ret


# ==========================================
# 9. Raw Kernel UART Diagnostics
# ==========================================

# Print null-terminated string directly
# Input: a0 = string address

kernel_puts_raw:
    li      t0, 0x10000000

raw_puts_loop:
    lbu     t1, 0(a0)
    beqz    t1, raw_puts_done

    sb      t1, 0(t0)
    addi    a0, a0, 1
    j       raw_puts_loop

raw_puts_done:
    ret


# Print a 64-bit hexadecimal value
# Input: a0 = value

kernel_print_hex64:
    li      t0, 0x10000000

    # Print "0x"
    li      t4, 48
    sb      t4, 0(t0)
    li      t4, 120
    sb      t4, 0(t0)

    # Print 16 hexadecimal digits
    mv      t1, a0
    li      t2, 16

hex64_loop:
    # Extract highest four bits
    srli    t3, t1, 60

    # Convert nibble into ASCII
    li      t4, 10
    bltu    t3, t4, hex64_digit

    # Convert 10-15 into a-f
    addi    t3, t3, 87
    j       hex64_emit

hex64_digit:
    # Convert 0-9 into ASCII
    addi    t3, t3, 48

hex64_emit:
    sb      t3, 0(t0)

    # Move next nibble into position
    slli    t1, t1, 4
    addi    t2, t2, -1
    bnez    t2, hex64_loop

    ret


# ==========================================
# 10. Read-only Data
# ==========================================

    .section .rodata

message:
    .asciz "kaiwai-os bare metal\nName: Wang Yunyu\nStudent ID: 24281239\n"

diag_user_header:
    .asciz "\n[kaiwai-os] TRAP DETECTED\n"

diag_kernel_header:
    .asciz "\n[kaiwai-os] KERNEL TRAP DETECTED\n"

diag_scause:
    .asciz "scause = "

diag_sepc:
    .asciz "\nsepc   = "

diag_stval:
    .asciz "\nstval  = "

diag_newline:
    .asciz "\n"


# ==========================================
# 11. Stack Memory
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
