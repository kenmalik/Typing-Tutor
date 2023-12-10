; TypingTutor.asm

INCLUDE Irvine32.inc
INCLUDE Macros.inc

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

; Play area bounds
VERTICAL_OFFSET = 2
HORIZONTAL_OFFSET = 10
LINE_LENGTH = 64
STARTING_DISTANCE = 24

; File reading utilities
BUFFER_SIZE = 5000
FILE_UNREAD = -1

; Game logic timing
TICK = 50 ; in milliseconds
SECOND_IN_TICKS = 20
STARTING_PROGRESSION_SPEED = SECOND_IN_TICKS * 2

.code
main proc

.data
	; Graphics elements
	divider BYTE LINE_LENGTH DUP("-"), 0
	endingMsg BYTE "--- Level Complete ---", 0

	; For file handling
	typingPrompt BYTE BUFFER_SIZE DUP(?)
	typingPromptSize DWORD 0
	filename BYTE "Text.txt", 0
	fileHandle HANDLE ?

	; Typing prompt data
	typingPromptLeftBound DWORD 0
	charIdx DWORD 0
	textColors WORD LENGTHOF typingPrompt - 1 DUP(black+(white*16)), 0

	; Cursor position data
	cursorX BYTE 0
	cursorY BYTE 0
	distanceFromTop BYTE STARTING_DISTANCE

	; Typing prompt display timing
	linePrintTicksElapsed BYTE 0
	linePrintCharIdx DWORD 0
	lineProgressSpeed BYTE STARTING_PROGRESSION_SPEED
	

.code
	; Clear screen to prevent weird screen color
	mov eax, white+(black*16)
	call SetTextColor
	call Clrscr

	; Read file to memory
	mov edx, OFFSET filename
	call openFile
	cmp eax, FILE_UNREAD
	je quit
	call closeInputFile
	
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

	; If time to print another line of text prompt, do so
	inc linePrintTicksElapsed
	mov al, lineProgressSpeed
	cmp linePrintTicksElapsed, al
	jne KeyRead						; Else, read key

	; If reached top of play area, game over
	dec distanceFromTop
	cmp distanceFromTop, -1			
	je quit

	call NewPromptLine				; Print a new line of prompt
	sub lineProgressSpeed, 1		; Increase the speed of progression
	mov linePrintTicksElapsed, 0	; Reset tick counter for display

KeyRead:
    call ReadKey			; look for keyboard input
    jz   MainGameLoop		; no key pressed yet

	; If at bottom of play area, don't do anything
	cmp cursorY, VERTICAL_OFFSET + STARTING_DISTANCE
	je MainGameLoop
	
	; Check if backspace pressed
	cmp dx, VK_BACK
	jne checkCharEqual				; If not backspace, process inputted character

	; Backspace was pressed
	cmp cursorX, HORIZONTAL_OFFSET	; If on char 0, don't do anything
	je MainGameLoop

	call ReplacePreviousChar
	jmp MainGameLoop

checkCharEqual:
	; Compare input with text
	mov edi, charIdx
	cmp    al, typingPrompt[edi]
	jne    charNotEqual

	; If character is equal
	mov eax, white + (green * 16)
	call WriteToColorArr
	jmp lineEndCheck

charNotEqual:
	mov eax, white + (red * 16)
	call WriteToColorArr

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
	cmp    typingPrompt[edi + 1], 0
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


;-------------------------------------------------------------------------------
; CloseInputFile
;
; Closes the file currently in fileHandle.
;-------------------------------------------------------------------------------
CloseInputFile proc USES eax
	mov eax, fileHandle
	call CloseFile
	ret
CloseInputFile endp


;-------------------------------------------------------------------------------
; NewPromptLine
;
; Writes a new line in the typing prompt.
;-------------------------------------------------------------------------------
NewPromptLine proc USES eax ebx ecx edx
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
	call ReprintPrompt
	
	call NewLine	; Move cursor to line below written prompt

	; If cursor is not at bottom of play area, clear the display line below prompt
	cmp cursorY, VERTICAL_OFFSET + STARTING_DISTANCE
	je ReturnToOriginalPos
	call ClearDisplayLine
	
