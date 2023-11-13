; TypingTutor.asm

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

.code
main proc

.data
	

.code
	mov eax, 5


		

	invoke ExitProcess,0
main endp
end main