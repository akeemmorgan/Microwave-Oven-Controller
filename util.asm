;┌───────────────────────────────┐
;│░█░█░▀█▀░▀█▀░█░░░░░░█▀█░█▀▀░█▄█│
;│░█░█░░█░░░█░░█░░░░░░█▀█░▀▀█░█░█│
;│░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░░▀░▀░▀▀▀░▀░▀│
;│░@student░Akeem░Morgan░░░░░░░░░│
;│░@student░no░N00427948░░░░░░░░░│
;└───────────────────────────────┘

.def ANSL = R0 		;To hold low-byte of answer
.def ANSH = R1 		;To hold high-byte of answer 
.def REML = R2 		;To hold low-byte of remainder
.def REMH = R3 		;To hold high-byte of remainder
.def AL = R16 		;To hold low-byte of dividend
.def AH = R17 		;To hold high-byte of dividend
.def BL = R18 		;To hold low-byte of divisor
.def BH = R19 		;To hold high-byte of divisor 
.def C16 = R20 		;Bit Counter 

dectab: 
	.dw 10000,1000,100,10,1,0

; 100 ms Delay
delay100ms:
	ldi		r18,0xFF		; 0xFF No sim
	ldi		r24,0xE1		; 0xE1 No sim
	ldi		r25,0x04   		; 0x04 No sim
d100:
	subi	r18,0x01		; 1
	sbci	r24,0x00		; 0
	sbci	r25,0x00		; 0
	brne	d100
	ret

; 1 Second Delay
delay1s:
	ldi		r20,64
d1:	
	ldi		r21,200
d2:	
	ldi		r22,250
d3:	
	nop
	nop
	dec		r22
	brne	d3
	dec		r21
	brne	d2
	dec		r20
	brne	d1
	ret

; Packed BCD To ASCII
; Number to convert in r17
; Converted output in r17 (upper nibble),r18 (lower nibble)
pBCDToASCII:
	; Lower nibble
	mov		r18,r17
	andi	r18,0x0F
	ori		r18,0x30
	
	; Upper nibble
	swap	r17
	andi	r17,0x0F
	ori		r17,0x30
	ret

; Byte To Hexadecimal ASCII
; Number to convert in r17
; Converted output in r17 (lower nibble),r18 (upper nibble)
byteToHexASCII:
	mov		r18, r17			; Save a copy
	andi	r17, 0x0f			; Mask the upper nibble
	ldi		r16, 0x30			; Index to '0'
	cpi		r17, 10
	brlo	b1
	ldi		r16, 0x37			; Index to 'A'
b1:	
	add		r17,r16
	swap	r18					; Look at the upper nibble
	andi	r18,0x0f			; Mask the upper nibble
	ldi		r16,0x30			; Index to '0'
	cpi		r18,10				; Greater than 9?
	brlo	b2
	ldi		r16,0x37			; Index to 'A'
b2:	
	add		r18,r16
	ret

; Converts unsigned integer value of r17:r16 to ASCII string tascii[5]
itoa_short: 
	ldi 	zl,low(dectab*2) 	; pointer to 10^x power compare value
	ldi 	zh,high(dectab*2) 
	ldi 	xl,low(tascii) 		; pointer to array to store string
	ldi 	xh,high(tascii) 
itoa_lext: 
	ldi 	r18,'0'-1 			; (ASCII 0) -1
	lpm 	r2,z+ 				; load 10^x word, point to next
	lpm 	r3,z+ 
itoa_lint: 
	inc 	r18 				; start with '0' ASCII
	sub 	r16,r2 				; (## - 10^x
	sbc 	r17,r3 
	brsh 	itoa_lint 
	add 	r16,r2 				; if negative reconstruct
	adc 	r17,r3 
	st 		x+,r18 				; save 1/10^x count, point to next location to save
	lpm 						; read last ZX pointed at from 10^x table in (r0)
	tst 	r0 					; LAST WORD YET?=0x00
	brne 	itoa_lext 
	ret

; 16-bit Unsigned Division
div1616: 
	movw 	ANSH:ANSL,AH:AL 	; Copy dividend into answer
	ldi 	C16,17 				; Load bit counter
	sub 	REML,REML 			; Clear Remainder and Carry
	clr 	REMH 
dloop: 
	rol 	ANSL 				; Shift the answer to the left
	rol 	ANSH 
	dec 	C16 				; Decrement Counter
	breq 	ddone 				; Exit if sixteen bits done
	rol 	REML 				; Shift remainder to the left
	rol 	REMH 
	sub 	REML,BL 			; Try to subtract divisor from remainder
	sbc 	REMH,BH 
	brcc 	skip 				; If the result was negative then
	add 	REML,BL 			; reverse the subtraction to try again
	adc 	REMH,BH 
	clc 						; Clear Carry Flag so zero shifted into A 
	rjmp 	dloop 				; Loop Back
skip: 
	sec 						; Set Carry Flag to be shifted into A
	rjmp 	dloop 
ddone: 
	ret

; 8-bit Unsigned Division
; r0 holds answer
; r2 holds remainder
; r16 holds dividend
; r18 holds divisor
; r20 Bit Counter
div88: 
	ldi 	r20,9 				; Load bit counter
	sub 	r2,r2 				; Clear remainder and Carry
	mov 	r0,r16 				; Copy dividend to answer
loopd8: 
	rol 	r0 					; Shift answer to left
	dec 	r20 				; Decrement counter
	breq 	doned8 				; Exit if eight bits done
	rol 	r2 					; Shift remainder to the left
	sub 	r2,r18 				; Try to subtract the divsor from remainder
	brcc 	skipd8 				; If result was negative then
	add 	r2,r18 				; reverse subtraction to try again
	clc 						; Clear Carry flag so zero shifted into A
	rjmp 	loopd8 
skipd8: 
	sec 						; Set Carry flag to be shifted into A
	rjmp 	loopd8 
doned8: 
	ret
