; TypingTutor.asm

INCLUDE Irvine32.inc
INCLUDE Macros.inc

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

VERTICAL_OFFSET = 5
HORIZONTAL_OFFSET = 20
LINE_LENGTH = 64
MAX_LINES = 5
BUFFER_SIZE = 5000
FILE_UNREAD = -1
TICK = 50 ; in milliseconds
SECOND_IN_TICKS = 20

.code
main proc

.data
	typingPrompt BYTE BUFFER_SIZE DUP(?)
	typingPromptSize DWORD 0
	filename BYTE "Text.txt", 0
	fileHandle HANDLE ?

	colors WORD LENGTHOF typingPrompt - 1 DUP(black+(white*16)), 0

	endingMsg BYTE "Level complete", 0
	
	; Cursor position
	cursorX BYTE 0
	cursorY BYTE 0

	charIdx BYTE 0

	linePrintTicksElapsed BYTE 0
	lineToPrint BYTE LINE_LENGTH DUP("a"), 0
	linePrintCharIdx DWORD 0
	linePrintLineNum BYTE 0
	distanceFromTop BYTE 15

.code
	; Set to standard color
	mov eax, black + (white * 16)
	call SetTextColor

	mov dh, VERTICAL_OFFSET
	mov dl, HORIZONTAL_OFFSET
	call UpdateCursorPos

	; Write prompt from file
	mov eax, black + (white * 16)
	call SetTextColor

	mov edx, OFFSET filename
	call openFile
	cmp eax, FILE_UNREAD
	je quit

	call closeInputFile
	call Crlf
	
	mov dh, VERTICAL_OFFSET
	mov dl, HORIZONTAL_OFFSET
	call UpdateCursorPos


MainGameLoop:
    mov  eax, TICK    
    call Delay           ; Delay to ensure proper key read


;	; --- WORK IN PROGRESS ---
;
;	; Skip line writing if reached end of prompt
;	mov eax, typingPromptSize
;	cmp linePrintCharIdx, eax		; If linePrintCharIdx >= typingPromptSize
;	jae KeyRead						; don't move cursor down
;
	inc linePrintTicksElapsed
	cmp linePrintTicksElapsed, SECOND_IN_TICKS * 2
	jne KeyRead

	dec distanceFromTop
	mov linePrintTicksElapsed, 0
	movzx ax, cursorX
	push ax
	
	; Set cursor position
	mov dh, distanceFromTop
	mov dl, HORIZONTAL_OFFSET
	call updateCursorPos

	; Write string
	add linePrintCharIdx, LINE_LENGTH
	mov edx, OFFSET typingPrompt
	mov ecx, linePrintCharIdx
	call PrintWithLineBreaks

	; Move cursor to line below
	call NewLine

	; Write blank lines to clear old text
	call ClearLine

	; Set cursor position
	mov dh, distanceFromTop
	pop ax
	mov cursorX, al
	mov dl, cursorX
	call updateCursorPos

;
;	; If time to write another line
;
;	mov eax, black + (white * 16)  ; Set to standard color
;	call SetTextColor
;
;	; Write previously written text
;	mov dh, cursorX
;	add dh, VERTICAL_OFFSET
;	add dh, distanceFromTop
;	mov dl, cursorY
;	add dl, HORIZONTAL_OFFSET
;	call Gotoxy
;
;	mov edx, OFFSET typingPrompt
;	mov ebx, 1
;	call WriteUntil
;
;	; Write new line of text
;	mov dh, linePrintLineNum		; Move to proper cursor position
;	add dh, VERTICAL_OFFSET
;	add dh, distanceFromTop
;	mov dl, HORIZONTAL_OFFSET
;	call Gotoxy
;
;	mov edx, OFFSET typingPrompt
;	mov ebx, linePrintCharIdx
;	call WriteLine
;	mov linePrintCharIdx, ebx		; Update character index after writing
;	mov linePrintTicksElapsed, 0	; Reset ticks elapsed
;
;	mov dh, cursorX
;	add dh, VERTICAL_OFFSET
;	add dh, distanceFromTop
;	mov dl, cursorY
;	add dl, HORIZONTAL_OFFSET
;	call Gotoxy
;
;	inc linePrintLineNum
;	dec distanceFromTop
;
;	; ------------------------

