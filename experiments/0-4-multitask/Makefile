CROSS   ?= riscv64-unknown-elf-
CC      := $(CROSS)gcc
OBJDUMP := $(CROSS)objdump
QEMU    ?= qemu-system-riscv64
BUILD   := build
TARGET  := $(BUILD)/kernel.elf
OBJECTS := $(BUILD)/start.o $(BUILD)/kernel.o $(BUILD)/user.o
CFLAGS  := -march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany -mno-relax \
           -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector \
           -Wall -Wextra -Werror -O2
LDFLAGS := -nostdlib -nostartfiles -Wl,--no-relax -Wl,-T,linker.ld

.PHONY: all run test dump clean
all: $(TARGET)

$(BUILD):
	mkdir -p $@

$(BUILD)/%.o: %.S | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/kernel.o: kernel.c kernel.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJECTS) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJECTS) -o $@

run: $(TARGET)
	$(QEMU) -machine virt -smp 1 -nographic -bios none -kernel $(TARGET)

test: $(TARGET)
	python3 test.py $(QEMU) $(TARGET)

dump: $(TARGET)
	$(OBJDUMP) -d $(TARGET)

clean:
	rm -rf $(BUILD)
