CROSS   := riscv64-unknown-elf-
AS      := $(CROSS)as
LD      := $(CROSS)ld
OBJDUMP := $(CROSS)objdump
QEMU    := qemu-system-riscv64

BUILD   := build
TARGET  := $(BUILD)/baremetal.elf
OBJECT  := $(BUILD)/start.o

.PHONY: all run dump clean

all: $(TARGET)

$(BUILD):
	mkdir -p $(BUILD)

$(OBJECT): start.S | $(BUILD)
	$(AS) start.S -o $(OBJECT)

$(TARGET): $(OBJECT) linker.ld
	$(LD) -T linker.ld $(OBJECT) -o $(TARGET)

run: $(TARGET)
	$(QEMU) -machine virt -nographic -bios none -kernel $(TARGET)

dump: $(TARGET)
	$(OBJDUMP) -d $(TARGET)

clean:
	rm -rf $(BUILD)
