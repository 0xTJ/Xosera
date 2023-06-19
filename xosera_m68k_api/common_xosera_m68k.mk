# Xosera rosco_m68k common build rules
#
# vim: set noet ts=8 sw=8
# Copyright (c) 2023 Xark
# MIT LICENSE

# Makefile "best practices" from https://tech.davis-hansson.com/p/make/ (but not forcing gmake)
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# check for rosco_m68k toolchain
ifeq (, $(shell m68k-elf-gcc --version))
$(info No m68k-elf-* build tools found in path)
else
# check for rosco_m68k build dir
ifndef ROSCO_M68K_DIR
$(info Please set ROSCO_M68K_DIR to the rosco_m68k directory to use for rosco_m68k building)
endif
endif
# check for xosera_m68k_api build dir
ifndef XOSERA_M68K_API
$(info Please set XOSERA_M68K_API to the xosera_m68k_api directory to use for Xosera m68k building)
endif

# include special user rosco_m68k build riles
-include $(ROSCO_M68K_DIR)/user.mk

CPU?=68010
EXTRA_CFLAGS?=-g -O2 -fomit-frame-pointer -I$(XOSERA_M68K_API)
EXTRA_VASMFLAGS?=
EXTRA_LIBS?=-L$(XOSERA_M68K_API) -lxosera_m68k_api
SYSINCDIR?=$(ROSCO_M68K_DIR)/code/software/libs/build/include
SYSLIBDIR?=$(ROSCO_M68K_DIR)/code/software/libs/build/lib
DEFINES=-DROSCO_M68K
CFLAGS=-ffreestanding -ffunction-sections -fdata-sections \
    -Wall -Wextra -Werror -Wno-unused-function -pedantic -I$(SYSINCDIR) \
    -mcpu=$(CPU) -march=$(CPU) -mtune=$(CPU) $(DEFINES)
# EVIL    	CFLAGS += -Wall -Wextra -Wpedantic -Wformat=2 -Wformat-overflow=2 -Wformat-truncation=2 -Wformat-security -Wnull-dereference -Wstack-protector -Wtrampolines -Walloca -Wvla -Warray-bounds=2 -Wimplicit-fallthrough=3 -Wshift-overflow=2 -Wcast-qual -Wstringop-overflow=4 -Wconversion -Warith-conversion -Wlogical-op -Wduplicated-cond -Wduplicated-branches -Wformat-signedness -Wshadow -Wstrict-overflow=4 -Wswitch-default -Wswitch-enum -Wstack-usage=1000000 -Wcast-align=strict
# Too-EVIL 	-Wundef -Wstrict-prototypes  -Wtraditional-conversion
CXXFLAGS=-std=c++20 -fno-exceptions -fno-rtti $(FLAGS)
GCC_LIBS=$(shell $(CC) --print-search-dirs \
    | grep libraries:\ = \
    | sed 's/libraries: =/-L/g' \
    | sed 's/:/m68000\/ -L/g')m68000/
LIBS=$(EXTRA_LIBS) -lrosco_m68k -lgcc
ASFLAGS=-mcpu=$(CPU) -march=$(CPU)

ifneq ($(ROSCO_M68K_HUGEROM),false)
LDSCRIPT?=$(SYSLIBDIR)/ld/serial/hugerom_rosco_m68k_program.ld
else
LDSCRIPT?=$(SYSLIBDIR)/ld/serial/rosco_m68k_program.ld
endif

LDFLAGS=-T$(LDSCRIPT) -L$(SYSLIBDIR) \
    -Map=$(MAP) --gc-sections --oformat=elf32-m68k
VASMFLAGS=-Felf -m68010 -quiet -Lnf $(DEFINES)
CC=m68k-elf-gcc
CXX=m68k-elf-g++
AS=m68k-elf-as
LD=m68k-elf-ld
NM=m68k-elf-nm
LD=m68k-elf-ld
OBJDUMP=m68k-elf-objdump
OBJCOPY=m68k-elf-objcopy
SIZE=m68k-elf-size
VASM=vasmm68k_mot
RM=rm -f
KERMIT=kermit
SERIAL?=/dev/modem
BAUD?=9600

COPASM=../copper/CopAsm/bin/copasm

# Output config (assume name of directory)
PROGRAM_BASENAME=$(shell basename $(CURDIR))

# Set other output files using output basname
ELF=$(PROGRAM_BASENAME).elf
BINARY=$(PROGRAM_BASENAME).bin
DISASM=$(PROGRAM_BASENAME).dis
MAP=$(PROGRAM_BASENAME).map
SYM=$(PROGRAM_BASENAME).sym


