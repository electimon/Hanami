PLUGIN_NAME = 02_IndexerPlugin

IS_WINDOWS := false
MACHINE_OS := $(shell clang -dumpmachine | cut -d'-' -f3)
ifeq ($(MACHINE_OS),windows)
IS_WINDOWS := true
endif

all:
ifneq ($(IS_WINDOWS),true)
	objfw-compile -I/usr/local/include/mayushii -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
else
	objfw-compile -L/usr/local/lib -lmayushii -L../../srcs -lhanami -I/usr/local/include/mayushii -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
endif
