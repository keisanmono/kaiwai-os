
    .section .text.boot
    .globl _start

# ==========================================
# 1. Machine Mode: Initialization
# 整体模型比喻：
#   M 态 = 大老板（开机权限最高，负责做底层准备后退居二线）
#   S 态 = 部门经理（操作系统内核，负责串口驱动、系统调用分发与异常处理）
#   U 态 = 普通打工人（用户程序，不能直接碰硬件，有需求必须敲门求助）
# ==========================================

_start:
    # 将 mstatus 的 MPP 字段（第 11~12 位）设置为 01 (S-mode)，
    # 使 mret 执行后进入 S-mode（相当于大老板提前填好“刚才来自 S 态经理岗”）。

    # TODO: 在这里填写对应的汇编指令。
    li      t0, 0x1800
    csrc    mstatus, t0
    li      t0, 0x0800
    csrs    mstatus, t0

    # 将 supervisor_entry 的地址写入 mepc，
    # 指定 mret 返回后的执行位置（经理办公室大门地址）。

    # TODO: 在这里填写对应的汇编指令。
    la      t0, supervisor_entry
    csrw    mepc, t0

    # 配置 PMP 物理内存保护（pmpaddr0=-1, pmpcfg0=0x0f），
    # 相当于给经理和打工人发全区门禁卡；否则降权后无法访问内存会直接触发异常。

    # TODO: 在这里填写对应的汇编指令。
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, 0x0f
    csrw    pmpcfg0, t0

    # 配置同步异常委派寄存器 medeleg = 0x104（Bit 2: 非法指令, Bit 8: U 态 ecall），
    # 相当于设置客服转接规则：打工人按门铃或写错指令时直接转给 S 态经理，不用惊动大老板。

    # TODO: 在这里填写对应的汇编指令。
    li      t0, 0x104
    csrw    medeleg, t0

    # 配置中断委派寄存器 mideleg |= 0x222（Bit 1/5/9: S 态软件/时钟/外部中断），
    # 将常见监管者中断一并委派给 S 态经理处理。

    # TODO: 在这里填写对应的汇编指令。
    li      t0, 0x222
    csrs    mideleg, t0

    # 执行 mret，利用硬件“返回机制”从 M 态降权切换到 S 态并跳转到 supervisor_entry。

    # TODO: 在这里填写对应的汇编指令。
    mret


# ==========================================
# 2. Supervisor Mode: Initialization
# 部门经理上岗，再用同样的方式从 S 态降权进入 U 态打工人
# ==========================================

supervisor_entry:
    # 将陷入总入口 supervisor_trap 的地址写入 stvec，
    # 相当于经理挂出前台门铃招牌：以后打工人按 ecall 或出事一律来这里。

    # TODO: 在这里填写对应的汇编指令。
    la      t0, supervisor_trap
    csrw    stvec, t0

    # 清除 sstatus 的 SPP 位（第 8 位，0x100），
    # 使 sret 执行后返回 U-mode（普通打工人身份）。

    # TODO: 在这里填写对应的汇编指令。
    li      t0, 0x100
    csrc    sstatus, t0

    # 将 user_entry 的地址写入 sepc，
    # 指定 sret 返回用户态后的第一条执行指令位置。

    # TODO: 在这里填写对应的汇编指令。
    la      t0, user_entry
    csrw    sepc, t0

    # 分离内核栈与用户栈（两张办公桌）：
    # 把 kernel_stack_top 暂存到 sscratch（用户态不可见），把 user_stack_top 交给 sp。

    # TODO: 在这里填写对应的汇编指令。
    la      t0, kernel_stack_top
    csrw    sscratch, t0

    la      sp, user_stack_top

    # 执行 sret，从 S 态降权进入 U 态并跳转到 user_entry。

    # TODO: 在这里填写对应的汇编指令。
    sret


# ==========================================
# 3. User Mode: Application
# U 态打工人：无权直接写串口，只能通过 ecall 门铃请求经理服务
# ==========================================

user_entry:
    # 先在临时寄存器 t3 放入测试值 0x55aa，
    # 用于检验后续内核 sys_putchar 改写 t3 时，陷入保护是否能把用户现场完整还原。
    li      t3, 0x55aa

    # 发起 2 号系统调用 puts(message)：a0 传入字符串地址，a7 传入调用号 2，
    # 执行 ecall 后将返回的打印字符长度保存到 s0。

    # TODO: 在这里填写对应的汇编指令。
    la      a0, message
    li      a7, 2
    ecall

    mv      s0, a0

    # 发起 1 号系统调用 putchar('!')：a0 传入 ASCII 33，a7 传入调用号 1。

    # TODO: 在这里填写对应的汇编指令。
    li      a0, 33
    li      a7, 1
    ecall

    # 故意发起未知的 99 号系统调用，验证内核返回错误码 -1 并保存到 s1。
    li      a7, 99
    ecall

    mv      s1, a0

user_halt:
    # 用户测试任务完成，原地死循环等待。
    j       user_halt


