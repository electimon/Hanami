PLUGIN_NAME = 52_HitCounter

IS_WINDOWS := false
MACHINE_OS := $(shell clang -dumpmachine | cut -d'-' -f3)
ifeq ($(MACHINE_OS),windows)
IS_WINDOWS := true
endif

all:
ifneq ($(IS_WINDOWS),true)
	objfw-compile -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
else
	objfw-compile -L../../srcs -lhanami -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
endif
