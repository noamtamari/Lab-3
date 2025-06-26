all: main

main: start.o main.c util.c
	gcc  -m32 -nostdlib -fno-builtin -o virusAttacher  main.c util.c start.o

start.o: start.s
	nasm -f elf start.s

clean:
	rm -f *.o virusAttacher
