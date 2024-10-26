;┌───────────────────────────────┐
;│░█▄█░█▀█░▀█▀░█▀█░░░░█▀█░█▀▀░█▄█│
;│░█░█░█▀█░░█░░█░█░░░░█▀█░▀▀█░█░█│
;│░▀░▀░▀░▀░▀▀▀░▀░▀░▀░░▀░▀░▀▀▀░▀░▀│
;│░@student░Akeem░Morgan░░░░░░░░░│
;│░@student░no░N00427948░░░░░░░░░│
;└───────────────────────────────┘

; General Constants
.equ CLOSED = 0
.equ OPEN = 1
.equ ON = 1
.equ OFF = 0
.equ YES = 1
.equ NO = 0
.equ JCTR = 125 			; Joystick center value

; States
.equ STARTS = 0
.equ IDLES = 1
.equ DATAS = 2
.equ COOKS = 3
.equ SUSPENDS = 4

; Port Pins
.equ	LIGHT	= 7     	; Door Light WHITE LED PORTD pin 7
.equ	TTABLE	= 6			; Turntable PORTD pin 6 PWM
.equ	BEEPER	= 5			; Beeper PORTD pin 5
.equ	CANCEL	= 4			; Cancel switch PORTD pin 4
.equ	DOOR	= 3			; Door latching switch PORTD pin 3
.equ	STSP	= 2			; Start/Stop switch PORTD pin 2
.equ	HEATER	= 0			; Heater RED LED PORTB pin 0

.nolist
.include "m328Pdef.inc"		; Include header file
.list

; S R A M
.dseg
.org SRAM_START
; Global Data (variables; requires memory)
.dseg
cstate:		.byte 1			; Current State (reserved at 0x100)
inputs:		.byte 1			; Current input settings
joyx:		.byte 1			; Raw joystick x-axis
joyy:		.byte 1			; Raw joystick y-axis
joys:		.byte 1			; Joystick status bits 0-not centred,1- centred
seconds:	.byte 2			; Cook time in seconds (16-bit)
sec1:		.byte 1			; minor tick time (100 ms)
tascii: 	.byte 8 		; itoa_short result

; Code segment Flash
.cseg
.org 	0x0000
jmp		start

; Start after interrupt vector table
.org	0xF6				; 0x0000 to 0x00F5 reserved words for interrupts

; strings to send
cmsg1:		.db "Akeem Morgan,	N00427948,	Time: ",0,0
cmsg2:		.db "	Cook Time: ",0,0
cmsg3:		.db "	State: ",0,0

; .asm includes
.include "iopins.asm"		; moved ...
.include "util.asm"
.include "serialio.asm"
.include "i2c.asm"
.include "rtcds1307.asm"
.include "adc.asm"
.include "andisplay.asm"

start:
	ldi		r16,HIGH(RAMEND)	; Initialize the stack pointer
	out		sph,r16
	ldi		r16,LOW(RAMEND)
	out		spl,r16	
	call	initPorts			; I/O Pin Initialization
	call	initUSART0			; USART Initialization
	call	i2cInit				; I2C Initialization
	call	ds1307Init			; DS1307 Initialization (RTC)
	call	setDS1307			; Set time...?
	call 	initADC				; A/D Converter
	call 	initAN 				; Alphanumeric Display
	jmp		startstate


; Main processing loop
;======================	
loop:
	call	updateTick			; Check the time


; Check the inputs
;==================
	; Is Door open (=0)?	
	sbis	PIND,DOOR			; DOOR = Pin number 3 of Port D
	jmp		suspend
	cbi 	PORTD,LIGHT 		; Light off

	; Is Cancel key pressed (=0)?
	sbic	PIND,CANCEL			; CANCEL = Pin number 4 of Port D
	jmp		ss0
	sbi		PORTD,BEEPER 		; Beeper on
stay:	
	sbis 	PIND,CANCEL
	jmp 	stay
	cbi 	PORTD,BEEPER 		; Beeper off
	jmp 	idle

	; Is Start Stop key pressed (=0)?
ss0:
	lds 	r24,cstate
	sbic	PIND,STSP			; STSP = Pin number 2 of Port D
	jmp 	joy0
	sbi		PORTD,BEEPER 		; Beeper on