# Assume source files in Makefile directory are source files for project
SOURCES+=$(wildcard *.c) $(wildcard *.cpp) $(wildcard *.S) $(wildcard *.asm) $(wildcard *.raw)

# Assume copasm will generate header file with copper code
CASMSOURCES?=
CASMOUTPUT=$(CASMSOURCES:.casm=.h)

# Assume copasm files will generate header files
HEADERS+=$(wildcard *.h) $(addsuffix .h,$(basename $(wildcard *.casm)))

# Assume each source files makes an object file
OBJECTS=$(addsuffix .o,$(basename $(SOURCES)))

all: $(BINARY) $(DISASM)

$(XOSERA_M68K_API)/libxosera_m68k_api.a:
	@echo === Building Xosera m68k API...
	cd $(XOSERA_M68K_API) && $(MAKE)

$(COPASM):
	@echo === Building copper assembler...
	cd $(XOSERA_M68K_API)/../copper/CopAsm/ && $(MAKE)

$(ELF) : $(OBJECTS) $(XOSERA_M68K_API)/libxosera_m68k_api.a
	$(LD) $(LDFLAGS) $(GCC_LIBS) $^ -o $@ $(LIBS)
	$(NM) --numeric-sort $@ >$(SYM)
	$(SIZE) $@
	-chmod a-x $@

$(BINARY) : $(ELF)
	$(OBJCOPY) -O binary $(ELF) $(BINARY)

$(DISASM) : $(ELF)
	$(OBJDUMP) --disassemble -S $(ELF) >$(DISASM)

$(OBJECTS): $(HEADERS) $(MAKEFILE_LIST)

%.h : %.casm $(COPASM)
	$(COPASM) -l -o $@ $<

%.o : %.c
	$(CC) -c $(CFLAGS) $(EXTRA_CFLAGS) -o $@ $<

%.o : %.cpp
	$(CXX) -c $(CXXFLAGS) $(EXTRA_CXXFLAGS) -o $@ $<

%.o : %.asm
	$(VASM) $(VASMFLAGS) $(EXTRA_VASMFLAGS) -L $(basename $@).lst -o $@ $<

# link raw binary file into executable (with symbols _binary_<name>_raw_start/*_end/*_size)
%.o: %.raw
	$(OBJCOPY) -I binary -O elf32-m68k -B m68k:68000 $< $@

# remove targets that can be generated by this Makefile
clean:
	$(RM) $(OBJECTS) $(CASMOUTPUT) $(ELF) $(BINARY) $(MAP) $(SYM) $(DISASM) $(addsuffix .lst,$(basename $(wildcard *.S) $(wildcard *.asm)))

disasm: $(DISASM)

# hexdump of program binary
dump: $(BINARY)
	hexdump -C $(BINARY)

# upload binary to rosco (if ready and kermit present)
load: $(BINARY)
	$(KERMIT) -i -l $(SERIAL) -b $(BAUD) -s $(BINARY)

# This is handy to test on Ubuntu Linux (kills previous "screen", opens one in shell window/tab)
test: $(BINARY) $(DISASM)
	-killall screen && sleep 1
	$(KERMIT) -i -l $(SERIAL) -b $(BAUD) -s $(BINARY)
	gnome-terminal --geometry=106x30 --title="rosco_m68k $(SERIAL)" -- screen $(SERIAL) $(BAUD)

# This is handy to test on MacOS (kills previous "screen", opens new one in shell window/tab)
mactest: $(BINARY) $(DISASM)
	-killall screen && sleep 1
	$(KERMIT) -i -l $(SERIAL) -b $(BAUD) -s $(BINARY)
	echo "#! /bin/sh" > $(TMPDIR)/rosco_screen.sh
	echo "/usr/bin/screen $(SERIAL) $(BAUD)" >> $(TMPDIR)/rosco_screen.sh
	chmod +x $(TMPDIR)/rosco_screen.sh
	sleep 1
	open -b com.apple.terminal $(TMPDIR)/rosco_screen.sh

# This is handy to test on MacOS (kills previous "screen", opens new one in shell window/tab)
macterm:
	-killall screen && sleep 1
	echo "#! /bin/sh" > $(TMPDIR)/rosco_screen.sh
	echo "/usr/bin/screen $(SERIAL) $(BAUD)" >> $(TMPDIR)/rosco_screen.sh
	chmod +x $(TMPDIR)/rosco_screen.sh
	sleep 1
	open -n -b com.apple.terminal $(TMPDIR)/rosco_screen.sh

# Makefile magic (for "phony" targets that are not real files)
.PHONY: all clean dump disasm load test mactest macterm
