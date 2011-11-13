ifeq ($(strip $(V)),)
	E = @echo
	Q = @
else
	E = @\#
	Q =
endif
export E Q

FIND		:= find
CSCOPE		:= cscope
TAGS		:= ctags
RM		:= rm
LD		:= ld
HEXDUMP		:= hexdump
CC		:= gcc
ECHO		:= echo
NM		:= nm
AWK		:= awk
SH		:= sh
MAKE		:= make

CFLAGS		+= -I./include
CFLAGS		+= -O0 -ggdb3

LIBS		+= -lrt -lpthread

# Additional ARCH settings for x86
ARCH ?= $(shell echo $(uname_M) | sed -e s/i.86/i386/ -e s/sun4u/sparc64/ \
                  -e s/arm.*/arm/ -e s/sa110/arm/ \
                  -e s/s390x/s390/ -e s/parisc64/parisc/ \
                  -e s/ppc.*/powerpc/ -e s/mips.*/mips/ \
                  -e s/sh[234].*/sh/ )

uname_M      := $(shell uname -m | sed -e s/i.86/i386/)
ifeq ($(uname_M),i386)
	ARCH         := x86
	DEFINES      += -DCONFIG_X86_32
endif
ifeq ($(uname_M),x86_64)
	ARCH         := x86
	DEFINES      += -DCONFIG_X86_64
endif

DEFINES		+= -D_FILE_OFFSET_BITS=64
DEFINES		+= -D_GNU_SOURCE

ifneq ($(WERROR),0)
	WARNINGS += -Werror
endif

WARNINGS	+= -Wall -Wno-unused
CFLAGS		+= $(WARNINGS) $(DEFINES)

PROGRAM		:= crtools

export CC ECHO MAKE CFLAGS LIBS ARCH DEFINES

all: $(PROGRAM)

OBJS		+= crtools.o
OBJS		+= parasite-syscall.o
OBJS		+= cr-dump.o
OBJS		+= cr-restore.o
OBJS		+= cr-show.o
OBJS		+= util.o
OBJS		+= elf.o
OBJS		+= seize.o
OBJS		+= restorer.o

DEPS		:= $(patsubst %.o,%.d,$(OBJS))

OBJS-BLOB	+= parasite.o
DEPS-BLOB	+= $(patsubst %.o,%.d,$(OBJS-BLOB))
SRCS-BLOB	+= $(patsubst %.o,%.c,$(OBJS-BLOB))

HEAD-BLOB	:= $(patsubst %.o,%.h,$(OBJS-BLOB))
HEAD-BLOB-GEN	:= $(patsubst %.o,%-blob.h,$(OBJS-BLOB))
HEAD-BIN	:= $(patsubst %.o,%.bin,$(OBJS-BLOB))
HEAD-LDS	:= $(patsubst %.o,%.lds.S,$(OBJS-BLOB))

HEAD-IDS	:= $(patsubst %.h,%_h__,$(subst -,_,$(HEAD-BLOB)))

$(OBJS-BLOB): $(SRCS-BLOB)
	$(E) "  CC      " $@
	$(Q) $(CC) -c $(CFLAGS) -fpic $< -o $@

$(HEAD-BIN): $(OBJS-BLOB) $(HEAD-LDS)
%.bin: %.o
	$(E) "  GEN     " $@
	$(Q) $(LD) -T $(patsubst %.bin,%.lds.S,$@) $< -o $@
	$(Q) $(LD) -T $(patsubst %.bin,%-elf.lds.S,$@) $< -o $@.o

$(HEAD-BLOB-GEN): $(HEAD-BIN) $(DEPS-BLOB)
$(HEAD-BLOB): $(DEPS-BLOB) $(HEAD-BIN)
%.h: %.bin
	$(E) "  GEN     " $@
	$(Q) $(SH) gen-offsets.sh					\
		$(subst -,_,$(patsubst %.h,%,$@))_h__			\
		$(subst -,_,$(patsubst %.h,%,$@))_blob_offset__		\
		$(subst -,_,$(patsubst %.h,%,$@))_blob			\
		$(patsubst %.h,%.o,$@)					\
		$(patsubst %.h,%.bin,$@) > $(patsubst %.h,%-blob.h,$@)
	$(Q) sync

$(OBJS): $(HEAD-BLOB) $(DEPS) $(HEAD-BLOB-GEN)
%.o: %.c
	$(E) "  CC      " $@
	$(Q) $(CC) -c $(CFLAGS) $< -o $@

$(PROGRAM): $(OBJS) restorer.o
	$(E) "  LINK    " $@
	$(Q) $(CC) $(CFLAGS) $(OBJS) $(LIBS) -o $@

$(DEPS): $(HEAD-BLOB)
%.d: %.c
	$(Q) $(CC) -M -MT $(patsubst %.d,%.o,$@) $(CFLAGS) $< -o $@

$(DEPS-BLOB): $(SRCS-BLOB)
	$(Q) $(CC) -M -MT $(patsubst %.d,%.o,$@) $(CFLAGS) $< -o $@

test:
	$(Q) $(MAKE) -C test all
.PHONY: test

rebuild:
	$(E) "  FORCE-REBUILD"
	$(Q) $(RM) -f ./*.o
	$(Q) $(RM) -f ./*.d
	$(Q) $(MAKE)
.PHONY: rebuild

clean:
	$(E) "  CLEAN"
	$(Q) $(RM) -f ./*.o
	$(Q) $(RM) -f ./*.d
	$(Q) $(RM) -f ./*.img
	$(Q) $(RM) -f ./*.elf
	$(Q) $(RM) -f ./*.out
	$(Q) $(RM) -f ./*.bin
	$(Q) $(RM) -f ./tags
	$(Q) $(RM) -f ./cscope*
	$(Q) $(RM) -f ./$(PROGRAM)
	$(Q) $(RM) -f ./$(HEAD-BLOB)
	$(Q) $(RM) -f ./$(HEAD-BLOB-GEN)
	$(Q) $(MAKE) -C test clean
.PHONY: clean

tags:
	$(E) "  GEN" $@
	$(Q) $(RM) -f tags
	$(Q) $(FIND) . -name '*.[hcS]' -print | xargs ctags -a
.PHONY: tags

cscope:
	$(E) "  GEN" $@
	$(Q) $(FIND) . -name '*.[hcS]' -print > cscope.files
	$(Q) $(CSCOPE) -bkqu
.PHONY: cscope
