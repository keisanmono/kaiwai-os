    .section .text
    # Check unique register and stack values after another process has run.
    .macro CHECK_CONTEXT value
    li      t0, \value
    bne     s0, t0, context_failure
    bne     t3, t0, context_failure
    ld      t1, 0(sp)
    bne     t1, t0, context_failure
    .endm

    .macro PUTS label
    la      a0, \label
    li      a7, 2
    ecall
    .endm

    .macro YIELD
    li      a7, 3
    ecall
    bnez    a0, context_failure
    .endm

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
    # An unsupported syscall returns -1 without damaging the context.
    li      a7, 99
    ecall
    li      t0, -1
    bne     a0, t0, context_failure
    CHECK_CONTEXT 0x1234
    li      a0, 0
    li      a7, 4
    ecall
    j       context_failure

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
