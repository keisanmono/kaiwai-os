    .section .text.boot
    .globl _start
# 多任务启动、陷入保存与上下文切换汇编：
#   1. M 态大老板：仅放行 0 号核心、清零 BSS（开机大扫除）、配置 PMP 门禁与 medeleg 后切入 S 态；
#   2. S 态部门经理：挂好 stvec = trap_entry，随后调用 C 语言总管 kernel_main()；
#   3. 陷入与任务切换：trap_entry 将当前员工现场存进 272 字节储物柜，
#      根据 handle_trap() 返回的新储物柜指针把 sp 切换过去，再执行 restore_user 恢复并 sret。

_start:
    # 仅让 hart 0 执行初始化，其余核心进入 .Lpark 等待。
    csrr    t0, mhartid
    bnez    t0, .Lpark

    # 设置临时启动栈并清零 __bss_start ~ __bss_end，
    # 防止全局变量、进程数组与初始陷入帧残留脏数据。

    # TODO: 在这里填写启动栈设置与 BSS 清零循环。
    la      sp, boot_stack_top
    la      t0, __bss_start
    la      t1, __bss_end
.Lclear_bss:
    bgeu    t0, t1, .Lbss_done
    sb      zero, 0(t0)
    addi    t0, t0, 1
    j       .Lclear_bss
.Lbss_done:
    # 配置 PMP 全物理地址放行权限（门禁卡）与同步异常委派 medeleg = 0xb1ff，
    # 随后设置 MPP = 01 (S-mode) 与 mepc = supervisor_entry，执行 mret 进入 S 态。

    # TODO: 在这里填写 PMP、medeleg 配置及 mret 降权逻辑。
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, 0x0f
    csrw    pmpcfg0, t0
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
    # 配置 S 态陷入入口 trap_entry，清零 sscratch，并跳转到 C 内核入口 kernel_main。

    # TODO: 在这里填写 S 态入口初始化并调用 kernel_main。
    la      t0, trap_entry
    csrw    stvec, t0
    csrw    sscratch, zero
    call    kernel_main
.Lhalt:
    wfi
    j       .Lhalt

    .align 2
trap_entry:
    # 原子对调用户栈与当前员工内核栈（交换办公桌）；
    # 若换出 sp 为 0，说明内核态自身触发异常，转入 .Lkernel_trap 诊断。

    # TODO: 在这里填写栈指针交换与内核重入检测指令。
    csrrw   sp, sscratch, sp
    beqz    sp, .Lkernel_trap

    # 分配 272 字节储物柜（256B 通用寄存器 + sepc + sstatus）并保存当前员工完整现场，
    # 同时将 sscratch 清零标记正在内核态执行。

    # TODO: 在这里填写 272 字节陷入帧保存逻辑。
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

    # 传入 (frame=sp, cause=scause, value=stval) 调用 C 函数 handle_trap()；
    # handle_trap 返回的 a0 为调度器选中的“下一个员工”的陷入帧地址，直接切过去恢复现场。

    # TODO: 在这里填写调用 handle_trap 并切换至目标帧的指令。
    mv      a0, sp
    csrr    a1, scause
    csrr    a2, stval
    call    handle_trap
    mv      sp, a0
    j       restore_user
.Lkernel_trap:
    # 内核态意外陷入：换回内核 sp 后交由 C 函数 kernel_trap 打印诊断并停机。
    csrrw   sp, sscratch, sp
    csrw    sscratch, zero
    csrr    a0, scause
    csrr    a1, sepc
    csrr    a2, stval
    call    kernel_trap
    j       .Lhalt

    # 首次启动用户进程（enter_user）与调度恢复通用出口（restore_user）：
    # 恢复目标员工的 sepc、sstatus，并把目标员工自己的内核栈顶（sp + 272）写回 sscratch，
    # 防止下次陷入时串用上一个员工的内核栈；最后恢复通用寄存器及用户 sp 并执行 sret。

    # TODO: 在这里填写 enter_user 与 restore_user 的上下文恢复逻辑。
    .globl enter_user
enter_user:
    mv      sp, a0
restore_user:
    ld      t0, 256(sp)
    csrw    sepc, t0
    ld      t0, 264(sp)
    csrw    sstatus, t0
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
# 开机初期进入 C 语言环境前使用的 4 KiB 临时启动栈
boot_stack:
    .skip 4096
boot_stack_top:
