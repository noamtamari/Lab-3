; ===============================================================================
;  Encoder Program - Task 1
;  This program encodes input text by shifting uppercase letters down by one.
;  It supports stdin/stdout by default with optional file input/output redirection.
; ===============================================================================

section .data
newline  db 0xA         ; ASCII code for newline character (LF)
Infile   dd 0           ; Default input file descriptor = 0 (stdin)
Outfile  dd 1           ; Default output file descriptor = 1 (stdout)

section .bss
buffer   resb 1         ; One-byte buffer for reading/writing characters

section .text
global _start           ; Export _start symbol for linker entry point
global system_call      ; Export system_call for C compatibility
global encoder_main     ; Export main function with better name
extern strlen           ; Import strlen function from util.c

; -------------------------------------------------------------------------------
;  Program entry point: sets up stack, passes arguments to main, handles exit
; -------------------------------------------------------------------------------
_start:
  pop  dword ecx        ; ecx = argc (number of command-line arguments)
  mov  esi, esp         ; esi = pointer to argv[] array on stack
  mov  eax, ecx         ; Copy argc to eax for calculation
  shl  eax, 2           ; eax = argc * 4 (multiply by 4 for pointer size)
  add  eax, esi         ; eax = &argv[argc] (point to end of argv array)
  add  eax, 4           ; eax = &envp[0] (skip past NULL at end of argv)
  push eax              ; Push envp as third parameter to main()
  push esi              ; Push argv as second parameter to main()
  push ecx              ; Push argc as first parameter to main()
  call encoder_main     ; Call main function for encoding
  
  ; Exit program with main's return value
  mov  ebx, eax         ; ebx = return value from encoder_main
  mov  eax, 1           ; System call number for exit
  int  0x80             ; Invoke kernel: exit(main_return_value)

; -------------------------------------------------------------------------------
;  system_call: C-compatible wrapper for making Linux system calls
;  Follows C calling convention to allow calls from C code
; -------------------------------------------------------------------------------
system_call:
  push ebp              ; Save old base pointer
  mov  ebp, esp         ; Set up new stack frame
  sub  esp, 4           ; Make room for return value
  pushad                ; Save all general purpose registers
  
  ; Load system call arguments from stack
  mov  eax, [ebp+8]     ; System call number
  mov  ebx, [ebp+12]    ; First argument (arg1)
  mov  ecx, [ebp+16]    ; Second argument (arg2)
  mov  edx, [ebp+20]    ; Third argument (arg3)
  int  0x80             ; Invoke kernel to perform system call
  
  mov  [ebp-4], eax     ; Save return value from system call
  popad                 ; Restore all registers
  mov  eax, [ebp-4]     ; Put return value in eax
  add  esp, 4           ; Clean up local variable
  pop  ebp              ; Restore base pointer
  ret                   ; Return to caller

; -------------------------------------------------------------------------------
;  encoder_main: implements Task 1.A (debug print), 1.B (encode), 1.C (I/O redirection)
; -------------------------------------------------------------------------------
encoder_main:           ; Renamed from "main" to be more descriptive
  push ebp              ; Set up stack frame
  mov  ebp, esp         ; Set new base pointer

  mov  ecx, [ebp+8]     ; ecx = argc (number of arguments)
  mov  esi, [ebp+12]    ; esi = argv (pointer to argument array)

  ; ----------------------------
  ; Parse -i and -o flags
  ; ----------------------------
  xor  edi, edi         ; edi = 0 (initialize argument index counter)

parse_arguments:        ; Better name than parse_flags
  cmp  edi, ecx         ; Compare index with argc
  jge  done_parsing     ; If we've processed all args, continue
  mov  eax, [esi + edi*4] ; eax = argv[edi] (pointer to current argument)
  test eax, eax         ; Check if argument pointer is NULL
  je   done_parsing     ; If NULL, we're done parsing

  mov  bx, [eax]        ; Load first two bytes of argument string into bx
  cmp  bx, 0x692D       ; Compare with "-i" (0x69=i, 0x2D=-)
  je   setup_input_file ; Better name than handle_i
  cmp  bx, 0x6F2D       ; Compare with "-o" (0x6F=o, 0x2D=-)
  je   setup_output_file ; Better name than handle_o
  jmp  next_argument    ; Process next argument (renamed)

setup_input_file:       ; Renamed from handle_i
  add  eax, 2           ; Skip over "-i" part of argument
  mov  ebx, eax         ; ebx = filename pointer (after "-i")
  push ecx              ; Save argc counter
  mov  ecx, 0           ; O_RDONLY flag for open()
  mov  eax, 5           ; sys_open system call number
  int  0x80             ; Call kernel: fd = open(filename, O_RDONLY)
  pop  ecx              ; Restore argc counter
  cmp  eax, 0           ; Check if open succeeded (fd >= 0)
  jl   exit_program     ; If error (negative fd), exit program
  mov  [Infile], eax    ; Store new input file descriptor
  jmp  next_argument    ; Process next argument (renamed)