wait:	
	sbis 	PIND,STSP
	jmp 	wait
	cbi 	PORTD,BEEPER 		; Beeper off
	cpi 	r24,COOKS
	breq 	jmpToSuspend 		; if the state was COOKS, go to suspend
	lds 	r16,seconds
	cpi 	r16,0 				; Check if cook time is zero
	breq 	zero1
	jmp  	cook
zero1:
	lds 	r16,seconds+1
	brne 	cook
	jmp  	idle

	; Check the joystick
joy0:
	lds 	r24,cstate
	cpi 	r24,COOKS
	breq 	loop
	cbi		PORTB,HEATER		; Heater off
	ldi 	r16,0x00
	out 	OCR0A,r16 			; Motor	off
	call 	joystickInputs
	cpi 	r25,0 				; 0 = not centered, shifted | 1 = centered, not shifted
	breq 	dataentry
	jmp 	loop

jmpToSuspend:
	jmp 	suspend				; moved due to "relative jmp out of reach"

; State routines
;====================
startstate:						
	ldi		r24,STARTS			; Set cstate to STARTS
	sts		cstate,r24			; Start state tasks
	ldi 	r24,0x00
	sts  	sec1,r24			; Set sec1 to 0 
	sts 	seconds,r24 		; Set seconds to 0	
	sts 	seconds+1,r24		; Set seconds+1 to 0 
	jmp		loop
	
idle:
	ldi		r24,IDLES			; Set cstate to IDLES
	sts		cstate,r24			; Do idle state tasks
	cbi		PORTB,HEATER		; Heater off
	sbis	PIND,DOOR			; DOOR = Pin number 3 of Port D (0 = open)
	jmp 	lightOnIdle
	cbi		PORTD,LIGHT			; Light off
	jmp 	continueIdle
lightOnIdle:
	sbi		PORTD,LIGHT 		; Light on 
continueIdle:
	ldi 	r16,0x00
	out 	OCR0A,r16 			; Turn off the motor
	sts 	seconds,r16			; Set seconds to 0 (Clears the cook time)
	sts 	seconds+1,r16		; Set seconds+1 to 0 (Clears the cook time)
	jmp		loop				

cook:
	ldi		r24,COOKS			; Set cstate to COOKS
	sts		cstate,r24			; Do cook state tasks
	cbi		PORTD,LIGHT			; Light off
	sbi		PORTB,HEATER		; Heater on
	ldi 	r16,0x23			; 13% duty cycle
	out 	OCR0A,r16 			; Turn on the motor	
	jmp		loop				

suspend:
	ldi		r24,SUSPENDS		; Set cstate to SUSPENDS
	sts		cstate,r24			; Do suspend state tasks
	cbi		PORTB,HEATER		; Heater off
	cbi		PORTD,BEEPER 		; Beeper off
	ldi 	r16,0x00
	out 	OCR0A,r16 			; Turn off the motor	
	sbis	PIND,DOOR			; DOOR = Pin number 3 of Port D (0 = open)'
	jmp 	lightOnSuspend
	cbi		PORTD,LIGHT			; Light off
	jmp 	continueSuspend
lightOnSuspend:
	sbi		PORTD,LIGHT 		; Light on 
continueSuspend:		
	jmp		loop
	
dataentry:
	ldi 	r24,DATAS 			; Set cstate to DATAS
	sts 	cstate,r24 
	lds 	r26,seconds 		; Get current cook time
	lds 	r27,seconds+1 
	lds 	r21,joyx 
	cpi 	r21,135 			; Check for time increment
	brsh 	de1 
	cpi 	r27,0 				; Check upper byte for 0
	brne 	de0 
	cpi 	r26,0 				; Check lower byte for 0
	breq 	de2 
	cpi 	r26,10 
	brsh 	de0 
	ldi 	r26,0 
	jmp 	de2 
de0: 
	sbiw 	r27:r26,10 			; Decrement cook time by 10 seconds
	jmp 	de2 
de1: 
	adiw 	r27:r26,10 			; Increment cook time by 10 seconds
de2: 
	sts 	seconds,r26 		; Store time
	sts 	seconds+1,r27 
	call 	displayState 
	call 	delay1s 
	call 	joystickInputs 
	lds 	r21,joys 
	cpi 	r21,0 
	breq 	dataentry 			; Do data entry until joystick centred
	ldi 	r24,SUSPENDS 
	sts 	cstate,r24 
	jmp 	loop
	
