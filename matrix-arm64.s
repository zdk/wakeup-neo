.equ STDOUT,      1
.equ SYS_IOCTL,   29
.equ SYS_WRITE,   64
.equ SYS_EXIT,    93
.equ SYS_NSLEEP,  101
.equ SYS_CLKTIME, 113
.equ SYS_SIGACT,  134
.equ TIOCGWINSZ,  0x5413
.equ SIGINT,      2
.equ SIGTERM,     15

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
// aarch64 uses VDSO for the signal restorer; sa_restorer is ignored.
sa:
    .quad sigint_h
    .quad 0
    .quad 0
    .space 16

.section .rodata
chars:
    // カタカナ
    .ascii "ア\0" "イ\0" "ウ\0" "エ\0" "オ\0"
    .ascii "カ\0" "キ\0" "ク\0" "ケ\0" "コ\0"
    .ascii "サ\0" "シ\0" "ス\0" "セ\0" "ソ\0"
    .ascii "タ\0" "チ\0" "ツ\0" "テ\0" "ト\0"
    .ascii "ナ\0" "ニ\0" "ヌ\0" "ネ\0" "ノ\0"
    .ascii "ハ\0" "ヒ\0" "フ\0" "ヘ\0" "ホ\0"
    .ascii "マ\0" "ミ\0" "ム\0" "メ\0" "モ\0"
    .ascii "ヤ\0" "ユ\0" "ヨ\0" "ラ\0" "リ\0"
    .ascii "ル\0" "レ\0" "ロ\0" "ワ\0" "ヲ\0" "ン\0"
    // 数字
    .ascii "0 \0\0" "1 \0\0" "2 \0\0" "3 \0\0" "4 \0\0"
    .ascii "5 \0\0" "6 \0\0" "7 \0\0" "8 \0\0" "9 \0\0" "Z \0\0"
chars_end:
chars_n = (chars_end - chars) / CHAR_SLOT

init_str:  .ascii "\033[?25l\033[40m\033[2J\033[H"
init_len  = . - init_str
exit_str:  .ascii "\033[?25h\033[0m\033[2J\033[H"
exit_len  = . - exit_str
green_seq: .ascii "\033[40;1;32m"
green_len = . - green_seq
erase_seq: .ascii "\033[40m  "
erase_len = . - erase_seq

.text
.global _start

emit_byte:
    strb w0, [x19], #1
    ret

emit_str:
    cbz x1, .Les_done
.Les_loop:
    ldrb w2, [x0], #1
    strb w2, [x19], #1
    subs x1, x1, #1
    b.ne .Les_loop
.Les_done:
    ret

emit_char:
    mov w1, #CHAR_SLOT
.Lec_loop:
    ldrb w2, [x0], #1
    cbz w2, .Lec_done
    strb w2, [x19], #1
    subs w1, w1, #1
    b.ne .Lec_loop
.Lec_done:
    ret

emit_dec:
    sub sp, sp, #16
    add x3, sp, #15
    mov w4, #0
    mov w5, #10
.Led_loop:
    udiv w6, w0, w5
    msub w7, w6, w5, w0
    add w7, w7, #'0'
    strb w7, [x3], #-1
    add w4, w4, #1
    mov w0, w6
    cbnz w0, .Led_loop
    add x3, x3, #1
.Led_copy:
    ldrb w0, [x3], #1
    strb w0, [x19], #1
    subs w4, w4, #1
    b.ne .Led_copy
    add sp, sp, #16
    ret

rand:
    adrp x1, rng_state
    add  x1, x1, :lo12:rng_state
    ldr  x0, [x1]
    lsl  x2, x0, #13
    eor  x0, x0, x2
    lsr  x2, x0, #7
    eor  x0, x0, x2
    lsl  x2, x0, #17
    eor  x0, x0, x2
    str  x0, [x1]
    ret

sigint_h:
    mov  x8, #SYS_WRITE
    mov  x0, #STDOUT
    adrp x1, exit_str
    add  x1, x1, :lo12:exit_str
    mov  x2, #exit_len
    svc  #0

    mov  x8, #SYS_EXIT
    mov  x0, #0
    svc  #0

