; ===============================================================================
;  Encoder Program - Task 1 (Using system_call wrapper)
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
  
  ; Exit program with main's return value - using system_call
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push 0                ; Third parameter (not used)
  push eax              ; Second parameter: exit code
  push 1                ; First parameter: SYS_EXIT (1)
  call system_call      ; Call system_call wrapper
  add  esp, 20          ; Clean up stack (5 params × 4 bytes)
  ; Note: We won't reach here as exit terminates the program

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
  mov  esi, [ebp+24]    ; Fourth argument (arg4) if needed
  mov  edi, [ebp+28]    ; Fifth argument (arg5) if needed
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
encoder_main:           
  push ebp              ; Set up stack frame
  mov  ebp, esp         ; Set new base pointer

  mov  ecx, [ebp+8]     ; ecx = argc (number of arguments)
  mov  esi, [ebp+12]    ; esi = argv (pointer to argument array)

  ; ----------------------------
  ; Parse -i and -o flags
  ; ----------------------------
  xor  edi, edi         ; edi = 0 (initialize argument index counter)

parse_arguments:        
  cmp  edi, ecx         ; Compare index with argc
  jge  done_parsing     ; If we've processed all args, continue
  mov  eax, [esi + edi*4] ; eax = argv[edi] (pointer to current argument)
  test eax, eax         ; Check if argument pointer is NULL
  je   done_parsing     ; If NULL, we're done parsing

  mov  bx, [eax]        ; Load first two bytes of argument string into bx
  cmp  bx, 0x692D       ; Compare with "-i" (0x69=i, 0x2D=-)
  je   setup_input_file 
  cmp  bx, 0x6F2D       ; Compare with "-o" (0x6F=o, 0x2D=-)
  je   setup_output_file 
  jmp  next_argument    ; Process next argument

setup_input_file:       
  add  eax, 2           ; Skip over "-i" part of argument
  push ecx              ; Save argc counter
  
  ; Call sys_open using system_call wrapper
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push 0                ; Third parameter - mode (not needed for read-only)
  push 0                ; Second parameter - O_RDONLY flag
  push eax              ; First parameter - filename pointer
  push 5                ; System call number (sys_open)
  call system_call      ; Call system_call wrapper
  add  esp, 24          ; Clean up stack (6 params × 4 bytes)
  
  pop  ecx              ; Restore argc counter
  cmp  eax, 0           ; Check if open succeeded (fd >= 0)
  jl   exit_program     ; If error (negative fd), exit program
  mov  [Infile], eax    ; Store new input file descriptor
  jmp  next_argument    ; Process next argument 

setup_output_file:      
  add  eax, 2           ; Skip over "-o" part of argument
  mov  ebx, eax         ; Save filename pointer
  push ecx              ; Save argc counter
  
  ; Call sys_open using system_call wrapper
  push 0                ; Fifth parameter (not used)
  push 0x1A4            ; Fourth parameter - mode (0644 permissions)
  push 577              ; Third parameter - flags: O_WRONLY|O_CREAT|O_TRUNC
  push ebx              ; Second parameter - filename pointer
  push 5                ; First parameter - system call number (sys_open)
  call system_call      ; Call system_call wrapper
  add  esp, 20          ; Clean up stack (5 params × 4 bytes)
  
  pop  ecx              ; Restore argc counter
  cmp  eax, 0           ; Check if open succeeded (fd >= 0)
  jl   exit_program     ; If error (negative fd), exit program
  mov  [Outfile], eax   ; Store new output file descriptor
  jmp  next_argument    ; Process next argument 

next_argument:          
  inc  edi              ; Increment argument index
  jmp  parse_arguments  ; Continue parsing flags

done_parsing:
  mov  ecx, [ebp+8]     ; Restore ecx = argc
  
  ; ----------------------------
  ; Debug print argv[] to stderr (Task 1.A)
  ; ----------------------------
  xor  edi, edi         ; edi = 0 (reset argument index)

