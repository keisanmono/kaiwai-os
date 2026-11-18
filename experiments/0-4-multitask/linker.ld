
ENTRY(_start)

PHDRS
{
    text   PT_LOAD FLAGS(5);  /* Read + Execute */
    rodata PT_LOAD FLAGS(4);  /* Read only */
    data   PT_LOAD FLAGS(6);  /* Read + Write */
}

SECTIONS
{
    . = 0x80000000;

    /* Executable code */
    .text :
    {
        KEEP(*(.text.boot))
        *(.text .text.*)
    } :text

    . = ALIGN(0x1000);

    /* Read-only data */
    .rodata :
    {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(0x1000);

    /* Writable data */
    .data :
    {
        *(.data .data.*)
    } :data

    /* Uninitialized data and stacks */
    /* BSS 区：存放未初始化全局变量、boot 栈以及两个员工的双栈；启动汇编会先把这里全擦成 0 */
    .bss (NOLOAD) :
    {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } :data
}
