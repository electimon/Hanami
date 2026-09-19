PROG = Hanami
SRCS = $(wildcard srcs/*.m) $(wildcard wregex/*.m)
VERSION = 0.1

all: $(PROG) plugins

$(PROG): $(SRCS)
	objfw-compile -Wl,--export-dynamic --arc -g -L /usr/local/lib -lmayushii -I /usr/local/include/mayushii -I wregex -DVERSION=@\"$(VERSION)\" -o dist/$(PROG) $(SRCS)

plugins:
	@echo "Building plugins..."
	@mkdir -p dist/plugins
	@for dir in plugins-src/*; do \
		if [ -d "$$dir" ]; then \
			echo "Building plugin: $$dir"; \
			cd "$$dir"; \
			make; \
			mv *.dll ../../dist/plugins/ || mv *.so ../../dist/plugins/; \
			cd ../..; \
		fi; \
	done
	@echo "Done"

gen_compiledb:
	@echo "Generating compile_commands.json..."
	@FLAGS=$$(objfw-config --cppflags --objcflags); \
	echo "[" > compile_commands.json; \
	first=1; \
	for f in $(SRCS); do \
		if [ $$first -eq 0 ]; then echo "," >> compile_commands.json; fi; \
		first=0; \
		echo "{" >> compile_commands.json; \
		echo "  \"directory\": \"$$(pwd)\"," >> compile_commands.json; \
		echo "  \"file\": \"$$f\"," >> compile_commands.json; \
		printf "  \"command\": \"clang -I wregex -I /usr/local/include/mayushii $$FLAGS -c $$f\"\n" >> compile_commands.json; \
		echo "}" >> compile_commands.json; \
	done; \
	echo "]" >> compile_commands.json
	@echo "Done"

clean:
	@find . -name '*.o' -delete
	@rm -f $(PROG)
	@echo Done

.PHONY: all clean gen_compiledb
