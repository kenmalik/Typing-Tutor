; TypingTutor.asm

INCLUDE Irvine32.inc

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

.code
main proc

.data
	typingPrompt BYTE "This is a test typing prompt 123jjj", 0
	endingMsg BYTE "Level complete", 0
	
	charIdx BYTE 0

	characterCorrect BYTE LENGTHOF typingPrompt - 1 DUP(0)

.code
	; Write prompt
	mov eax, black + (white * 16)
	call SetTextColor
	mov edx, OFFSET typingPrompt
	call WriteString
	
	mov dh, 0
	mov dl, 0
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
	
	mov eax, black + (white * 16)  ; Replace the previous char
	call SetTextColor
	movzx esi, charIdx
	mov characterCorrect[esi], 0
	dec charIdx

	mov dl, charIdx                ; Move cursor to previous char
	call Gotoxy

	movzx esi, charIdx             ; Revert color of char (moves cursor forward)
	movzx eax, typingPrompt[esi]
	call WriteChar
	call Gotoxy                    ; Move cursor back to previous char's space
	jmp TypingLoop                 ; Return to loop start

checkCharEqual:
	movzx esi, charIdx
	; Compare input with text
	cmp    al, typingPrompt[esi]
	jne    charNotEqual

	; If character is equal
	mov characterCorrect[esi], 1
	mov eax, white + (green * 16)
	call SetTextColor
	movzx eax, typingPrompt[esi]
	call WriteChar
	jmp finishCheck

charNotEqual:
	mov eax, white + (red * 16)
	call SetTextColor
	movzx eax, typingPrompt[esi]
	call WriteChar

finishCheck:
	inc    charIdx
	; If not finished yet
	cmp    typingPrompt[esi + 1], 0
	jne    TypingLoop

	; When complete
	call Crlf
	mov eax, white + (green * 16)
	call SetTextColor
	call Crlf
	mov edx, OFFSET endingMsg
	call WriteString
	
	call Crlf
	mov edx, OFFSET characterCorrect
	call WriteString

	mov ecx, LENGTHOF characterCorrect
countCorrect:
	cmp characterCorrect[ecx], 1

	; Reset color
	mov eax, white + (black * 16)
	call SetTextColor
		

	invoke ExitProcess,0
main endp
end main