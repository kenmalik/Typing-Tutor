; TypingTutor.asm

INCLUDE Irvine32.inc
INCLUDE Macros.inc

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

.data
MenuTable BYTE '1'
	DWORD PLAY_GAME
EntrySize = ($ - MenuTable)
	BYTE '2'
	DWORD LEADERBOARD
NumberOfEntries = ($ - MenuTable) / EntrySize

.code
main proc
	MAIN_MENU_X_OFFSET = 30
	MAIN_MENU_Y_OFFSET = 8
	LINE_SPACING = 2

MainMenu:
	; Clear screen to prevent weird screen color
	mov eax, white+(black*16)
	call SetTextColor
	call Clrscr

	; Display title
	mov eax, black + (yellow * 16)
	call SetTextColor

	mGotoxy MAIN_MENU_X_OFFSET, MAIN_MENU_Y_OFFSET
	mWrite "    TYPING TUTOR    "

	; Display menu options
	mov eax, yellow+(black*16)
	call SetTextColor

	mGotoxy MAIN_MENU_X_OFFSET, MAIN_MENU_Y_OFFSET + LINE_SPACING
	mWrite "1. Play Game"

	mGotoxy MAIN_MENU_X_OFFSET, MAIN_MENU_Y_OFFSET + LINE_SPACING * 2
	mWrite "2. View Leaderboard"

	mGotoxy MAIN_MENU_X_OFFSET, MAIN_MENU_Y_OFFSET + LINE_SPACING * 3
	mWrite ">>> "

	call ReadChar
	mov ebx, OFFSET MenuTable
	mov ecx, NumberOfEntries

L1:
	cmp al, [ebx]				; Inputted char = lookup value?
	jne L2

	call Clrscr					; Run menu procedure
	call NEAR PTR [ebx + 1]
	call Crlf
	jmp MainMenu

L2:
	add ebx, EntrySize			; Go to next entry
	loop L1

	exit						; If no matching entries found, exit


	invoke ExitProcess,0
main endp


;-------------------------------------------------------------------------------
;                                 MAIN GAME
;-------------------------------------------------------------------------------


; Play area bounds
PLAY_AREA_Y_OFFSET = 2
PLAY_AREA_X_OFFSET = 10
LINE_LENGTH = 64
STARTING_DISTANCE = 24
INFO_COLUMN_X = PLAY_AREA_X_OFFSET + LINE_LENGTH + 6
SCOREBOARD_Y = PLAY_AREA_Y_OFFSET + 4
SCORE_LABEL_LENGTH = 20

; File reading utilities
BUFFER_SIZE = 5000
FILE_UNREAD = -1

; Game logic timing
TICK = 50	; in milliseconds
SECOND_IN_TICKS = 20
STARTING_PROGRESSION_SPEED = SECOND_IN_TICKS * 3


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
	lineStatus DWORD 0, 0

	; Cursor position data
	cursorX BYTE 0
	cursorY BYTE 0
	distanceFromTop BYTE STARTING_DISTANCE

	; Typing prompt display timing
	linePrintTicksElapsed BYTE 0
	linePrintCharIdx DWORD 0
	lineProgressSpeed BYTE STARTING_PROGRESSION_SPEED

	; Score counters
	charsTyped DWORD 0
	backspacesPressed DWORD 0


.code
PLAY_GAME proc
	call ResetGame

	; Read file to memory
	mov edx, OFFSET filename
	call openFile
	cmp eax, FILE_UNREAD
	je quit
	call closeInputFile
	
	; Game title
	mov eax, black + (yellow * 16)
	call SetTextColor
	mGotoxy INFO_COLUMN_X, PLAY_AREA_Y_OFFSET + 2
	mWrite "    TYPING TUTOR    "

	; Add top divider
	mov eax, yellow + (black * 16)
	call SetTextColor
	mGotoxy PLAY_AREA_X_OFFSET, PLAY_AREA_Y_OFFSET - 1
	mWriteString OFFSET divider

	; Add bottom divider
	mGotoxy PLAY_AREA_X_OFFSET, PLAY_AREA_Y_OFFSET + STARTING_DISTANCE
	mWriteString OFFSET divider

	; Scoreboard labels
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y
	mWrite "Characters Typed  : "
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING
	mWrite "Backspaces Pressed: "

	; How to exit prompt
	mGotoxy INFO_COLUMN_X, PLAY_AREA_Y_OFFSET + STARTING_DISTANCE
	mWrite "Press ESC to Quit"

	; Set to standard color
	mov eax, black + (white * 16)
	call SetTextColor

	; Initial cursor positioning
	mov dh, PLAY_AREA_Y_OFFSET
	add dh, distanceFromTop
	mov dl, PLAY_AREA_X_OFFSET
	call UpdateCursorPos


