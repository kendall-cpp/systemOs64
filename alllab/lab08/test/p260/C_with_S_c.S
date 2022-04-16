section .data
str: db "asm_print says hello world!",0xa,0
; 0xa 是换行符，0 是手工加上的字符串结束符 \0 的 ASCII 码
str_len equ $-str


section .text
extern c_print
global _start
_start:

; 调用 C 代码中的函数 c_print
	push str
	call c_print
	add esp,4

; 退出程序
	mov eax,1
	int 0x80

; 到处该函数，供外部使用
global asm_print	; 相当于 asm_print(str,size)

asm_print:
	push ebp;
	mov ebp,esp  	; 将 ebp 作为基址访问栈中的参数
	mov eax,4		; 4 子功能号 write
	mov ebx,1		; 1 子功能号 exit
	mov ecx,[ebp+8]	; 第一个参数
	mov edx,[ebp+12];第二个参数
	int 0x80		; 发起中断
	pop ebp
	ret


