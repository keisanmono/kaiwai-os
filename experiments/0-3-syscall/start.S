
    .section .text.boot
    .globl _start

# ==========================================
# 1. Machine Mode: Initialization
# 整体模型比喻：
#   M 态 = 大老板（开机权限最高，负责做底层准备后退居二线）
#   S 态 = 部门经理（操作系统内核，负责串口驱动、系统调用分发与异常处理）
#   U 态 = 普通打工人（用户程序，不能直接碰硬件，有需求必须敲门求助）
# ==========================================

# M 态大老板开机初始化函数（_start）：
# 1. 将 mstatus.MPP 设为 01 (S-mode)，并将 supervisor_entry 地址写入 mepc；
# 2. 配置 PMP 全物理地址门禁卡（pmpaddr0=-1, pmpcfg0=0x0f），放行降权后的内存访问权限；
# 3. 设置客服委派规则 medeleg=0x104（非法指令与 U 态 ecall）和 mideleg|=0x222（S 态中断）；
# 4. 执行 mret 降权切入 S 态内核入口。
#
# TODO: 在这里完成 M 态特权级准备、PMP 权限配置、异常/中断委派并切入 S 态。
_start:
    # 将 mstatus 的 MPP 字段（第 11~12 位）清零后设为 01 (S-mode)
    li      t0, 0x1800
    csrc    mstatus, t0
    li      t0, 0x0800
    csrs    mstatus, t0

    # 将 supervisor_entry 写入 mepc，作为 mret 返回目的地
    la      t0, supervisor_entry
    csrw    mepc, t0

    # 发全区门禁卡：配置 PMP 允许 S/U 态访问全部物理地址
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, 0x0f
    csrw    pmpcfg0, t0

    # 客服转接：委派同步异常（Bit 2 非法指令, Bit 8 U-mode ecall）及 S 态中断给 S-mode
    li      t0, 0x104
    csrw    medeleg, t0

    li      t0, 0x222
    csrs    mideleg, t0

    # 执行 mret 降权进入 S 态
    mret


# ==========================================
# 2. Supervisor Mode: Initialization
# 部门经理上岗，再用同样的方式从 S 态降权进入 U 态打工人
# ==========================================

# S 态部门经理初始化函数（supervisor_entry）：
# 1. 在 stvec 挂出陷入处理前台 supervisor_trap；
# 2. 清除 sstatus.SPP (0x100) 预设返回 U-mode，并将 user_entry 写入 sepc；
# 3. 分离两张办公桌：kernel_stack_top 存进 sscratch，user_stack_top 交给 sp；
# 4. 执行 sret 降权切入 U 态用户程序。
#
# TODO: 在这里完成 S 态陷入入口设置、双栈分离并降权进入 U 态。
supervisor_entry:
    # 设置 S 态陷入总入口 stvec
    la      t0, supervisor_trap
    csrw    stvec, t0

    # 清除 SPP 位（第 8 位）使 sret 返回 U 态，并把 user_entry 写入 sepc
    li      t0, 0x100
    csrc    sstatus, t0

    la      t0, user_entry
    csrw    sepc, t0

    # 内核栈顶放入 sscratch（用户态不可见），用户栈顶放入 sp
    la      t0, kernel_stack_top
    csrw    sscratch, t0

    la      sp, user_stack_top

    # 执行 sret 进入 U 态
    sret


# ==========================================
# 3. User Mode: Application
# U 态打工人：无权直接写串口，只能通过 ecall 门铃请求经理服务
# ==========================================

# U 态测试入口函数（user_entry）：
# 1. 先在 t3 放入暗号 0x55aa，测试内核写串口（内部用到 t3）时是否能完整保护用户现场；
# 2. 依次发起 2 号调用 puts（长度存入 s0）、1 号调用 putchar('!') 与未知 99 号调用（-1 存入 s1）；
# 3. 执行完毕后进入 user_halt 原地等待。
#
# TODO: 在这里编写用户态系统调用验证流程。
user_entry:
    # 测试值 t3 = 0x55aa（防踩踏验证）
    li      t3, 0x55aa

    # 按 2 号门铃：puts(message)，返回值（长度）存入 s0
    la      a0, message
    li      a7, 2
    ecall
    mv      s0, a0

    # 按 1 号门铃：putchar('!')
    li      a0, 33
    li      a7, 1
    ecall

    # 按 99 号门铃：测试不支持的系统调用返回 -1（存入 s1）
    li      a7, 99
    ecall
    mv      s1, a0

