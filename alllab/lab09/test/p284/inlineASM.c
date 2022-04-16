char *str = "hello world";
//记录 write 系统调用的返回值
int count = 0;

void main() 
{
	 //将8个通用寄存器压入栈
asm("pusha; \   
	movl $4,%eax;	\
	movl $1,%ebx;	\
	movl str,%ecx;	\
	movl str,%edx;	\
	int $0x80;	\
	mov %eax,count;	\
	popa;	
	");
}