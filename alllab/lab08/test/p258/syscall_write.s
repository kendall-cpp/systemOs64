;  .data段 （数据段）    通常包含初始化的数据
section .data
str_c_lib: db "c library says: hello world!", 0xa     ;0xa 是 LF ASCII 码 ; 0xa 是换行符
str_c_lib_len equ $-str_c_lib   					 ; equ 表示让左边的等于右边，
													; $-str_c_lib 表示当前地址-字符串初始地址，就是长度

str_syscall: db "syscall say: hello world!", 0xa
str_syscall_len equ $-str_syscall

;  .text段 （文本段）    通常包含可执行代码
section .text
global _start
_start:

; 第一种方式，使用 C 语言中系统调用库函数 write
	push str_c_lib_len		; 按照 C 调用约定压入栈
	push str_c_lib
	push 1

	call simu_write			; 这个函数时自己定义的
	add esp, 12     		; 回收栈空间

; 第二种方式，跨过库函数，字节进行系统调用
	mov eax,4		; 第 4 子功能好，就是 write 系统调用
	mov ebx,1
	mov ecx,str_syscall
	mov edx,str_syscall_len
	int 0x80		; 发起中断，通知 Linux 完成请求的功能

; 退出程序
	mov eax, 1		; 第 1 子功能号是 exit
	int 0x80		; 发起中断，通知 linux 完成请求的功能

; 下面定义的是 simu_write 函数，模拟 write 的实现
simu_write: 
	push ebp	;备份 ebp
	mov ebp,esp	
	mov eax, 4	; 第 4 号子功能，write 系统调用
	mov ebx, [ebp+8]   ;第1个参数
	mov ecx, [ebp+12]	;第2个参数
	mov edx, [ebp+16]	;第3个参数
	int 0x80			; 发起中断，通知linux完成请求的功能
	pop ebp
	ret