print_arguments:        
  cmp  edi, ecx         ; Compare with argc
  jge  start_encoding   ; If all args printed, start encoding 
  mov  eax, [esi + edi*4] ; eax = argv[edi]
  test eax, eax         ; Check if argument pointer is NULL
  je   start_encoding   ; If NULL, we're done printing

  ; Get string length for write syscall
  push eax              ; Push argument string pointer
  call strlen           ; Call strlen(argv[edi])
  add  esp, 4           ; Clean up stack after call
  mov  edx, eax         ; edx = length of string

  ; Call sys_write using system_call wrapper
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push edx              ; Third parameter - string length
  push dword [esi+edi*4] ; Second parameter - string pointer
  push 2                ; First parameter - stderr file descriptor
  push 4                ; System call number (sys_write)
  call system_call      ; Call system_call wrapper
  add  esp, 24          ; Clean up stack

  ; Write newline character to stderr using system_call
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push 1                ; Third parameter - length (1 byte)
  push newline          ; Second parameter - newline character
  push 2                ; First parameter - stderr file descriptor
  push 4                ; System call number (sys_write)
  call system_call      ; Call system_call wrapper
  add  esp, 24          ; Clean up stack

  inc  edi              ; Increment argument index
  jmp  print_arguments  ; Continue printing arguments

start_encoding:         
  ; ----------------------------
  ; Encode input and write to output (Tasks 1.B and 1.C)
  ; ----------------------------
  mov  edi, buffer      ; edi = pointer to our character buffer

character_process_loop: 
  ; Read character using system_call
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push 1                ; Third parameter - read 1 byte
  push edi              ; Second parameter - buffer pointer
  push dword [Infile]   ; First parameter - input file descriptor
  push 3                ; System call number (sys_read)
  call system_call      ; Call system_call wrapper
  add  esp, 24          ; Clean up stack
  
  cmp  eax, 0           ; Check if we're at end of file (bytes_read == 0)
  je   handle_eof       ; If at EOF, jump to end-of-file handling 

  ; Perform encoding: Uppercase letters A-Z get shifted to previous letter
  mov  al,  [edi]       ; AL = current character read
  cmp  al,  'A'         ; Is it below 'A'?
  jl   output_character ; If so, don't modify it 
  cmp  al,  'Z'         ; Is it above 'Z'? 
  jg   output_character ; If so, don't modify it 

  ; Character is in uppercase range, perform shift
  cmp  al,  'A'         ; Special case: Is it 'A'?
  jne  decrement_letter ; If not 'A', just subtract 1 
  mov  al,  'Z'         ; Wrap 'A' around to 'Z'
  jmp  output_character ; Write the encoded character 

decrement_letter:       
  dec  al               ; Decrement character value: B→A, C→B, etc.

output_character:       
  mov  [edi], al        ; Store encoded character back to buffer
  
  ; Write character using system_call
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push 1                ; Third parameter - write 1 byte
  push edi              ; Second parameter - buffer pointer
  push dword [Outfile]  ; First parameter - output file descriptor
  push 4                ; System call number (sys_write)
  call system_call      ; Call system_call wrapper
  add  esp, 24          ; Clean up stack
  
  jmp  character_process_loop ; Continue reading next character

handle_eof:             
  ; Write final newline to output file using system_call
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push 1                ; Third parameter - length (1 byte)
  push newline          ; Second parameter - newline character
  push dword [Outfile]  ; First parameter - output file descriptor
  push 4                ; System call number (sys_write)
  call system_call      ; Call system_call wrapper
  add  esp, 24          ; Clean up stack

exit_program:
  ; Exit program with success code using system_call
  push 0                ; Fifth parameter (not used)
  push 0                ; Fourth parameter (not used)
  push 0                ; Third parameter (not used)
  push 0                ; Second parameter - exit code 0 (success)
  push 1                ; First parameter - SYS_EXIT (1)
  call system_call      ; Call system_call wrapper
  add  esp, 20          ; Clean up stack (5 params × 4 bytes)
  ; Note: We won't reach here as exit terminates the program
  ret                   ; Just in case - return to caller
