    .section .text.boot
    .globl _start
_start:
    # Only hart 0 initializes shared state. This experiment uses one hart.
    csrr    t0, mhartid
    bnez    t0, .Lpark
    la      sp, boot_stack_top
    la      t0, __bss_start
    la      t1, __bss_end
.Lclear_bss:
    bgeu    t0, t1, .Lbss_done
    sb      zero, 0(t0)
    addi    t0, t0, 1
    j       .Lclear_bss
.Lbss_done:
    # Full physical access for S/U mode; no virtual memory in this lab.
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, 0x0f
    csrw    pmpcfg0, t0
    # Delegate U-mode ecalls and other synchronous exceptions to S-mode.
    li      t0, 0xb1ff
    csrw    medeleg, t0
    la      t0, supervisor_entry
    csrw    mepc, t0
    li      t0, 0x1800
    csrc    mstatus, t0
    li      t0, 0x800
    csrs    mstatus, t0
    mret
.Lpark:
    wfi
    j       .Lpark

supervisor_entry:
    la      t0, trap_entry
    csrw    stvec, t0
    csrw    sscratch, zero
    call    kernel_main
.Lhalt:
    wfi
    j       .Lhalt

    .align 2
trap_entry:
    # U-mode has its kernel stack top in sscratch; S-mode keeps it zero.
    csrrw   sp, sscratch, sp
    beqz    sp, .Lkernel_trap
    addi    sp, sp, -272
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
    csrr    t0, sscratch
    sd      t0, 16(sp)
    csrw    sscratch, zero
    csrr    t0, sepc
    sd      t0, 256(sp)
    csrr    t0, sstatus
    sd      t0, 264(sp)
    mv      a0, sp
    csrr    a1, scause
    csrr    a2, stval
    call    handle_trap
    # The scheduler returns the frame belonging to the selected process.
    mv      sp, a0
    j       restore_user
.Lkernel_trap:
    csrrw   sp, sscratch, sp
    csrw    sscratch, zero
    csrr    a0, scause
    csrr    a1, sepc
    csrr    a2, stval
    call    kernel_trap
    j       .Lhalt

    .globl enter_user
enter_user:
    mv      sp, a0
restore_user:
    ld      t0, 256(sp)
    csrw    sepc, t0
    ld      t0, 264(sp)
    csrw    sstatus, t0
    # sscratch must again contain the selected process's kernel stack top.
    addi    t0, sp, 272
    csrw    sscratch, t0
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
    ld      t0, 40(sp)
    ld      sp, 16(sp)
    sret

    .section .bss
    .balign 16
boot_stack:
    .skip 4096
boot_stack_top:
