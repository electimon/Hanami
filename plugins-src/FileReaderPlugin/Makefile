PLUGIN_NAME = 03_FileReaderPlugin

all:
ifneq ($(IS_WINDOWS),true)
	objfw-compile -I/usr/local/include/mayushii -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
else
	objfw-compile -L/usr/local/lib -lmayushii -L../../srcs -lhanami -I/usr/local/include/mayushii -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
endif
