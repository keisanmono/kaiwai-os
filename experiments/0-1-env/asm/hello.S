    .section .rodata
message:
    .ascii "Subete Anata no Sei Desu.\n"
message_end:
    .equ message_len, message_end - message

    .section .text
    .globl _start

_start:
    # write(1, message, message_len)
    li a0, 1
    la a1, message
    li a2, message_len
    li a7, 64
    ecall

    # exit(0)
    li a0, 0
    li a7, 93
    ecall