MainGameLoop:
    mov  eax, TICK    
    call Delay           ; Delay to ensure proper key read

	call UpdateScoreboard

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
	cmp cursorY, PLAY_AREA_Y_OFFSET + STARTING_DISTANCE
	je MainGameLoop

	; Check if escape pressed
	cmp dx, VK_ESCAPE
	jne CheckBackspace
	ret

CheckBackspace:
	; Check if backspace pressed
	cmp dx, VK_BACK
	jne checkCharEqual				; If not backspace, process inputted character

	; Backspace was pressed
	cmp cursorX, PLAY_AREA_X_OFFSET	; If on char 0, don't do anything
	je MainGameLoop

	inc backspacesPressed
	call ReplacePreviousChar
	call RevertLineStatus
	jmp MainGameLoop

checkCharEqual:
	inc charsTyped

	; Compare input with text
	mov edi, charIdx
	cmp    al, typingPrompt[edi]
	jne    CharNotEqual

	; If character is equal
	mov eax, white + (green * 16)
	call WriteToColorArr
	call CorrectInput
	jmp LineEndCheck

CharNotEqual:
	mov eax, white + (red * 16)
	call WriteToColorArr
	call WrongInput

LineEndCheck:
	inc    charIdx
	cmp cursorX, LINE_LENGTH + PLAY_AREA_X_OFFSET
	jne finishCheck

	call CheckLineStatus
	jc ClearLine
	call ReplacePreviousChar
	call RevertLineStatus
	dec charsTyped
	jmp MainGameLoop

ClearLine:
	; Clear completed lines
	mov ebx, typingPromptLeftBound
	call ClearLineStatus
	mov dh, cursorY
	mov dl, PLAY_AREA_X_OFFSET
	call UpdateCursorPos					; Move cursor position for display clearing
	call ClearDisplayLine
	call NewLine
	add typingPromptLeftBound, LINE_LENGTH	; Move left bound for typing prompt forward
	inc distanceFromTop						; Inc distance from top to account for cleared line

finishCheck:
	; If not finished yet
	cmp    typingPrompt[edi + 1], 0
	jne    MainGameLoop

	mov ebx, typingPromptLeftBound
	call CheckLineStatus
	jc LevelComplete
	call ReplacePreviousChar
	call RevertLineStatus
	dec charsTyped
	jmp MainGameLoop


LevelComplete:
	; Level complete message
	call Crlf
	mov eax, white + (green * 16)
	call SetTextColor
	call Crlf
	mWriteString OFFSET endingMsg
	call NewLine
	call WaitMsg

quit:
	mov eax, white + (black * 16)
	call SetTextColor
	mGotoxy 0, PLAY_AREA_Y_OFFSET + STARTING_DISTANCE + 4
	ret
PLAY_GAME endp


;-------------------------------------------------------------------------------
;                                LEADERBOARD
;-------------------------------------------------------------------------------


.code
LEADERBOARD proc
	mWrite "Not implemented"
	call ReadChar
	ret
LEADERBOARD endp



;-------------------------------------------------------------------------------
;                                PROCEDURES
;-------------------------------------------------------------------------------


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
	add dh, PLAY_AREA_Y_OFFSET
	mov dl, PLAY_AREA_X_OFFSET
	call UpdateCursorPos

	; Write text block
	add linePrintCharIdx, LINE_LENGTH
	mov edx, OFFSET typingPrompt
	mov ecx, linePrintCharIdx
	mov ebx, typingPromptLeftBound
	call ReprintPrompt
	
	call NewLine	; Move cursor to line below written prompt

	; If cursor is not at bottom of play area, clear the display line below prompt
	cmp cursorY, PLAY_AREA_Y_OFFSET + STARTING_DISTANCE
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
	mov dl, PLAY_AREA_X_OFFSET
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
	cmp cursorX, PLAY_AREA_X_OFFSET + LINE_LENGTH
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



UpdateScoreboard proc USES eax edx
	; Push cursor position to stack
	movzx ax, cursorX
	push ax
	movzx ax, cursorY
	push ax

	mov eax, yellow+(black*16)
	call SetTextColor

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y
	mov eax, charsTyped
	call WriteDec

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y + LINE_SPACING
	mov eax, backspacesPressed
	call WriteDec

	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING * 2
	mov eax, lineStatus
	call WriteBin

	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING * 3
	mov eax, lineStatus[TYPE lineStatus]
	call WriteBin

	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING * 4
	mov ebx, typingPromptLeftBound
	call CheckLineStatus
	jnc NotComplete
	mWrite "Line complete"
	jmp Complete