user_halt:
    j       user_halt


# ==========================================
# 4. Supervisor Mode: Trap Entry
# 前台接诊入口：门铃响起后硬件自动切回 S 态并记录 sepc 与 scause，跳到这里
# ==========================================

# S 态陷入总入口函数（supervisor_trap）：
# 1. 用 csrrw 对调用户 sp 与内核栈顶 sscratch，若换出 0 说明内核自身发生重入陷入；
# 2. 在内核栈开辟 256 字节储物柜保存全部通用寄存器及用户 sp（存入 16(sp)），并把 sscratch 清零；
# 3. 核对 scause == 8（U 态 ecall，否则转入 user_trap_unhandled），再按 a7 分发 1/2 号系统调用或返回 -1。
#
# TODO: 在这里实现陷入栈切换、256 字节现场保存、异常判断与系统调用分发。
    .balign 4
supervisor_trap:
    # 原子对调用户栈与内核栈，并检测内核态重入（sp == 0）
    csrrw   sp, sscratch, sp
    beqz    sp, supervisor_kernel_trap

    # 分配 256 字节陷入帧（32×8B 储物格），保存全部通用寄存器
    addi    sp, sp, -256
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

    # 取出暂存在 sscratch 的原用户 sp 存进 16(sp)，随后将 sscratch 清零标记处于内核态
    csrr    t0, sscratch
    sd      t0, 16(sp)
    csrw    sscratch, zero

    # 检查陷入原因 scause == 8（U-mode ecall），不是则跳转异常诊断
    csrr    t0, scause
    li      t1, 8
    bne     t0, t1, user_trap_unhandled

    # 按门铃号 a7 分派系统调用（1=putchar, 2=puts, 其他=-1）
    li      t0, 1
    beq     a7, t0, handle_putchar

    li      t0, 2
    beq     a7, t0, handle_puts

    li      a0, -1
    j       syscall_done


# ==========================================
# 5. System Call Dispatch
# ==========================================

# 系统调用分发桩函数（handle_putchar / handle_puts）：
# 分别调用对应的内核实现，并在完成后跳向 syscall_done 返回用户态。
#
# TODO: 在这里实现 1 号与 2 号系统调用分发入口。
handle_putchar:
    call    sys_putchar
    li      a0, 1
    j       syscall_done

handle_puts:
    call    sys_puts
    j       syscall_done


# ==========================================
# 6. System Call Return
# 经理办完事收拾现场，把打工人安全送回用户态下一条指令
# ==========================================

# 系统调用返回函数（syscall_done）：
# 1. 将返回值 a0 写回陷入帧 80(sp) 槽位，避免恢复现场时被旧参数覆盖；
# 2. 将 sepc 加 4 跳过 4 字节 ecall 指令，防止返回后无限重触发；
# 3. 恢复通用寄存器与 sscratch/用户 sp，释放 256 字节帧后执行 sret 返回 U 态。
#
# TODO: 在这里实现返回值写回、sepc 推进、现场恢复与 sret 返回。
syscall_done:
    # 写回返回值到 a0 槽位（80(sp)），并将 sepc += 4 跳过 ecall
    sd      a0, 80(sp)
    csrr    t0, sepc
    addi    t0, t0, 4
    csrw    sepc, t0

    # 恢复除 sp 与临时搬运工 t0 之外的通用寄存器
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

    # 把原用户 sp 放回 sscratch，恢复 t0，释放陷入帧后再次对调换回用户栈，最后 sret
    ld      t0, 16(sp)
    csrw    sscratch, t0
    ld      t0, 40(sp)
    addi    sp, sp, 256
    csrrw   sp, sscratch, sp
    sret


# ==========================================
# 7. Unexpected Trap Diagnostics
# 异常黑匣子：当出现非预期陷入时打印 scause、sepc、stval 并停机
# ==========================================

