###############################################################################
#	makefile
#	 by Alex Chadwick
#
#	A makefile script for generation of raspberry pi kernel images.
###############################################################################

# The toolchain to use. arm-none-eabi works, but there does exist 
# arm-bcm2708-linux-gnueabi.
ARMGNU ?= $(HOME)/c/gcc-linaro-7.1.1-2017.08-x86_64_aarch64-elf/bin/aarch64-elf

# The intermediate directory for compiled object files.
BUILD = build

# The directory in which source files are stored.
SOURCE = source

# The name of the output file to generate.
TARGET = $(BUILD)/kernel.elf

# The name of the assembler listing file to generate.
LIST = $(BUILD)/kernel.list

# The name of the map file to generate.
MAP = $(BUILD)/kernel.map

# The name of the linker script to use.
LINKER = kernel.ld

# The names of all object files that must be generated. Deduced from the 
# assembly code files in source.
OBJECTS := $(patsubst $(SOURCE)/%.S,$(BUILD)/%.o,$(wildcard $(SOURCE)/*.S))

# Targeted CPU.
TARGET_CPU = cortex-a57

QEMU := qemu-system-aarch64

QEMUFLAGS := -d guest_errors,unimp -M virt -cpu $(TARGET_CPU) -nographic -serial mon:stdio

# Rule to make everything.
all: $(TARGET) $(LIST)

# Rule to remake everything. Does not include clean.
rebuild: all

# Rule to make the listing file.
$(LIST) : $(BUILD)/kernel.elf
	$(ARMGNU)-objdump -d $(BUILD)/kernel.elf > $(LIST)

# Rule to make the elf file.
$(BUILD)/kernel.elf : $(OBJECTS) $(LINKER)
	$(ARMGNU)-ld --no-undefined $(OBJECTS) -Map $(MAP) -o $(BUILD)/kernel.elf -T $(LINKER)

# Rule to make the object files.
$(BUILD)/%.o: $(SOURCE)/%.s $(BUILD)
	$(ARMGNU)-as -mcpu=$(TARGET_CPU) -g -I $(SOURCE) $< -o $@

$(BUILD)/main.o: $(SOURCE)/builtins.fs

$(BUILD):
	mkdir $@

qemu: all
	$(QEMU) $(QEMUFLAGS) -kernel build/kernel.elf -S -s

qemu-nogdb: all
	$(QEMU) $(QEMUFLAGS) -kernel build/kernel.elf

gdb:
	$(ARMGNU)-gdb build/kernel.elf -ex 'target remote localhost:1234' -ex 'set confirm off' -ex 'layout prev'

# Rule to clean files.
clean : 
	-rm -rf $(BUILD)
	-rm -f $(TARGET)
	-rm -f $(LIST)
	-rm -f $(MAP)
