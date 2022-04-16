extern void asm_print(char *,int);  // 这个函数在汇编代码中实现
void c_print(char * str) {
	int len = 0;
	while(str[len++]);
	asm_print(str,len);
}
