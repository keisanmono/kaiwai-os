
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
    .bss (NOLOAD) :
    {
        . = ALIGN(16);
        *(.bss .bss.*)
        *(COMMON)
    } :data
}