; Time Tasks
;============
updateTick:
	call 	delay100ms 
	cbi 	PORTD,BEEPER 		; Turn off beeper
	lds 	r22,sec1 			; Get minor tick time
	cpi 	r22,10 				; 10 delays of 100 ms done?
	brne 	ut2 
	ldi 	r22,0 				; Reset minor tick
	sts 	sec1,r22 			; Do 1 second interval tasks
	lds 	r23,cstate 			; Get current state
	cpi 	r23,COOKS 
	brne 	ut1 
	lds 	r26,seconds 		; Get current cook time
	lds 	r27,seconds+1 
	inc 	r26 
	sbiw 	r27:r26,1 			; Decrement cook time by 1 second
	brne 	ut3 
	;jump to idle
	ldi 	r23,IDLES 			; if cook time = 0, turn OFF the HEATER
	sts 	cstate,r23
	cbi 	PORTB,HEATER 		; Heater off
	ldi 	r16,0x00 			; Motor off
	out 	OCR0A,r16 
	jmp 	ut1
ut3: 
	sbiw 	r27:r26,1 			; Decrement/store cook time
	sts 	seconds,r26 
	sts 	seconds+1,r27 
ut1: 
	call 	displayState 
ut2: 
	lds 	r22,sec1 
	inc 	r22 
	sts 	sec1,r22 
	ret

	
; Display Tasks
;===============
displayState:
	call 	newline
	
	; cmsg1
	ldi 	zl,low(cmsg1<<1)		; low byte of cmsg1 to register Z (low)
	ldi 	zh,high(cmsg1<<1)		; high byte of cmsg1 to register Z (high)
	ldi 	r16,1 					; string in program memory
	call 	putsUSART0				; send cmsg1
	
	; display time of day
	call 	displayTOD				; send the time of day HH:MM:SS
	
	; cmsg2
	ldi 	zl,low(cmsg2<<1)		; low byte of cmsg2 to register Z (low)
	ldi 	zh,high(cmsg2<<1)		; high byte of cmsg2 to register Z (high)
	ldi 	r16,1 					; string in program memory
	call 	putsUSART0				; send cmsg2
	
	; display cook time
	call 	displayCookTime 		; display the cook time in 5 digits
	ldi 	zl,low(cmsg3<<1)		; low byte of cmsg3 to register Z (low)
	ldi 	zh,high(cmsg3<<1)		; high byte of cmsg3 to register Z (high)
	ldi 	r16,1 					; string in program memory
	call 	putsUSART0				; send cmsg3
	
	; Sends the current state
	lds 	r16,cstate				; retrieve current state
	ori 	r16,0x30				; ASCII format
	call 	putchUSART0
	ret			

displayTOD:
	; Send to Tera Term	
	; Reading and Sending Hours from the RTC
	ldi 	r25,HOURS_REGISTER		; r25 <= ds1307 Minutes_Register
	call 	ds1307GetDateTime		; Read the hours and return data to R24
	mov 	r17,r24 
 	call 	pBCDToASCII 			; convert to ASCII  
 	mov 	r16,r17 
 	call 	putchUSART0 			; send ASCII character
 	mov 	r16,r18 
 	call 	putchUSART0 			; send ASCII character
 	
 	; Formatting...
 	ldi 	r16,':' 				; send character ‘:’
 	call 	putchUSART0

	; Reading and Sending Minutes from the RTC
	ldi 	r25,MINUTES_REGISTER	; r25 <= ds1307 Minutes_Register
	call 	ds1307GetDateTime		; Read the minutes and return data to R24
	mov 	r17,r24 
 	call 	pBCDToASCII 			; convert to ASCII  
 	mov 	r16,r17 
 	call 	putchUSART0 			; send ASCII character 
 	mov 	r16,r18 
 	call 	putchUSART0 			; send ASCII character
 	
 	; Formatting...
 	ldi 	r16,':' 				; send character ‘:’
 	call 	putchUSART0 

	; Reading and Sending Seconds from the RTC
	ldi 	r25,SECONDS_REGISTER	; r25 <= ds1307 Seconds_Register
	call 	ds1307GetDateTime		; Read the seconds and return data to R24
	mov 	r17,r24 
 	call 	pBCDToASCII 			; convert to ASCII  
 	mov 	r16,r17 
 	call 	putchUSART0 			; send ASCII character 
 	mov 	r16,r18 
 	call 	putchUSART0 			; send ASCII character

 	; Display ToD in IDLES only
 	lds 	r24,cstate 				
 	cpi 	r24,COOKS
 	breq 	tod0
 	cpi 	r24,SUSPENDS
 	breq 	tod0
 	cpi 	r24,DATAS
 	breq 	tod0

 	; Send to alphanumeric display
	ldi		r25,HOURS_REGISTER		; Get current time
	call	ds1307GetDateTime
	mov		r17,r24
	call	pBCDToASCII
	mov		r16,r17
	mov		r15,r18
	ldi		r17,0					; Most significant hours digit.
	call	anWriteDigit
	mov		r16,r15
	ldi		r17,1
	call	anWriteDigit
	mov		r16,r15
	ldi		r25,MINUTES_REGISTER	; Get current time
	call	ds1307GetDateTime
	mov		r17,r24
	call	pBCDToASCII
	mov		r16,r17
	mov		r15,r18
	ldi		r17,2					; Most significant minutes digit.
	call	anWriteDigit
	mov		r16,r15
	ldi		r17,3
	call	anWriteDigit
