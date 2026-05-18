.intel_syntax noprefix

.equ STDOUT,      1
.equ SYS_WRITE,   1
.equ SYS_IOCTL,   16
.equ SYS_SIGACT,  13
.equ SYS_NSLEEP,  35
.equ SYS_EXIT,    60
.equ SYS_CLKTIME, 228
.equ SYS_SIGRET,  15
.equ TIOCGWINSZ,  0x5413
.equ SIGINT,      2
.equ SIGTERM,     15
.equ SA_RESTORER, 0x04000000

.equ MAX_COLS,    300
.equ TRAIL,       14
.equ CHAR_SLOT,   4

.bss
.align 8
winsize:   .skip 8
rng_state: .skip 8
y_pos:     .skip 1200
ts:        .skip 16
outbuf:    .skip 262144

.data
.align 8
sa:
    .quad sigint_h
    .quad SA_RESTORER
    .quad restorer
    .space 16

.section .rodata
chars:
    # カタカナ
    .ascii "ア\0" "イ\0" "ウ\0" "エ\0" "オ\0"
    .ascii "カ\0" "キ\0" "ク\0" "ケ\0" "コ\0"
    .ascii "サ\0" "シ\0" "ス\0" "セ\0" "ソ\0"
    .ascii "タ\0" "チ\0" "ツ\0" "テ\0" "ト\0"
    .ascii "ナ\0" "ニ\0" "ヌ\0" "ネ\0" "ノ\0"
    .ascii "ハ\0" "ヒ\0" "フ\0" "ヘ\0" "ホ\0"
    .ascii "マ\0" "ミ\0" "ム\0" "メ\0" "モ\0"
    .ascii "ヤ\0" "ユ\0" "ヨ\0" "ラ\0" "リ\0"
    .ascii "ル\0" "レ\0" "ロ\0" "ワ\0" "ヲ\0" "ン\0"
    # 数字
    .ascii "0 \0\0" "1 \0\0" "2 \0\0" "3 \0\0" "4 \0\0"
    .ascii "5 \0\0" "6 \0\0" "7 \0\0" "8 \0\0" "9 \0\0" "Z \0\0"
chars_end:
chars_n = (chars_end - chars) / CHAR_SLOT

init_str:  .ascii "\x1b[?25l\x1b[40m\x1b[2J\x1b[H"
init_len  = . - init_str
exit_str:  .ascii "\x1b[?25h\x1b[0m\x1b[2J\x1b[H"
exit_len  = . - exit_str
green_seq: .ascii "\x1b[40;1;32m"
green_len = . - green_seq
erase_seq: .ascii "\x1b[40m  "
erase_len = . - erase_seq

.text
.global _start

emit_byte:
    mov [rbx], al
    inc rbx
    ret

emit_str:
    test rcx, rcx
    jz .Les_done
.Les_loop:
    mov al, [rsi]
    mov [rbx], al
    inc rsi
    inc rbx
    dec rcx
    jnz .Les_loop
.Les_done:
    ret

emit_char:
    mov ecx, CHAR_SLOT
.Lec_loop:
    mov al, [rsi]
    test al, al
    jz .Lec_done
    mov [rbx], al
    inc rbx
    inc rsi
    dec ecx
    jnz .Lec_loop
.Lec_done:
    ret

emit_dec:
    xor ecx, ecx
    mov esi, 10
.Led_loop:
    xor edx, edx
    div esi
    add dl, '0'
    push rdx
    inc ecx
    test eax, eax
    jnz .Led_loop
.Led_pop:
    pop rax
    mov [rbx], al
    inc rbx
    dec ecx
    jnz .Led_pop
    ret

rand:
    mov rax, [rip + rng_state]
    mov rcx, rax
    shl rcx, 13
    xor rax, rcx
    mov rcx, rax
    shr rcx, 7
    xor rax, rcx
    mov rcx, rax
    shl rcx, 17
    xor rax, rcx
    mov [rip + rng_state], rax
    ret

sigint_h:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [rip + exit_str]
    mov rdx, exit_len
    syscall

    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

