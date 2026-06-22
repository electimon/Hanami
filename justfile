prog := "Hanami"

[default]
build:
    objfw-compile -I wregex -o {{prog}} srcs/*.m wregex/*.m

clean:
    @rm `find . -name *.o`
    @rm {{prog}}
    @echo Done