_start:
    mov  x8, #SYS_SIGACT
    mov  x0, #SIGINT
    adrp x1, sa
    add  x1, x1, :lo12:sa
    mov  x2, #0
    mov  x3, #8
    svc  #0

    mov  x8, #SYS_SIGACT
    mov  x0, #SIGTERM
    adrp x1, sa
    add  x1, x1, :lo12:sa
    mov  x2, #0
    mov  x3, #8
    svc  #0

    mov  x8, #SYS_IOCTL
    mov  x0, #STDOUT
    mov  x1, #TIOCGWINSZ
    adrp x2, winsize
    add  x2, x2, :lo12:winsize
    svc  #0

    adrp x0, winsize
    add  x0, x0, :lo12:winsize
    ldrh w21, [x0]
    ldrh w22, [x0, #2]

    cbnz w21, .Lhave_rows
    mov  w21, #24
.Lhave_rows:
    cbnz w22, .Lhave_cols
    mov  w22, #80
.Lhave_cols:
    lsr  w22, w22, #1
    cmp  w22, #MAX_COLS
    b.le .Lcols_ok
    mov  w22, #MAX_COLS
.Lcols_ok:

    mov  x8, #SYS_CLKTIME
    mov  x0, #0
    adrp x1, ts
    add  x1, x1, :lo12:ts
    svc  #0

    adrp x0, ts
    add  x0, x0, :lo12:ts
    ldr  x1, [x0]
    ldr  x2, [x0, #8]
    eor  x1, x1, x2
    cbnz x1, .Lseed_ok
    movz x1, #0x5678
    movk x1, #0x1234, lsl #16
    movk x1, #0xBABE, lsl #32
    movk x1, #0xCAFE, lsl #48
.Lseed_ok:
    adrp x0, rng_state
    add  x0, x0, :lo12:rng_state
    str  x1, [x0]

    mov  w23, #0
.Linit_loop:
    bl   rand
    udiv x2, x0, x21
    msub x3, x2, x21, x0
    adrp x4, y_pos
    add  x4, x4, :lo12:y_pos
    str  w3, [x4, w23, sxtw #2]
    add  w23, w23, #1
    cmp  w23, w22
    b.lt .Linit_loop

    mov  x8, #SYS_WRITE
    mov  x0, #STDOUT
    adrp x1, init_str
    add  x1, x1, :lo12:init_str
    mov  x2, #init_len
    svc  #0

.Lframe:
    adrp x19, outbuf
    add  x19, x19, :lo12:outbuf
    mov  x20, x19

    mov  w23, #0
.Lcol_loop:
    adrp x0, y_pos
    add  x0, x0, :lo12:y_pos
    ldr  w24, [x0, w23, sxtw #2]

    cmp  w24, #1
    b.lt .Lno_head
    cmp  w24, w21
    b.gt .Lno_head

    mov  w0, #0x1b
    bl   emit_byte
    mov  w0, #'['
    bl   emit_byte
    mov  w0, w24
    bl   emit_dec
    mov  w0, #';'
    bl   emit_byte
    lsl  w0, w23, #1
    add  w0, w0, #1
    bl   emit_dec
    mov  w0, #'H'
    bl   emit_byte

    adrp x0, green_seq
    add  x0, x0, :lo12:green_seq
    mov  x1, #green_len
    bl   emit_str

    bl   rand
    mov  x1, #chars_n
    udiv x2, x0, x1
    msub x3, x2, x1, x0
    lsl  x3, x3, #2
    adrp x0, chars
    add  x0, x0, :lo12:chars
    add  x0, x0, x3
    bl   emit_char

.Lno_head:
    sub  w25, w24, #TRAIL
    cmp  w25, #1
    b.lt .Lno_erase
    cmp  w25, w21
    b.gt .Lno_erase

    mov  w0, #0x1b
    bl   emit_byte
    mov  w0, #'['
    bl   emit_byte
    mov  w0, w25
    bl   emit_dec
    mov  w0, #';'
    bl   emit_byte
    lsl  w0, w23, #1
    add  w0, w0, #1
    bl   emit_dec
    mov  w0, #'H'
    bl   emit_byte

    adrp x0, erase_seq
    add  x0, x0, :lo12:erase_seq
    mov  x1, #erase_len
    bl   emit_str

.Lno_erase:
    add  w24, w24, #1
    add  w0, w21, #TRAIL + 8
    cmp  w24, w0
    b.le .Lkeep
    bl   rand
    and  x0, x0, #31
    neg  w24, w0
.Lkeep:
    adrp x0, y_pos
    add  x0, x0, :lo12:y_pos
    str  w24, [x0, w23, sxtw #2]

    add  w23, w23, #1
    cmp  w23, w22
    b.lt .Lcol_loop

    mov  x8, #SYS_WRITE
    mov  x0, #STDOUT
    mov  x1, x20
    sub  x2, x19, x20
    svc  #0

    adrp x0, ts
    add  x0, x0, :lo12:ts
    str  xzr, [x0]
    ldr  x1, =50000000
    str  x1, [x0, #8]
    mov  x8, #SYS_NSLEEP
    mov  x1, #0
    svc  #0

    b    .Lframe
