    .section .text
    # 两个 U 态打工人（alpha 与 beta）的上下文防踩踏验证程序：
    # 各自将专属特征值写入寄存器和用户栈，调用 yield 交替让出 CPU 后检查现场是否完好。

    # 校验宏：检查 s0、t3 与用户栈顶 0(sp) 是否仍等于当前任务的专属特征值。
    # TODO: 在这里完成上下文校验宏与系统调用封装宏。
    .macro CHECK_CONTEXT value
    li      t0, \value
    bne     s0, t0, context_failure
    bne     t3, t0, context_failure
    ld      t1, 0(sp)
    bne     t1, t0, context_failure
    .endm

    # 按 2 号门铃（puts）：请求内核打印字符串。
    .macro PUTS label
    la      a0, \label
    li      a7, 2
    ecall
    .endm

    # 按 3 号门铃（yield）：主动让出工位切换任务，恢复后校验返回值 a0 为 0。
    .macro YIELD
    li      a7, 3
    ecall
    bnez    a0, context_failure
    .endm

    # 1 号打工人 alpha（专属暗号：0x1234）：
    # 分配用户栈后依次打印三步，前两步让出，最后测试非法调用号 99 返回 -1 并 exit(0)。
    # TODO: 在这里填写 user_alpha 的实现。
    .globl user_alpha
user_alpha:
    addi    sp, sp, -16
    li      s0, 0x1234
    mv      t3, s0
    sd      s0, 0(sp)
    PUTS    alpha1
    YIELD
    CHECK_CONTEXT 0x1234
    PUTS    alpha2
    YIELD
    CHECK_CONTEXT 0x1234
    PUTS    alpha3
    li      a7, 99
    ecall
    li      t0, -1
    bne     a0, t0, context_failure
    CHECK_CONTEXT 0x1234
    li      a0, 0
    li      a7, 4
    ecall
    j       context_failure

    # 2 号打工人 beta（专属暗号：0x5678）：
    # 与 alpha 交替运行三步并校验上下文，最后调用 exit(0) 结束。
    # TODO: 在这里填写 user_beta 的实现。
    .globl user_beta
user_beta:
    addi    sp, sp, -16
    li      s0, 0x5678
    mv      t3, s0
    sd      s0, 0(sp)
    PUTS    beta1
    YIELD
    CHECK_CONTEXT 0x5678
    PUTS    beta2
    YIELD
    CHECK_CONTEXT 0x5678
    PUTS    beta3
    li      a0, 0
    li      a7, 4
    ecall
    j       context_failure

# 上下文校验失败处理分支（context_failure）：
# 若寄存器或栈校验失败，输出报错信息并以退出码 1 调用 exit(1) 结束。
#
# TODO: 在这里实现校验失败报错退出分支。
context_failure:
    PUTS    failed_message
    li      a0, 1
    li      a7, 4
    ecall
1:  j       1b

    .section .rodata
alpha1: .asciz "[alpha] step 1\n"
alpha2: .asciz "[alpha] step 2\n"
alpha3: .asciz "[alpha] step 3; context intact\n"
beta1:  .asciz "[beta]  step 1\n"
beta2:  .asciz "[beta]  step 2\n"
beta3:  .asciz "[beta]  step 3; context intact\n"
failed_message: .asciz "[user] context check FAILED\n"
