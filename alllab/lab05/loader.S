;------------------------
%include "boot.inc" 
section loader vstart=LOADER_BASE_ADDR 
LOADER_STACK_TOP equ LOADER_BASE_ADDR  ;相同内存地址，地址之下便是栈


;构建 gdt 及其内部的描述符
GDT_BASE: dd 0x00000000       ;第0个段描述符不可用
		dd 0x00000000  

CODE_DESC: dd 0x0000FFFF   ;代码段描述符
		 dd DESC_CODE_HIGH4 
 
DATA_STACK_DESC: dd 0x0000FFFF ;栈段描述符 栈段和数据段共用一个描述符 均向上扩展
		 dd DESC_DATA_HIGH4  
 
VIDEO_DESC: dd 0x80000007   ; limit=(0xbffff-0xb8000)/4k=0x7  故段界限为7
			dd  DESC_VIDEO_HIGH4  ;此时dpl为0
		

	 
GDT_SIZE equ $ - GDT_BASE ; 先是通过地址差来获得 GDT的大小，进而用 GDT大小减1得到了段界限
GDT_LIMIT equ GDT_SIZE - 1   ;用于构建GDTR的段界限


times 60 dq 0 ;此处预留 60 个描述符的空位


;;;;;;;;;;;;;;;;;;新增一句代码;;;;;;;;;;;;;

;total_mem_bytes用于保存内存容量,以字节为单位
;当前偏移loader.bin文件头0x200字节
;0x200字节=(60+4)*8=512字节
;loader.bin加载地址是0x900
;故total_mem_bytes代表的内存地址是0xb00
total_mem_bytes dd 0;  大小4个字节

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;以下是构建代码段、数据段、显存段选择子
SELECTOR_CODE equ (0x0001 << 3) + TI_GDT + RPL0 
;相当于[(CODE_DESC - GDT_BASE) /8 ]<<3+ TI_GDT + RPL0 
;内存地址的编号是一个存储单元8比特，这里CODE_DESC - GDT_BASE应该等于8
;书里的备注应该写掉了"<<3"
SELECTOR_DATA equ (0x0002<< 3) + TI_GDT + RPL0 
SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0 

;以下是 gdt 的指针即GDTR，前2字节是gdt界限，后4字节是gdt起始地址 后面代码使用lgdt指令时会用上
gdt_ptr dw GDT_LIMIT 
dd GDT_BASE 


;ards_buf为缓冲区地址，缓冲区用来装0xe820子功能返回的ARDS结构体
;一个ARDS结构体20字节，本次实验测试一共返回了6个。
;虽然ards_buf不需要244字节，定义244字节是为了下面代码的loader_start的地址长得好看
;人工对齐:total_mem_bytes+gdt_ptr+ards_buf+ards_nr=4+6+244+2=256,共256字节
;256字节=0x100字节
ards_buf times 244 db 0 
ards_nr dw 0 ;大小2个字节,用于记录 ARDS 结构体数量

; loader_start地址为0x900+0x300,偏移地址为0x300
;total_mem_bytes的文件内偏移为0x200，人工对齐又0x100，故0x300
   loader_start: 

; int 15h eax = 0000E820h ,edx = 534D4150h ('SMAP')获取内存布局

;;;;;;先使用0xe820子功能;;;;;;;;;
;;;;;先进行相关寄存器的输入;;;;;;;;;;
xor ebx, ebx   ; 异或运算，第一次使用0xe820子功能ebx要清0
mov edx, 0x534d4150 ;edx 只赋值一次，循环体中不会改变
mov di, ards_buf  ;ES:DI是ards结构缓冲区的指针,所以将ards缓冲区首地址赋给di
		  ;es已在mbr.s赋值完毕了,这里不用再赋值.
;;;;;循环调用0xe820子功能,获取每个 ARDS 内存范围描述结构;;;;;;
.e820_mem_get_loop: 
mov eax, 0x0000e820 ;执行int Oxl5 后，eax 值变为 Ox534d4150,
; 所以每次执行int前都要更新为子功能号
mov ecx, 20  ; 1个ards结构体大小为20字节
int 0x15;

jc .e820_failed_so_try_e801 
;cf 位为 1则 有错误发生，尝试 Oxe801子功能 
;;;;;cf为0,收集输出寄存器的值;
add di, cx ;使di 增加 20 字节指向缓冲区中新的 ARDS 结构位置
inc word [ards_nr] ;记录 ARDS 数量

;若ebx为0且cf不为1，这说明ards全部返回,退出循环
;若ebx不等于0,代码将会返回.e820_mem_get_loop,继续调用e820子功能返回ards结构体
cmp ebx, 0 
jnz .e820_mem_get_loop