KeyRead:

    call ReadKey         ; look for keyboard input
    jz   MainGameLoop      ; no key pressed yet
	
	; Check if backspace pressed
	cmp dx, VK_BACK
	jne checkCharEqual

	; Backspace pressed
	cmp charIdx, 0                 ; If on char 0, don't do anything
	je MainGameLoop
	
	; Replacing the previous char
	dec cursorY
	dec charIdx                    ; Move cursor to previous char
	mov dh, cursorX
	add dh, VERTICAL_OFFSET
	mov dl, cursorY
	add dl, HORIZONTAL_OFFSET
	call Gotoxy

	mov eax, black + (white * 16)  ; Reverting color of char
	call SetTextColor
	movzx esi, charIdx             
	movzx eax, typingPrompt[esi]   ; Write character in default color
	call WriteChar
	call Gotoxy                    ; Move cursor back to previous char's space
	jmp MainGameLoop                 ; Return to loop start

checkCharEqual:
	inc cursorX

	movzx esi, charIdx
	; Compare input with text
	cmp    al, typingPrompt[esi]
	jne    charNotEqual

	; If character is equal
	mov eax, white + (green * 16)
	call UpdateChar
	jmp lineEndCheck

charNotEqual:
	mov eax, white + (red * 16)
	call UpdateChar

lineEndCheck:
	cmp cursorX, LINE_LENGTH + HORIZONTAL_OFFSET
	jne finishCheck
	call NewLine

	;inc cursorX
	;mov cursorY, 0
	;mov dh, cursorX
	;add dh, VERTICAL_OFFSET
	;mov dl, cursorY
	;add dl, HORIZONTAL_OFFSET
	call Gotoxy

finishCheck:
	inc    charIdx
	; If not finished yet
	cmp    typingPrompt[esi + 1], 0
	jne    MainGameLoop

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
;           EDX = Offset of the string to write.
; Returns:  EBX = Index of text ended at
;-------------------------------------------------------------------------------
WriteLine proc uses ecx
	mov ecx, LINE_LENGTH
lineWriter:
	mov al, [edx + ebx]
	cmp al, 0
	je quit
	call WriteChar
	inc ebx
	loop lineWriter

quit:
	ret
WriteLine endp



; EBX = Index of character in array to write
WriteColorChar proc uses ecx
	mov ecx, OFFSET colors

	mov eax, [ecx + (ebx * TYPE colors)]
	call SetTextColor

	mov al, [edx + ebx]
	call WriteChar
	
	ret
WriteColorChar endp


; EDX = Offset of string
; ECX = Amount of characters to print
PrintWithLineBreaks proc
	mov ebx, 0
	mov edi, 0				; Counter to if line length was reached
	mov al, [edx + ebx]

printLoop:
	; If reached line length, start new line
	cmp edi, LINE_LENGTH
	jne writeChars
	call NewLine
	mov edi, 0

writeChars:
	call WriteColorChar

	; Break if end of string
	inc ebx
	inc edi
	mov al, [edx + ebx]
	cmp al, 0
	jne continuePrintLoop

	call ClearLine
	jmp quit

continuePrintLoop:
	loop PrintLoop
	
quit:
	ret
PrintWithLineBreaks endp


updateCursorPos proc
	mov cursorX, dl
	mov cursorY, dh
	mGotoxy cursorX, cursorY
	ret
updateCursorPos endp


NewLine proc uses edx
	inc cursorY
	mov dh, cursorY
	mov dl, HORIZONTAL_OFFSET
	call updateCursorPos
	mGotoxy cursorX, cursorY
	ret
NewLine endp


clearLine proc uses eax
	mov eax, white+(black*16)
	call SetTextColor
	mWriteSpace LINE_LENGTH
	ret
clearLine endp

; EAX = the color to write in and save to colors array
UpdateChar proc
	call SetTextColor
	mov colors[esi * TYPE colors], ax	; Save color
	movzx eax, typingPrompt[esi]
	call WriteChar
	ret
UpdateChar endp

end main