restorer:
    mov rax, SYS_SIGRET
    syscall

_start:
    mov rax, SYS_SIGACT
    mov rdi, SIGINT
    lea rsi, [rip + sa]
    xor rdx, rdx
    mov r10, 8
    syscall

    mov rax, SYS_SIGACT
    mov rdi, SIGTERM
    lea rsi, [rip + sa]
    xor rdx, rdx
    mov r10, 8
    syscall

    mov rax, SYS_IOCTL
    mov rdi, STDOUT
    mov rsi, TIOCGWINSZ
    lea rdx, [rip + winsize]
    syscall

    movzx r12d, word ptr [rip + winsize]
    movzx r13d, word ptr [rip + winsize + 2]

    test r12d, r12d
    jnz .Lhave_rows
    mov r12d, 24
.Lhave_rows:
    test r13d, r13d
    jnz .Lhave_cols
    mov r13d, 80
.Lhave_cols:
    shr r13d, 1
    cmp r13d, MAX_COLS
    jbe .Lcols_ok
    mov r13d, MAX_COLS
.Lcols_ok:

    mov rax, SYS_CLKTIME
    xor rdi, rdi
    lea rsi, [rip + ts]
    syscall

    mov rax, [rip + ts + 8]
    mov rcx, [rip + ts]
    xor rax, rcx
    test rax, rax
    jnz .Lseed_ok
    movabs rax, 0xCAFEBABE12345678
.Lseed_ok:
    mov [rip + rng_state], rax

    xor r14, r14
.Linit_loop:
    call rand
    xor edx, edx
    mov ecx, r12d
    div ecx
    lea rdi, [rip + y_pos]
    mov [rdi + r14*4], edx
    inc r14
    cmp r14d, r13d
    jl .Linit_loop

    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [rip + init_str]
    mov rdx, init_len
    syscall

.Lframe:
    lea rbx, [rip + outbuf]
    mov rbp, rbx

    xor r14, r14
.Lcol_loop:
    lea rax, [rip + y_pos]
    mov r15d, [rax + r14*4]

    cmp r15d, 1
    jl .Lno_head
    cmp r15d, r12d
    jg .Lno_head

    mov al, 0x1b
    call emit_byte
    mov al, '['
    call emit_byte
    mov eax, r15d
    call emit_dec
    mov al, ';'
    call emit_byte
    mov eax, r14d
    shl eax, 1
    inc eax
    call emit_dec
    mov al, 'H'
    call emit_byte

    lea rsi, [rip + green_seq]
    mov rcx, green_len
    call emit_str

    call rand
    xor edx, edx
    mov ecx, chars_n
    div ecx
    shl edx, 2
    lea rsi, [rip + chars]
    add rsi, rdx
    call emit_char

.Lno_head:
    mov r10d, r15d
    sub r10d, TRAIL
    cmp r10d, 1
    jl .Lno_erase
    cmp r10d, r12d
    jg .Lno_erase

    mov al, 0x1b
    call emit_byte
    mov al, '['
    call emit_byte
    mov eax, r10d
    call emit_dec
    mov al, ';'
    call emit_byte
    mov eax, r14d
    shl eax, 1
    inc eax
    call emit_dec
    mov al, 'H'
    call emit_byte

    lea rsi, [rip + erase_seq]
    mov rcx, erase_len
    call emit_str

.Lno_erase:
    inc r15d
    mov eax, r12d
    add eax, TRAIL + 8
    cmp r15d, eax
    jle .Lkeep
    call rand
    and eax, 31
    neg eax
    mov r15d, eax
.Lkeep:
    lea rdi, [rip + y_pos]
    mov [rdi + r14*4], r15d

    inc r14
    cmp r14d, r13d
    jl .Lcol_loop

    mov rsi, rbp
    mov rdx, rbx
    sub rdx, rbp
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    mov qword ptr [rip + ts], 0
    mov qword ptr [rip + ts + 8], 50000000
    mov rax, SYS_NSLEEP
    lea rdi, [rip + ts]
    xor rsi, rsi
    syscall

    jmp .Lframe