;在所有 ards 结构中
;找出（base_add low + length_low ）的最大值，即内存的容量
mov cx, [ards_nr] ;遍历每一个 ARDS 结构体，循环次数是 ARDS 的数量
mov ebx, ards_buf 
xor edx, edx   ;ebx为最大容量，在此先清0
.find_max_mem_area: 
;无需判断 type 是否为1，最大的内存块一定是可被使用的 
mov eax, [ebx] ;缓冲区首地址就是第一个结构体的base_add_low,移了32位 
add eax, [ebx+8] ;base_add_low+length_low 
add ebx, 20 ;指向缓冲区中下－个 ARDS 结构
cmp edx, eax 
;简单选择排序，找出最大,edx寄存器始终记录最大的内存容量
jge .next_ards  ;edx大于eax就访问下一个ards结构体 
mov edx, eax    ;小于就记录在edx中
.next_ards: 
   loop .find_max_mem_area ;cx记录了ards结构体数量,cx为0说明已经循环了20次，最大的内存
;已经在edx中了,则退出循环。
   jmp .mem_get_ok ;将最大内存容量放入total_mem_byte中

;;;;;;;;int 15h ax = EBOlh 获取内存大小，最大支持4G
;返回后， ax ex 一样，以 KB 为单位， bx dx 值一样，以 64KB 为单位
;在 ax ex 寄存器中为低16MB ，在 bx dx 寄存器中为16MB到4GB

.e820_failed_so_try_e801:
   mov ax,0xe801 
   int 0x15 ;调用0xe810子功能
   jc .e801_failed_so_try88   ;cf为1表示出错
 
;若成功,先算出低 15MB 的内存
;ax ex 中是以 KB 为单位的内存数量，将其转换为以 byte 为单位
   mov cx, 0x400;  cx ax 值一样， cx 用作乘数 0x400字节=1KB
   mul cx        ;cx*ax 16位*16位 乘积32位，高16位dx保存，低16位ax保存
   shl edx,16 
   and eax,0x0000FFFF 
   or edx,eax  ;;;获得乘积，即获得内存容量字节数-1MB
   add edx, 0x100000   ;ax只是15MB,故要加1MB
   mov esi,edx  ;低15MB内存容量存入esi

; 再将 16MB 以上的内存转换为 byte 为单位
;寄存器 bx dx 中是以 64KB 为单位的内存数量
   xor eax, eax 
   mov ax, bx 
   mov ecx, 0x10000 
   mul ecx 
;0x10000 十进制为64KB
; 32 位乘法，默认的被乘数是 eax ，积为 64位
;高 32 位存入 edx ，低 32 位存入 eax
add esi, eax 
;由于此方法只能测出 4GB 以内的内存，故 32位eax 足够了
; edx 肯定为0，只加 eax 便可
   mov edx, esi ;edx 为总内存大小
   jmp .mem_get_ok 

;;;;;;;int 15h ah = Ox88 获取内存大小，只能获取 64MB 之内
.e801_failed_so_try88: 
;int 15 后， ax 存入的是以 KB 为单位的内存容量 100 mov ah, Ox88 
   int 0x15 
   jc .error_hlt 
   and eax,0x0000FFFF 
   mov cx, 0x400 
;0x400 等于 1024 ，将 ax 中的内存容量换为以 byte 为单位
   mul cx   
;16 位乘法，被乘数是 ax ，积为 32 位。积的高 16 位在 dx
;积的低 16 位在 ax

   shl edx, 16 ;把 dx 移到高 16
   or edx, eax ;把积的低 16 位组合到 edx ，为 32 位的积
   add edx, 0x100000 ; Ox88 子功能只会返回 lMB 以上的内存
;故实际内存大小要加上 lMB
.error_hlt:
   jmp $
.mem_get_ok: 
   mov [total_mem_bytes ], edx   ;3种子功能均是把最大容量放入edx
    ; 一一一一一一一一一一 准备进入保护模式 一一一一一一一一一一一一一一－
;1 打开 A20
;2 加载 gdt
;3 将cr0 的 pe 位置1 

;一一一一一一一－打开 A20 一一一一一
   in al,0x92
   or al, 0000_0010B 
   out 0x92,al 
 
;一一一一一一一一加载 GDT (也就是设置好gdtr，gdtr记录着gdt的起始地址)一一一一一一一－
   lgdt [gdt_ptr ] 

;一一一一一一一一 cr0位置1 一一一一一一一－
   mov eax, cr0 
   or eax, 0x00000001 
   mov cr0, eax 

   jmp dword SELECTOR_CODE:p_mode_start  ;刷新流水线

[bits 32] 
   p_mode_start: 
;;;;用选择子初始化段寄存器
	mov ax, SELECTOR_DATA 
	mov ds, ax 
	mov es, ax 
	mov ss, ax 
	mov esp, LOADER_STACK_TOP 
	mov ax, SELECTOR_VIDEO 
	mov gs, ax 
	
	
	mov byte [gs:0xA0], 'P' 

	jmp $