ReturnToOriginalPos:
	; Pop original cursor position to return to former position
	pop ax
	dec al			; Cursor y has to decrement to account for prompt having moved
	mov dh, al
	pop ax
	mov dl, al
	call UpdateCursorPos
	ret
NewPromptLine endp


;-------------------------------------------------------------------------------
; ReprintPrompt
;
; Reprints typing prompt using colors from text colors from colors array
; Receives: EDX = OFFSET of typing prompt
;			EBX = The index of typing prompt to start printing from
;			ECX = The index of typing prompt to stop printing at
;-------------------------------------------------------------------------------
ReprintPrompt proc USES edi
 	mov edi, 0				; Counter for if line length was reached
	mov al, [edx + ebx]

printLoop:
	; If reached line length, start new line
	cmp edi, LINE_LENGTH
	jne writeChars
	call NewLine
	mov edi, 0

writeChars:
	call WriteFromColorArr

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
ReprintPrompt endp


;-------------------------------------------------------------------------------
; WriteFromColorArr
;
; Writes a colored character to display using colors from text colors array.
; Receives: EBX = Index of character in array to write
;-------------------------------------------------------------------------------
WriteFromColorArr proc USES ecx
	inc cursorX
	mov ecx, OFFSET textColors	; Get a reference to text colors array

	mov eax, [ecx + (ebx * TYPE textColors)]	; Select color from array
	call SetTextColor

	mov al, [edx + ebx]			; Write character in selected color
	call WriteChar
	
	ret
WriteFromColorArr endp


;-------------------------------------------------------------------------------
; WriteToColorArr
;
; Writes a charater in a given color and saves that color to textColors array.
; Receives: EAX = the color to write in and save to textColors array
;			EDI = the index of color array to write to.
;-------------------------------------------------------------------------------
WriteToColorArr proc
	call SetTextColor
	mov textColors[edi * TYPE textColors], ax	; Save color
	movzx eax, typingPrompt[edi]
	call WriteChar
	inc cursorX
	ret
WriteToColorArr endp


;-------------------------------------------------------------------------------
; UpdateCursorPos
;
; Moves cursor to an (x,y) coordinate on screen and updates cursor location
; varaibles accordingly.
; Receives: DL = the x position to set cursor to
;			DH = the y position to set cursor to
;-------------------------------------------------------------------------------
UpdateCursorPos proc
	mov cursorX, dl
	mov cursorY, dh
	mGotoxy cursorX, cursorY
	ret
UpdateCursorPos endp


;-------------------------------------------------------------------------------
; NewLine
;
; Moves cursor to the next line in play area.
;-------------------------------------------------------------------------------
NewLine proc USES edx
	inc cursorY
	mov dh, cursorY
	mov dl, HORIZONTAL_OFFSET
	call UpdateCursorPos
	ret
NewLine endp


;-------------------------------------------------------------------------------
; ClearDisplayLine
;
; Clears a line of the play area starting from cursor's x coordinate.
;-------------------------------------------------------------------------------
ClearDisplayLine proc USES eax
	mov eax, white+(black*16)
	call SetTextColor

spaceWrite:
	mWriteSpace
	inc cursorX
	cmp cursorX, HORIZONTAL_OFFSET + LINE_LENGTH
	jne spaceWrite
	
	ret
ClearDisplayLine endp


;-------------------------------------------------------------------------------
; ReplacePreviousChar
;
; Reverts color of previous character in play area and updates text color array
; accordingly.
;-------------------------------------------------------------------------------
ReplacePreviousChar proc
	dec cursorX
	mov dh, cursorY
	mov dl, cursorX
	call UpdateCursorPos           ; Move cursor to previous char

	mov eax, black + (white * 16)  ; Reverting color of char (this moves cursor forward)
	dec charIdx         
	mov edi, charIdx
	call WriteToColorArr

	call UpdateCursorPos           ; Move cursor back to previous char's space

	ret
ReplacePreviousChar endp

end main