setup_output_file:      ; Renamed from handle_o
  add  eax, 2           ; Skip over "-o" part of argument
  mov  ebx, eax         ; ebx = filename pointer (after "-o")
  push ecx              ; Save argc counter
  mov  ecx, 577         ; O_WRONLY|O_CREAT|O_TRUNC flags
                        ; 577 = 0x0241 = 0001 + 0100 + 0100 0000
  mov  edx, 0x1A4       ; File mode 0644 (rw-r--r--)
  mov  eax, 5           ; sys_open system call number
  int  0x80             ; Call kernel: fd = open(filename, flags, mode)
  pop  ecx              ; Restore argc counter
  cmp  eax, 0           ; Check if open succeeded (fd >= 0)
  jl   exit_program     ; If error (negative fd), exit program
  mov  [Outfile], eax   ; Store new output file descriptor
  jmp  next_argument    ; Process next argument (renamed)

next_argument:          ; Renamed from next_arg
  inc  edi              ; Increment argument index
  jmp  parse_arguments  ; Continue parsing flags

done_parsing:
  mov  ecx, [ebp+8]     ; Restore ecx = argc
  
  ; ----------------------------
  ; Debug print argv[] to stderr (Task 1.A)
  ; ----------------------------
  xor  edi, edi         ; edi = 0 (reset argument index)

print_arguments:        ; Renamed from print_args
  cmp  edi, ecx         ; Compare with argc
  jge  start_encoding   ; If all args printed, start encoding (renamed)
  mov  eax, [esi + edi*4] ; eax = argv[edi]
  test eax, eax         ; Check if argument pointer is NULL
  je   start_encoding   ; If NULL, we're done printing

  ; Get string length for write syscall
  push eax              ; Push argument string pointer
  call strlen           ; Call strlen(argv[edi])
  add  esp, 4           ; Clean up stack after call
  mov  edx, eax         ; edx = length of string

  mov  ecx, [esi + edi*4] ; ecx = pointer to argument string
  mov  ebx, 2           ; stderr file descriptor (2)
  mov  eax, 4           ; sys_write system call number
  int  0x80             ; Call kernel: write(stderr, argv[edi], strlen(argv[edi]))

  ; Write newline character to stderr
  mov  eax, 4           ; sys_write system call number
  mov  ebx, 2           ; stderr file descriptor (2)
  mov  ecx, newline     ; Pointer to newline character
  mov  edx, 1           ; Length = 1 byte
  int  0x80             ; Call kernel: write(stderr, "\n", 1)

  inc  edi              ; Increment argument index
  jmp  print_arguments  ; Continue printing arguments

start_encoding:         ; Renamed from start_encode
  ; ----------------------------
  ; Encode input and write to output (Tasks 1.B and 1.C)
  ; ----------------------------
  mov  edi, buffer      ; edi = pointer to our character buffer

character_process_loop: ; Renamed from read_loop
  mov  eax, 3           ; sys_read system call number
  mov  ebx, [Infile]    ; File descriptor to read from
  mov  ecx, edi         ; Buffer to read into
  mov  edx, 1           ; Number of bytes to read
  int  0x80             ; Call kernel: bytes_read = read(Infile, buffer, 1)
  cmp  eax, 0           ; Check if we're at end of file (bytes_read == 0)
  je   handle_eof       ; If at EOF, jump to end-of-file handling (renamed)

  ; Perform encoding: Uppercase letters A-Z get shifted to previous letter
  mov  al,  [edi]       ; AL = current character read
  cmp  al,  'A'         ; Is it below 'A'?
  jl   output_character ; If so, don't modify it (renamed)
  cmp  al,  'Z'         ; Is it above 'Z'? 
  jg   output_character ; If so, don't modify it (renamed)

  ; Character is in uppercase range, perform shift
  cmp  al,  'A'         ; Special case: Is it 'A'?
  jne  decrement_letter ; If not 'A', just subtract 1 (renamed)
  mov  al,  'Z'         ; Wrap 'A' around to 'Z'
  jmp  output_character ; Write the encoded character (renamed)

decrement_letter:       ; Renamed from shift_down
  dec  al               ; Decrement character value: B→A, C→B, etc.

output_character:       ; Renamed from write_char
  mov  [edi], al        ; Store encoded character back to buffer
  mov  eax, 4           ; sys_write system call number
  mov  ebx, [Outfile]   ; File descriptor to write to
  mov  ecx, edi         ; Pointer to buffer containing character
  mov  edx, 1           ; Number of bytes to write
  int  0x80             ; Call kernel: write(Outfile, buffer, 1)
  jmp  character_process_loop ; Continue reading next character

handle_eof:             ; Renamed from eof
  ; Write final newline to output file
  mov  eax, 4           ; sys_write system call number
  mov  ebx, [Outfile]   ; Output file descriptor
  mov  ecx, newline     ; Pointer to newline character
  mov  edx, 1           ; Length = 1 byte
  int  0x80             ; Call kernel: write(Outfile, "\n", 1)

exit_program:
  mov  eax, 1           ; sys_exit system call number
  xor  ebx, ebx         ; Exit status code 0 (success)
  int  0x80             ; Call kernel: exit(0)
