; TypingTutor.asm

INCLUDE Irvine32.inc
INCLUDE Macros.inc

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

HORIZONTAL_OFFSET = 15
LINE_LENGTH = 50
BUFFER_SIZE = 5000
FILE_UNREAD = -1

.code
main proc

.data
	typingPrompt BYTE BUFFER_SIZE DUP(?)
	typingPromptSize DWORD 0
	filename BYTE "Text.txt", 0
	fileHandle HANDLE ?

	endingMsg BYTE "Level complete", 0
	
	rowNum BYTE 0
	colNum BYTE 0

	charIdx BYTE 0

.code
	; Write prompt from file
	mov eax, black + (white * 16)
	call SetTextColor

	mov edx, OFFSET filename
	call openFile
	cmp eax, FILE_UNREAD
	je quit

	mov edx, OFFSET typingPrompt
	call WritePrompt

	call closeInputFile
	call Crlf

	; DEBUG: typing prompt size output
	; mov eax, typingPromptSize
	; call WriteInt

	
	
	mov dh, 0
	mov dl, HORIZONTAL_OFFSET
	call Gotoxy


TypingLoop:
    mov  eax, 50          
    call Delay           ; Delay to ensure proper key read

    call ReadKey         ; look for keyboard input
    jz   TypingLoop      ; no key pressed yet
	
	; Check if backspace pressed
	cmp dx, VK_BACK
	jne checkCharEqual

	; Backspace pressed
	cmp charIdx, 0                 ; If on char 0, don't do anything
	je TypingLoop
	
	; Replacing the previous char
	dec colNum
	dec charIdx                    ; Move cursor to previous char
	mov dh, rowNum
	mov dl, colNum
	add dl, HORIZONTAL_OFFSET
	call Gotoxy

	mov eax, black + (white * 16)  ; Reverting color of char
	call SetTextColor
	movzx esi, charIdx             
	movzx eax, typingPrompt[esi]   ; Write character in default color
	call WriteChar
	call Gotoxy                    ; Move cursor back to previous char's space
	jmp TypingLoop                 ; Return to loop start

checkCharEqual:
	movzx esi, charIdx
	; Compare input with text
	cmp    al, typingPrompt[esi]
	jne    charNotEqual

	; If character is equal
	mov eax, white + (green * 16)
	call SetTextColor
	movzx eax, typingPrompt[esi]
	call WriteChar
	jmp lineEndCheck

charNotEqual:
	mov eax, white + (red * 16)
	call SetTextColor
	movzx eax, typingPrompt[esi]
	call WriteChar

lineEndCheck:
	inc colNum
	cmp colNum, LINE_LENGTH
	jne finishCheck

	inc rowNum
	mov colNum, 0
	mov dh, rowNum
	mov dl, colNum
	add dl, HORIZONTAL_OFFSET
	call Gotoxy

finishCheck:
	inc    charIdx
	; If not finished yet
	cmp    typingPrompt[esi + 1], 0
	jne    TypingLoop

	; Level complete message
	call Crlf
	mov eax, white + (green * 16)
	call SetTextColor
	call Crlf
	mov edx, OFFSET endingMsg
	call WriteString
	

	; Reset color
	mov eax, white + (black * 16)
	call SetTextColor	

quit:
	invoke ExitProcess,0
main endp


;-------------------------------------------------------------------------------
; openFile
;
; Opens the file whose name is stored in filename. Verifies file is opened and
; that contents are within designated buffer size.
; Receives: EDX = Offset of the filename to be opened.
; Returns:  EAX = Bytes read (set to FILE_UNREAD if error occurs).
;-------------------------------------------------------------------------------
openFile proc
	call OpenInputFile
	mov fileHandle, eax

	cmp eax, INVALID_HANDLE_VALUE
	jne file_ok
	mWrite <"Cannot open file", 0dh, 0ah>
	mov eax, FILE_UNREAD
	jmp quit

file_ok:
	mov edx, OFFSET typingPrompt
	mov ecx, BUFFER_SIZE
	call ReadFromFile
	mov typingPromptSize, eax
	jnc check_buffer_size
	mWrite "Error reading file. "
	call WriteWindowsMsg
	mov eax, FILE_UNREAD
	jmp quit
	
check_buffer_size:
	cmp eax, BUFFER_SIZE
	jb quit
	mWrite <"Error: Buffer too small for the file", 0dh, 0ah>
	mov eax, FILE_UNREAD

quit:
	ret
openFile endp


closeInputFile proc
	mov eax, fileHandle
	call CloseFile
	ret
closeInputFile endp


;-------------------------------------------------------------------------------
; WriteLine
;
; Writes a line of LINE_LENGTH length.
; Receives: EBX = Starting index of text to be outputted
;           EDI = Offset of the filename to be opened.
; Returns:  EBX = Index of text ended at
;-------------------------------------------------------------------------------
WriteLine proc
	mov ecx, LINE_LENGTH
lineWriter:
	mov al, [edi + ebx]
	cmp al, 0
	je quit
	call WriteChar
	inc ebx
	loop lineWriter

quit:
	ret
WriteLine endp



WritePrompt proc
.data
	lineCharIdx DWORD 0
	lineNumber BYTE 0

.code
	mov ebx, 0
	mov edi, OFFSET typingPrompt

promptWriteLoop:
	mov lineCharIdx, ebx

	mov dh, lineNumber
	mov dl, HORIZONTAL_OFFSET
	call Gotoxy

	call WriteLine
	call Crlf
	inc lineNumber

	cmp ebx, lineCharIdx
	jne promptWriteLoop

	ret
WritePrompt endp

end main