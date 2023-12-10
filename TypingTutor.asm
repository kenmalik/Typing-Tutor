; TypingTutor.asm

INCLUDE Irvine32.inc
INCLUDE Macros.inc

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

VERTICAL_OFFSET = 2
HORIZONTAL_OFFSET = 20
LINE_LENGTH = 64
STARTING_DISTANCE = 24
BUFFER_SIZE = 5000
FILE_UNREAD = -1
TICK = 50 ; in milliseconds
SECOND_IN_TICKS = 20

.code
main proc

.data
	divider BYTE LINE_LENGTH DUP("-"), 0

	typingPrompt BYTE BUFFER_SIZE DUP(?)
	typingPromptSize DWORD 0
	filename BYTE "Text.txt", 0
	fileHandle HANDLE ?

	typingPromptLeftBound DWORD 0

	colors WORD LENGTHOF typingPrompt - 1 DUP(black+(white*16)), 0

	endingMsg BYTE "Level complete", 0
	
	; Cursor position
	cursorX BYTE 0
	cursorY BYTE 0
	distanceFromTop BYTE STARTING_DISTANCE

	charIdx DWORD 0

	linePrintTicksElapsed BYTE 0
	linePrintCharIdx DWORD 0
	lineProgressSpeed BYTE SECOND_IN_TICKS * 2
	

.code
	mov eax, white+(black*16)
	call SetTextColor
	call Clrscr

	; Read file to memory
	mov edx, OFFSET filename
	call openFile
	cmp eax, FILE_UNREAD
	je quit

	call closeInputFile
	call Crlf
	
	; Add top divider
	mov eax, yellow + (black * 16)
	call SetTextColor
	mGotoxy HORIZONTAL_OFFSET, VERTICAL_OFFSET - 1
	mWriteString OFFSET divider

	; Add bottom divider
	mGotoxy HORIZONTAL_OFFSET, VERTICAL_OFFSET + STARTING_DISTANCE
	mWriteString OFFSET divider

	; Set to standard color
	mov eax, black + (white * 16)
	call SetTextColor

	; Initial cursor positioning
	mov dh, VERTICAL_OFFSET
	add dh, distanceFromTop
	mov dl, HORIZONTAL_OFFSET
	call UpdateCursorPos


MainGameLoop:
    mov  eax, TICK    
    call Delay           ; Delay to ensure proper key read

	; If 2 seconds has passed, move text up one line
	inc linePrintTicksElapsed
	mov al, lineProgressSpeed
	cmp linePrintTicksElapsed, al
	jne KeyRead

	sub lineProgressSpeed, 1		; Increase the speed of progression
	dec distanceFromTop
	cmp distanceFromTop, -1			; Game over if reached top of play area
	je quit
	mov linePrintTicksElapsed, 0

	; Push cursor position to stack
	movzx ax, cursorX
	push ax
	movzx ax, cursorY
	push ax

	; Set cursor position to rewrite block of text
	mov dh, distanceFromTop
	add dh, VERTICAL_OFFSET
	mov dl, HORIZONTAL_OFFSET
	call UpdateCursorPos

	; Write text block
	add linePrintCharIdx, LINE_LENGTH
	mov edx, OFFSET typingPrompt
	mov ecx, linePrintCharIdx
	mov ebx, typingPromptLeftBound
	call PrintWithLineBreaks

	; Move cursor to line below
	call NewLine
	cmp cursorY, VERTICAL_OFFSET + STARTING_DISTANCE
	je ReturnToOriginalPos
	
	; Write blank lines to clear old text
	call ClearDisplayLine
	
ReturnToOriginalPos:
	; Pop original cursor position to return to former position
	pop ax
	dec al
	mov dh, al
	pop ax
	mov dl, al
	call UpdateCursorPos

KeyRead:

    call ReadKey         ; look for keyboard input
    jz   MainGameLoop      ; no key pressed yet
	
	; Check if backspace pressed
	cmp dx, VK_BACK
	jne checkCharEqual

	; Backspace pressed
	cmp cursorX, HORIZONTAL_OFFSET                 ; If on char 0, don't do anything
	je MainGameLoop
	
	; Replacing the previous char
	dec cursorX
	dec charIdx                    ; Move cursor to previous char
	mov esi, charIdx
	mov dh, cursorY
	mov dl, cursorX
	call UpdateCursorPos

	mov eax, black + (white * 16)  ; Reverting color of char
	call UpdateChar
	call Gotoxy                    ; Move cursor back to previous char's space
	jmp MainGameLoop                 ; Return to loop start

checkCharEqual:
	inc cursorX

	mov esi, charIdx
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

	; Clear completed lines
	mov dh, cursorY
	mov dl, HORIZONTAL_OFFSET
	call UpdateCursorPos					; Move cursor position for display clearing
	call ClearDisplayLine
	call NewLine
	add typingPromptLeftBound, LINE_LENGTH	; Move left bound for typing prompt forward
	inc distanceFromTop						; Inc distance from top to account for cleared line

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

quit:
	mov eax, white + (black * 16)
	call SetTextColor
	mGotoxy 0, VERTICAL_OFFSET + STARTING_DISTANCE + 4
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


; EBX = Index of character in array to write
WriteColorChar proc uses ecx
	inc cursorX
	mov ecx, OFFSET colors

	mov eax, [ecx + (ebx * TYPE colors)]
	call SetTextColor

	mov al, [edx + ebx]
	call WriteChar
	
	ret
WriteColorChar endp


; EDX = Offset of string
; ECX = The index to stop at
; EBX = The index to start from
PrintWithLineBreaks proc
 	mov edi, 0				; Counter for if line length was reached
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

	call ClearDisplayLine	; Clear the rest of the display line
	jmp quit

continuePrintLoop:
	cmp ebx, ecx
	jne printLoop
	
quit:
	ret
PrintWithLineBreaks endp


UpdateCursorPos proc
	mov cursorX, dl
	mov cursorY, dh
	mGotoxy cursorX, cursorY
	ret
UpdateCursorPos endp


NewLine proc uses edx
	inc cursorY
	mov dh, cursorY
	mov dl, HORIZONTAL_OFFSET
	call UpdateCursorPos
	ret
NewLine endp


ClearDisplayLine proc uses eax
	mov eax, white+(black*16)
	call SetTextColor

spaceWrite:
	mWriteSpace
	inc cursorX
	cmp cursorX, HORIZONTAL_OFFSET + LINE_LENGTH
	jne spaceWrite
	
	ret
ClearDisplayLine endp


; EAX = the color to write in and save to colors array
UpdateChar proc
	call SetTextColor
	mov colors[esi * TYPE colors], ax	; Save color
	movzx eax, typingPrompt[esi]
	call WriteChar
	ret
UpdateChar endp

end main