# ==========================================
# 4. Supervisor Mode: Trap Entry
# 前台接诊入口：门铃响起后硬件自动切回 S 态并记录 sepc 与 scause，跳到这里
# ==========================================

    # 满足 stvec Direct 模式最低两位为 00 的 4 字节对齐要求
    .balign 4

supervisor_trap:
    # 用 csrrw 原子对调用户栈指针 sp 与 sscratch 里的内核栈顶（交换两张办公桌），
    # 并检测 sp 是否为 0：因为内核态执行时 sscratch 会被清零，若换出 0 说明内核自身发生重入陷入。

    # TODO: 在这里填写对应的汇编指令。
    csrrw   sp, sscratch, sp

    beqz    sp, supervisor_kernel_trap

    # 在内核栈顶下方分配 256 字节陷入帧（32 个 8 字节储物格），
    # 保存全部通用寄存器，以免内核执行时踩坏用户程序现场。

    # TODO: 在这里填写对应的汇编指令。
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

    # 从 sscratch 取出原用户 sp 存入陷入帧 16(sp)，
    # 随后把 sscratch 清零，作为“当前正在内核态运行”的标志。

    # TODO: 在这里填写对应的汇编指令。
    csrr    t0, sscratch
    sd      t0, 16(sp)

    csrw    sscratch, zero

    # 检查陷入原因 scause 是否等于 8（U-mode ecall）；
    # 若不是 8，则跳转到 user_trap_unhandled 打印异常诊断信息。

    # TODO: 在这里填写对应的汇编指令。
    csrr    t0, scause
    li      t1, 8
    bne     t0, t1, user_trap_unhandled

    # 按系统调用号 a7 分发服务：1 号调 handle_putchar，2 号调 handle_puts，其余返回 -1。

    # TODO: 在这里填写对应的汇编指令。
    li      t0, 1
    beq     a7, t0, handle_putchar

    li      t0, 2
    beq     a7, t0, handle_puts

    li      a0, -1
    j       syscall_done


# ==========================================
# 5. System Call Dispatch
# ==========================================

handle_putchar:
    # 1 号服务：输出 1 个字符并返回 1
    call    sys_putchar
    li      a0, 1
    j       syscall_done

handle_puts:
    # 2 号服务：输出字符串，返回实际打印字符数
    call    sys_puts
    j       syscall_done


# ==========================================
# 6. System Call Return
# 经理办完事收拾现场，把打工人安全送回用户态下一条指令
# ==========================================

syscall_done:
    # 将系统调用返回值 a0 写回陷入帧的 80(sp) 槽位，避免恢复现场时被旧参数覆盖；
    # 同时将 sepc 加 4，跳过 4 字节的 ecall 指令，防止返回后无限重复触发 ecall。

    # TODO: 在这里填写对应的汇编指令。
    sd      a0, 80(sp)

    csrr    t0, sepc
    addi    t0, t0, 4
    csrw    sepc, t0

    # 从陷入帧恢复除 sp 与临时搬运工 t0 之外的通用寄存器。

    # TODO: 在这里填写对应的汇编指令。
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

    # 先借 t0 把原用户 sp 放回 sscratch，再从 40(sp) 恢复真正的 t0，
    # 释放 256 字节陷入帧后再次 csrrw 对调用户栈与内核栈，最后执行 sret 返回 U 态。

    # TODO: 在这里填写对应的汇编指令。
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

user_trap_unhandled:
    # 用户态意外异常：此时内核栈已经切换就绪，直接输出诊断头并转入报告
    la      a0, diag_user_header
    j       trap_diagnostic

supervisor_kernel_trap:
    # 内核态重入异常：先把被交换进 sscratch 的内核 sp 换回来再报告
    csrrw   sp, sscratch, sp

    la      a0, diag_kernel_header
    j       trap_diagnostic

trap_diagnostic:
    # 依次打印诊断标题、scause、sepc、stval 与换行
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
    # 报告完毕后停机等待
    j       trap_halt


# ==========================================
# 8. Kernel System Calls
# S 态系统调用实现：由内核直接操作 UART 硬件寄存器 0x10000000
# ==========================================

# 1 号系统调用 putchar：输入 a0 = 字符。
# 这里故意使用 t3，可用于验证上方陷入帧是否真正保护住了用户态的 t3=0x55aa。

sys_putchar:
    # TODO: 在这里填写对应的汇编指令。
    li      t3, 0x10000000
    sb      a0, 0(t3)
    ret


# 2 号系统调用 puts：输入 a0 = 字符串地址，输出 a0 = 打印字符数。
# 循序调用 sys_putchar 直到遇到 '\0'，并按调用规约保存和恢复 ra、s2、s3。

sys_puts:
    # TODO: 在这里填写对应的汇编指令。
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

# 直接打印 '\0' 结尾字符串：输入 a0 = 字符串地址

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


# 打印 64 位十六进制数：输入 a0 = 数值
# 先输出 "0x"，再循环 16 次每次右移 60 位取出最高 4 bit 转为 ASCII 字符

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
