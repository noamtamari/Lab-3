all: task1

task1: start.o util.o
	ld -m elf_i386 start.o util.o -o encoder1

start.o: start.s
	nasm -f elf32 start.s -o start.o

util.o: util.c util.h
	gcc -m32 -Wall -ansi -c -nostdlib -fno-stack-protector util.c -o util.o

clean:
	rm -f *.o encoder1
