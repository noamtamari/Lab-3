#include "util.h"          // Provided to you (for strlen, strncmp, etc.)

extern int system_call();

// Raw syscall numbers
#define SYS_EXIT    1
#define SYS_READ    3
#define SYS_WRITE   4
#define SYS_OPEN    5
#define SYS_CLOSE   6
#define SYS_GETDENTS64 220  // Switch back to 64-bit version

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

/* 64-bit dirent layout */
struct linux_dirent64 {
    unsigned long long  d_ino;    // 64-bit inode number
    unsigned long long  d_off;    // 64-bit offset
    unsigned short d_reclen;      // Size of this dirent
    unsigned char  d_type;        // File type
    char           d_name[256];   // Fixed size array
} __attribute__((packed));

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

void print(const char* str) {
    sys_call(SYS_WRITE, 1, (int)str, strlen(str), 0, 0);
}

void print_error_exit() {
    print("Error occurred\n");
    sys_call(SYS_EXIT, 0x66, 0, 0, 0, 0); // Exit with code 0x66 as required
}

void print_int(int num) {
    char buf[12];
    int i = 0;
    int is_negative = 0;
    
    if (num == 0) {
        buf[i++] = '0';
        buf[i] = '\0';
        print(buf);
        return;
    }
    
    if (num < 0) {
        is_negative = 1;
        num = -num;
    }
    
    while (num > 0) {
        buf[i++] = (num % 10) + '0';
        num /= 10;
    }
    
    if (is_negative)
        buf[i++] = '-';
    
    buf[i] = '\0';
    
    // Reverse the string
    int start = 0;
    int end = i - 1;
    while (start < end) {
        char temp = buf[start];
        buf[start] = buf[end];
        buf[end] = temp;
        start++;
        end--;
    }
    
    print(buf);
}

int main(int argc, char **argv) {
    char *prefix = 0;
    int i;
    
    // Check for -a flag
    for (i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-a", 2) == 0) {
            prefix = argv[i] + 2; // pointer to prefix text
        }
    }
    
    // Call infection() once if -a supplied
    if (prefix) {
        print(prefix);
        infection();
    }
    
    // Open current directory
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
        print_int(-nread);
        print("\n");
        print_error_exit();
    }
    
    
    // Process directory entries
    int bpos = 0;
    while (bpos < nread) {
        struct linux_dirent64 *d = (struct linux_dirent64 *)(buf + bpos);
        char *name = d->d_name;
        
        // Skip "." and ".."
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
            print(name);
            print("\n");
            bpos += d->d_reclen;
            continue;
        }
        
        // Print the filename
        print(name);
        
        // If -a<prefix> given and name starts with prefix → infect
        if (prefix && strncmp(name, prefix, strlen(prefix)) == 0) {
            print(" VIRUS ATTACHED\n");
            infector(name);
        } else {
            print("\n");
        }
        
        // Advance to next entry
        bpos += d->d_reclen;
    }
    
    // Close directory and exit
    sys_call(SYS_CLOSE, fd, 0, 0, 0, 0);
    return 0;
}