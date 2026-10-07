    .section .text.boot
    .globl _start

_start:
    li      t0, 0x10000000
    la      t1, message

print_loop:
    lbu     t2, 0(t1)
    beqz    t2, done
    sb      t2, 0(t0)
    addi    t1, t1, 1
    j       print_loop

done:
    wfi
    j       done

    .section .rodata
message:
    .asciz "kaiwai-os bare metal\nName: Wang Yunyu\nStudent ID: 24281239\n"