# 意外陷入诊断函数群（user_trap_unhandled / supervisor_kernel_trap / trap_diagnostic）：
# 若为用户态意外异常则直接打印诊断头；若为内核重入则先换回内核 sp，再依次打印 scause/sepc/stval 后停机。
#
# TODO: 在这里实现非预期异常的现场抢救与诊断输出流程。
user_trap_unhandled:
    la      a0, diag_user_header
    j       trap_diagnostic

supervisor_kernel_trap:
    # 把被 csrrw 换进 sscratch 的内核 sp 换回来
    csrrw   sp, sscratch, sp
    la      a0, diag_kernel_header
    j       trap_diagnostic

trap_diagnostic:
    call    kernel_puts_raw

    la      a0, diag_scause
    call    kernel_puts_raw
    csrr    a0, scause
    call    kernel_print_hex64

    la      a0, diag_sepc
    call    kernel_puts_raw
    csrr    a0, sepc
    call    kernel_print_hex64

    la      a0, diag_stval
    call    kernel_puts_raw
    csrr    a0, stval
    call    kernel_print_hex64

    la      a0, diag_newline
    call    kernel_puts_raw

trap_halt:
    j       trap_halt


# ==========================================
# 8. Kernel System Calls
# S 态系统调用实现：由内核直接操作 UART 硬件寄存器 0x10000000
# ==========================================

# 1 号系统调用函数 sys_putchar(a0=字符)：
# 直接往 QEMU UART0 地址 0x10000000 写入 1 字节；故意使用 t3 测试用户现场保护。
#
# TODO: 在这里实现 sys_putchar。
sys_putchar:
    li      t3, 0x10000000
    sb      a0, 0(t3)
    ret


# 2 号系统调用函数 sys_puts(a0=字符串地址) -> a0=打印字符数：
# 按调用规约保存 ra、s2、s3，循环调用 sys_putchar 输出直至 '\0' 并返回计数。
#
# TODO: 在这里实现 sys_puts。
sys_puts:
    addi    sp, sp, -32
    sd      ra, 24(sp)
    sd      s2, 16(sp)
    sd      s3, 8(sp)

    mv      s2, a0
    li      s3, 0

sys_puts_loop:
    lbu     a0, 0(s2)
    beqz    a0, sys_puts_done

    call    sys_putchar

    addi    s2, s2, 1
    addi    s3, s3, 1
    j       sys_puts_loop

sys_puts_done:
    mv      a0, s3

    ld      s3, 8(sp)
    ld      s2, 16(sp)
    ld      ra, 24(sp)
    addi    sp, sp, 32
    ret


# ==========================================
# 9. Raw Kernel UART Diagnostics
# 异常诊断专用的底层串口输出函数（不依赖系统调用，直接写 0x10000000）
# ==========================================

# 裸字符串输出函数 kernel_puts_raw(a0=字符串地址)：直接轮询字节写入 0x10000000。
#
# TODO: 在这里实现 kernel_puts_raw。
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


# 64 位十六进制输出函数 kernel_print_hex64(a0=数值)：
# 先输出 "0x"，再循环 16 次每次右移 60 位取出最高 4 bit 转为 ASCII 字符。
#
# TODO: 在这里实现 kernel_print_hex64。
kernel_print_hex64:
    li      t0, 0x10000000

    li      t4, 48
    sb      t4, 0(t0)
    li      t4, 120
    sb      t4, 0(t0)

    mv      t1, a0
    li      t2, 16

hex64_loop:
    srli    t3, t1, 60

    li      t4, 10
    bltu    t3, t4, hex64_digit

    addi    t3, t3, 87
    j       hex64_emit

hex64_digit:
    addi    t3, t3, 48

hex64_emit:
    sb      t3, 0(t0)

    slli    t1, t1, 4
    addi    t2, t2, -1
    bnez    t2, hex64_loop

    ret


# ==========================================
# 10. Read-only Data
# 只读数据区：存放输出文本与异常诊断提示信息
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
# 栈区：经理的 4 KiB 办公桌 + 打工人的 4 KiB 办公桌（栈从 top 高地址往下长）
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