NotComplete:
	mWrite "Line not complete"
Complete:

	; Pop original cursor position to return to former position
	pop ax
	mov dh, al
	pop ax
	mov dl, al
	call UpdateCursorPos

	ret
UpdateScoreboard endp


ResetGame proc
	; Reset scores
	mov charsTyped, 0
	mov backspacesPressed, 0

	; Reset starting distance
	mov distanceFromTop, STARTING_DISTANCE

	; Reset typing prompt data
	mov typingPromptLeftBound, 0
	mov charIdx, 0


	; Reset timing
	mov linePrintTicksElapsed, 0
	mov linePrintCharIdx, 0
	mov lineProgressSpeed, STARTING_PROGRESSION_SPEED

	mov ecx, LENGTHOF textColors - 1
ResetColors:
	mov textColors[ecx * TYPE textColors], black+(white*16)
	loop ResetColors
	mov textColors[ecx * TYPE textColors], black+(white*16)

	mov ecx, LENGTHOF lineStatus - 1
ResetLineStatus:
	mov lineStatus[ecx * TYPE lineStatus], 0
	loop ResetColors
	mov lineStatus[ecx * TYPE lineStatus], 0

	ret
ResetGame endp


;-------------------------------------------------------------------------------
; CorrectInput
;
; Updates line status bit string to reflect correct input.
;-------------------------------------------------------------------------------
CorrectInput proc USES eax
	mov eax, lineStatus[0]
	shrd lineStatus[TYPE lineStatus], eax, 1
	mov eax, 1
	shrd lineStatus[0], eax, 1
	ret
CorrectInput endp


;-------------------------------------------------------------------------------
; WrongInput
;
; Updates line status bit string to reflect incorrect input.
;-------------------------------------------------------------------------------
WrongInput proc USES eax
	mov eax, lineStatus[0]
	shrd lineStatus[TYPE lineStatus], eax, 1
	shr lineStatus[0], 1
	ret
WrongInput endp


;-------------------------------------------------------------------------------
; RevertLineStatus
;
; Reverts last change to line status bit string.
;-------------------------------------------------------------------------------
RevertLineStatus proc USES eax
	mov eax, lineStatus[TYPE lineStatus]
	shld lineStatus[0], eax, 1
	shl lineStatus[TYPE lineStatus], 1
	ret
RevertLineStatus endp


;-------------------------------------------------------------------------------
; ClearLineStatus
;
; Sets line status bit string to zeros.
;-------------------------------------------------------------------------------
ClearLineStatus proc USES eax
	mov ecx, LENGTHOF lineStatus - 1
StatusClearing:
	mov lineStatus[ecx * TYPE lineStatus], 0
	loop StatusClearing
	mov lineStatus[ecx * TYPE lineStatus], 0

	ret
ClearLineStatus endp


;-------------------------------------------------------------------------------
; CheckLineStatus
;
; Reverts last change to line status bit string.
; Recieves: EBX = left bound of typing prompt
; Returns : CY = 0 if line not completely correct
;			CY = 1 if line is completely correct
;-------------------------------------------------------------------------------
CheckLineStatus proc USES eax ebx ecx edx
	mov ecx, typingPromptSize
	sub ecx, ebx
	mov edx, 0		; Counter for how many times rotated

	cmp ecx, LINE_LENGTH
	jbe L_LineCheck
	mov ecx, LINE_LENGTH

L_LineCheck:
	mov eax, lineStatus[0]
	shld lineStatus[TYPE lineStatus], eax, 1
	rcl lineStatus[0], 1
	inc edx
	jnc IncorrectChar
	loop L_LineCheck

	mov edi, 1
	jmp ReturnBits

IncorrectChar:
	mov edi, 0

ReturnBits:
	mov ecx, edx
L_ReturnBits:
	mov eax, lineStatus[TYPE lineStatus]
	shrd lineStatus[0], eax, 1
	rcr lineStatus[TYPE lineStatus], 1
	loop L_ReturnBits

	cmp edi, 1
	jne LineIsIncorrect
	stc
	jmp LineIsCorrect

LineIsIncorrect:
	clc
LineIsCorrect:
	ret
CheckLineStatus endp


end main