tod0:
 	ret

displayCookTime:
	; Send to Tera Term	
 	lds 	r16,seconds
 	lds 	r17,seconds+1
 	call 	itoa_short
 	ldi 	r20,0
 	sts 	tascii+5,r20			; 0
 	sts 	tascii+6,r20			; 0
 	sts 	tascii+7,r20			; 0
 	ldi 	zl,low(tascii)			; low byte of tascii to register Z (low)
 	ldi 	zh,high(tascii)			; higher byte of tascii to register Z (high)
	ldi 	r16,0 					; string in RAM
	call 	putsUSART0				; send tascii

	; Display CookTime in COOKS, SUSPENDS, DATAS
	lds 	r24,cstate
	cpi 	r24,COOKS
	breq 	dct1
	cpi 	r24,SUSPENDS
	breq 	dct1
	cpi 	r24,DATAS
	brne 	dct2

	; Send to alphanumeric display
dct1:
	lds		r16,seconds				; Get current timer seconds
	lds		r17,seconds+1
	ldi		r18,60					; 16-bit Divide by 60 seconds to get mm:ss
	ldi		r19,0					; answer = mm, remainder = ss
	call	div1616
	mov		r4,r0					; Save mm in r4
	mov		r5,r2					; Save ss in r5
	mov		r16,r4					; Divide minutes by 10
	ldi		r18,10
	call	div88
	ldi		r16,'0'					; Convert to ASCII
	add		r16,r0					; Division answer is 10's minutes
	ldi		r17,0
	call	anWriteDigit			; Write 10's minutes digit
	ldi		r16,'0'					; Convert ASCII
	add		r16,r2					; Division remainder is 1's minutes
	ldi		r17,1
	call	anWriteDigit			; Write 1's minutes digit
	mov		r16,r5					; Divide seconds by 10
	ldi		r18,10
	call	div88
	ldi		r16,'0'					; Convert to ASCII
	add		r16,r0					; Division answer is 10's seconds
	ldi		r17,2
	call	anWriteDigit			; Write 10's seconds digit
	ldi		r16,'0'					; Convert to ASCII
	add		r16,r2					; Division remainder is 1's seconds
	ldi		r17,3
	call	anWriteDigit			; Write 1's seconds digit
dct2:
	ret

joystickInputs:
	; Save Most Significant 8 bits of Joystick X,Y
	ldi 	r24,0x00 				; Read ch 0 Joystick Y
	call 	readADCch 
	swap 	r25 
	lsl 	r25 
	lsl 	r25 
	lsr 	r24 
	lsr 	r24 
	or 		r24,r25 
	sts 	joyy,r24 
	ldi 	r24,0x01 				; Read ch 1 Joystick X
	call 	readADCch 
	swap 	r25 
	lsl 	r25 
	lsl 	r25 
	lsr 	r24 
	lsr 	r24 
	or 		r24,r25 
	sts 	joyx,r24 
	ldi 	r25,0 					; Not centred
	cpi 	r24,115 
	brlo 	ncx 
	cpi 	r24,135 
	brsh 	ncx 
	ldi 	r25,1 					; Centred
ncx: 
	sts 	joys,r25 
	ret 
;.include "iopins.asm"
;.include "util.asm"