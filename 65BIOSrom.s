; Written by Anders Nielsen, 2023
; License: https://creativecommons.org/licenses/by-nc/4.0/legalcode
; Modified by Mariano Luna, 2024
; Version 1.0.1

.feature string_escapes ; Allow c-style string escapes when using ca65
.feature org_per_seg
.feature c_comments

; ZP Variables
I2CRAM = $00
I2CADDR = I2CRAM ; I2C device Address to communicate to
inb     = I2CRAM +1
outb    = I2CRAM +2
xtmp    = I2CRAM +3
stringp = I2CRAM +4 ; (and +5) Pointer to string in mem to print

timer2  = stringp ; We're not going to be printing strings while waiting for timer2
;Stringp +1 free for temp.
mode  = stringp +2 ; mode 0 text echo (ASCII), mode 1 program loading (bin)
rxcnt   = stringp + 3
txcnt   = rxcnt +1
runpnt  = txcnt +1
cursor    = runpnt +2
scroll  = runpnt +3
tflags  = runpnt +4
;serialbuf = runpnt +5 ; Address #14 / 0x0E
serialbuf = $0f

SCL     = 1 ; DRB0 bitmask
SCL_INV = $FE ; Inverted for easy clear bit
SDA     = 2 ; DRB1 bitmask
SDA_INV = $FD

; RIOT Addresses 
RIOT = $80
DRA     = RIOT + $00 ;DRA ('A' side data register)
DDRA    = RIOT + $01 ;DDRA ('A' side data direction register)
DRB     = RIOT + $02 ;DRB ('B' side data register)
DDRB    = RIOT + $03 ;('B' side data direction register)
READTDI = RIOT + $04 ;Read timer (disable interrupt)

WEDGC   = RIOT + $04 ;Write edge-detect control (negative edge-detect,disable interrupt)
RRIFR   = RIOT + $05 ;Read interrupt flag register (bit 7 = timer, bit 6 PA7 edge-detect) Clear PA7 flag
A7PEDI  = RIOT + $05 ;Write edge-detect control (positive edge-detect,disable interrupt)
A7NEEI  = RIOT + $06 ;Write edge-detect control (negative edge-detect, enable interrupt)
A7PEEI  = RIOT + $07 ;Write edge-detect control (positive edge-detect enable interrupt)

; RIOT Timer delay
; The timer counts up to 255 times 
; in 1,8,64 or 1024 T intervals
; where T is a clock cycle (T = 1 microsecond)
READTEI = RIOT + $0C ;Read timer (enable interrupt)
WTD1DI  = RIOT + $14 ; Write timer (divide by 1, disable interrupt)
WTD8DI  = RIOT + $15 ;Write timer (divide by 8, disable interrupt)
WTD64DI = RIOT + $16 ;Write timer (divide by 64, disable interrupt)
WTD1KDI = RIOT + $17 ;Write timer (divide by 1024, disable interrupt)

WTD1EI  = RIOT + $1C ;Write timer (divide by 1, enable interrupt)
WTD8EI  = RIOT + $1D ;Write timer (divide by 8, enable interrupt)
WTD64EI = RIOT + $1E ;Write timer (divide by 64, enable interrupt)
WTD1KEI = RIOT + $1F ;Write timer (divide by 1024, enable interrupt)

; The segment below is for the user code starts at $0f
.segment "USERLAND"
userland:

lda #'@'
jsr ssd1306_sendchar

; Serial echo in Hex
w4serial: 
lda DRA ; Check serial 3c
and #$01 ; 2c
bne w4serial ; 2c
jsr serial_rx ; Get character
jsr printbyte
jmp w4serial

; END User Program
halt:
lda #0
sta mode
jmp welcomemsg ; Get ready for new code

; BIOS Segment START
.segment "RODATA"
.org $F000 ; Not strictly needed with CA65 but shows correct address in listing.txt
nmi:
irq:
reset:
  ; Standard 6502 housekeeping
  cld
  sei 
  ; Set stack pointer
  ldx #$7f 
  txs
  ; Clear Zero Page
  lda #0
  clearzp:
    sta $00,x
    dex
    bne clearzp
  sta $00,x
  ; Initialize Port B
  lda #%10111100  ; Bit 0, 1 are SCL and SDA, bit 6 is input button.
  sta DDRB        ; Set B register direction to #%10111100
  ; Initialize Port A
  lda #%00000110  ; Bit 1 is serial TX (Output) & 2 (CTS)
  sta DDRA
  lda #%11111001  ; Bit 0 is serial RX (input), other bits as inputs also not sure @why
  sta DRA
  jsr qsdelay ; .25s delay
  ; Initialize I2C ssd1306 Display 
  ; The display slave address uses the last bit as R/W# 
  ; so is $78 for write and $79 for read
  ; We save the ssd1306 shited right ($78 >> = $3C) 
  ; to simplify setting the last bit for either read (1) or write (0)
  lda #$3C ; Display Address $78 >> = $3C
  sta I2CADDR
  jsr ssd1306_init
  jsr qsdelay ; .25s delay
  jsr ssd1306_clear
  ; Check if button is pressed
  ; BIT FOOBAR will put bit 7 of FOOBAR's contents into the N flag, 
  ; and bit 6 into the V flag, so you can branch on these without loading first.
  bit DRB ; test bit 6 & 7 
  ; BTN ON = LOW = bit 6 and V is Clear
  bvc welcomemsg ; branch to welcome if BTN ON
  ; BTN Off fallthough to bootloader

bootloader:  ; Start Serial Bootloader
  lda #1
  sta mode
  lda #<ready
  sta stringp
  lda #>ready
  sta stringp+1
  jsr ssd1306_wstring ; Print Ready to load
  clc
  bcc main ; @todo: replace this with a JMP maybe?

welcomemsg: ; Print Welcome Message and 
  lda #<welcome
  sta stringp
  lda #>welcome
  sta stringp+1
  jsr ssd1306_wstring
  ; fallthough to main loop

main:
  ; this shoud be just and 
  ; lda DRB
  ; eor #$80
  ; sta DRB 
  bit DRB     ; LED in bit 7, Check bit 7 clear = led ON
  bpl ledoff  ; branch on plus (negative clear) = LED on, turn it off 
  lda DRB     ; LED off, turn it on
  and #$7f    ; Bit low == ON
  sta DRB
  jmp l71
ledoff:
  lda DRB   ; I could do an DEC DRB here since i branch here when N=0
  ora #$80 ; High == off
  sta DRB
l71:
  lda #244
  ; why is checking here is the button is pressed to clear the screen
  ; bit 7 goes to N and bit 6 goes to V
  bit DRB ; test bit 6 & 7 
  ; BTN ON = LOW = bit 6 is Clear
  bvs quartersecond ;  branch to quartersecond if BTN is OFF = bit 6 is SET
  sta WTD64DI ; 244*64 = 15616 ~= 16ms
  jsr ssd1306_clear ; We only end up here if button is pressed
  bne wait ; BRA
quartersecond:
  sta WTD1KDI ; 244 * 1024 = 249856 ~= quarter second
  bne wait ; BRA @why is always bra? the bit operation will be setting bit 7

; this is here to enable the branching 
gonoserial:
  jmp noserial

; this wait label is the serial routine ??
wait:
  ; Check serial RX 
  lda DRA ;  3 cycles
  and #%11111011 ; CTS low
  sta DRA
  ; check for RX by testing DRA Bit 0
  ; serial TX Start bit is low 
  and #$01 ; 2 cycles
  bne gonoserial ; 2 cycles | if (A && $01) != 0 jump to noserial -- Bit 0 is high
  ; someone is sending data
  tay ; init buffer pointer, A already 0
  sta txcnt
  lda #64 ; RX wait loop below is 16 cycles @ 1 usec each
  sta timer2 ; init timeout counter | 3 cycles 
  rx:
    dec timer2 ; 5 cycles
    beq rxtimeout ; Branch if timeout | 2 cycles (+1 if taken) 
    lda DRA ; Check serial 3 cycles
    and #$01 ; 2 cycles
    bne rx ; Wait for RX until timeout | 2 cycles (+1 if taken) 
  lda #64
  sta timer2 ; Reset timer | 3 cycles 
  gorx: ; This label is not used ??
  jsr serial_rx ; RX byte in A | 6 cycles
  sta serialbuf, y
  cpy #128-25 ; check if er still have space. Leaves 9 bytes for stack
  beq rx_err ; buffer overflow
  iny
  bne rx ; BRA (Y never 0)
  rx_err:
    sty rxcnt
    lda DRA 
    ora #4 ; CTS high to stop TX
    sta DRA
    lda #$13 ; XOFF
    jsr serial_tx ; Inform sender we're out of buffer space
    lda #<overflow
    sta stringp
    lda #>overflow
    sta stringp+1
    jsr ssd1306_wstring
    clc
    bcc tx ; BRA    
rxtimeout: ; Nothing in the RX line
  sty rxcnt
  lda mode ; mode 0 text echo (ASCII), mode 1 program loading (bin)
  beq txt ;  mode = 0 then got to echo
  cmp #1 ; we only have 2 modes so this is a bit redundant
  bne txt ; node NOT 1 so got to echo mode
  ;fallthough to bootloader when mode NOT 0 
  ;Time to parse data instead of ASCII 
  jsr ssd1306_clear 
  lda #<loaded ; display loaded bytes
  sta stringp
  lda #>loaded
  sta stringp+1
  jsr ssd1306_wstring

  lda rxcnt
  jsr printbyte

  lda #<bytes
  sta stringp
  lda #>bytes
  sta stringp+1
  jsr ssd1306_wstring
  ; fallthough

waittorun: ; BIN file loaded 
  jsr qsdelay ; Delay 1 second@todo change this to a loop until BTN is pressed
  jsr qsdelay
  jsr qsdelay
  jsr qsdelay
  jsr ssd1306_clear 
  lda #0
  sta cursor
  jsr ssd1306_setline
  lda #0
  jsr ssd1306_setcolumn

  ;lda #<userland
  ;sta runpnt
  ;lda #>userland
  ;sta runpnt+1

  ;jmp (runpnt)
  jmp userland

; Text echo mode: serial RX is printed to the OLED in ASCII
txt:
  lda DRA ;
  ora #4 ; CTS high
  sta DRA
  lda #$13 ; XOFF
  jsr serial_tx ; Inform sender to chill while we write stuff to screen

tx:
  ldy txcnt
  bne notfirst ; not the first character
  lda serialbuf, y
  cmp #$01 ; Check for SOH = SOH as the first char will force bootloader mode
  bne notfirst
  sta mode ; set bootloader mode (mode = 1)
  jmp main ; Got a start main routine in bootloader mode, character (SOH) via serial
notfirst: ; Not the first byte just add it to the buffer
  cpy rxcnt ; ?? @why
  beq txdone ; @check did we loop
  lda serialbuf, y
  jsr ssd1306_sendchar ; echo the RX char to the screen
  inc txcnt
  jmp tx

; Nothing in the RX port
noserial:
lda READTDI
bne gowait ; Loop until timer runs out
jmp main ; loop

txdone: ; TX is complete set CTS and XON
  lda DRA ;
  and #$fb ; CTS low
  sta DRA
  lda #$11 ; XON
  jsr serial_tx
  
gowait:
  jmp wait

; Messages
; Display Width 16 characters
; "         1111111"
; "1234567890123456"
; "XXXXXXXXXXXXXXXX"
ready:
.asciiz "Ready to load code... "

loading:
.asciiz "Loading... "

overflow:
.asciiz "OF!"

loaded:
.asciiz "Loaded "

bytes:
.asciiz " bytes of data. Running code in 1 second."

welcome:
.byte "Hi!             I'm the 65uino! I'm a 6502 baseddev board. Come learn everything about me!"
.byte $00

;Routines

i2c_start:
  lda I2CADDR
  rol ; Shift in carry
  sta outb ; Save addr + r/w bit

  ; Start with SCL as input HIGH - that way we can inc/dec from here
  lda #SCL_INV
  and DDRB
  sta DDRB 

  ; Ensure SDA is output low before SCL is LOW
  lda #SDA 
  ora DDRB
  sta DDRB
  lda #SDA_INV
  and DRB
  sta DRB

  lda #SCL_INV ; Ensure SCL is low when it turns to output
  and DRB
  sta DRB
  inc DDRB ; Set to output by incrementing the direction register == OUT, LOW

  ; Fall through to send address + RW bit
  ; After a start condition we always send the address byte so we don't need to RTS+JSR again here

i2cbyteout: ; Clears outb
  lda #SDA_INV ; In case this is a data byte we set SDA LOW
  and DRB
  sta DRB
  ldx #8    ; We will transmit 8 bits 
  bne first ; BRA - skip INC since first time already out, low
I2Cbyteloop:
  inc DDRB  ; SCL out, low
first:
  asl outb  ; MSB to carry
  bcc seti2cbit0 ; If bit was low
  lda DDRB       ; else set it high
  and #SDA_INV
  sta DDRB
  bcs wasone ; BRA doesn't exist on 6507
seti2cbit0:
  lda DDRB
  ora #SDA
  sta DDRB
  wasone:
  dec DDRB
  dex
  bne I2Cbyteloop

  inc DDRB

  lda DDRB ; Set SDA to INPUT (HIGH)
  and #SDA_INV
  sta DDRB

  dec DDRB ; Clock high
  lda DRB  ; Check ACK bit
  sec
  and #SDA
  bne nack
  clc ; Clear carry on ACK
  nack:
  inc DDRB ; SCL low
  rts

i2cbytein:
  ; Assume SCL is low from address byte
  lda DDRB  ; SDA, input
  and #SDA_INV
  sta DDRB
  lda #0
  sta inb
  ldx #8
i2cbyteinloop:
  clc
  dec DDRB ; SCL HIGH
  lda DRB ; Let's read after SCL goes high
  and #SDA
  beq got0
  sec
  got0:
  rol inb ; Shift bit into the input byte
  inc DDRB ; SCL LOW
  dex
  bne i2cbyteinloop

  lda DDRB ; Send NACK == SDA high (only single bytes for now)
  and #SDA_INV
  sta DDRB
  dec DDRB ; SCL HIGH
  inc DDRB ; SCL LOW
  rts

i2c_stop:
  lda DDRB ; SDA low
  ora #SDA
  sta DDRB
  dec DDRB ; SCL HIGH
  lda DDRB ; Set SDA high after SCL == Stop condition
  and #SDA_INV
  sta DDRB
  rts

ssd1306_init:
  clc
  jsr i2c_start
  ldy #0
  initloop:
  lda ssd1306_inittab, y
  cmp #$ff
  beq init_done
  sta outb
  jsr i2cbyteout
  iny
  bne initloop ; BRA
  init_done:
  jsr i2c_stop
  rts

ssd1306_clear:
  lda #0
  sta cursor
  sta tflags ; Reset scroll
  jsr ssd1306_setline
  lda #0
  jsr ssd1306_setcolumn
  clc ; Write
  jsr i2c_start
  lda #$40 ; Co bit 0, D/C# 1
  sta outb
  jsr i2cbyteout
  ;outb is already 0
  ldy #0
  clearcolumn:
  jsr i2cbyteout
  jsr i2cbyteout
  jsr i2cbyteout
  jsr i2cbyteout
  dey
  bne clearcolumn ; Inner loop
  jsr i2c_stop

  lda #$d3 ; Clear scroll
  jsr ssd1306_cmd
  lda #0
  sta scroll
  sta outb
  jsr i2cbyteout
  jsr i2c_stop
  return:
  rts

gonewline:
jmp newline

ssd1306_sendchar:
cmp #$0D ; Newline
beq gonewline
cmp #$0A ; CR - also newline
beq gonewline
cmp #$08 ; Backspace
beq backspace
cmp #$7f ; Delete - also backspace
beq backspace
cmp #$0C ; Form feed, CTRL+L on your keyboard.
bne startprint
;jsr ssd1306_clear
rts
startprint:
tay ; Save out byte
clc ; Write
jsr i2c_start
lda #$40 ; Co bit 0, D/C 1
sta outb
jsr i2cbyteout
;outb already 0
jsr i2cbyteout ; Send 0
lda fontc1-$20, y ; Get font column pixels
sta outb
jsr i2cbyteout
lda fontc2-$20, y ; Get font column pixels
sta outb
jsr i2cbyteout
lda fontc3-$20, y ; Get font column pixels
sta outb
jsr i2cbyteout
lda fontc4-$20, y ; Get font column pixels
sta outb
jsr i2cbyteout
lda fontc5-$20, y ; Get font column pixels
sta outb
jsr i2cbyteout
jsr i2cbyteout ; Send 0
jsr i2cbyteout ; Send 0
jsr i2c_stop
;tya
;jsr serial_tx
lda cursor
clc
adc #1
and #127
sta cursor

lda scroll
asl ; Convert scroll offset to cursor count - units. 8 << 2 == 16 == Second line
clc ; Need this?
adc cursor
and #$7F ; Throw away only the top bit since scroll offset might have it set

bne l451 ; Again - not taking scroll offset into account..
lda #1 ; We reached wraparound so we start scrolling
sta tflags ; Terminal flags
l451:
lda cursor
and #$0F ; Check if we started a new line and need to reset cursor position.
bne nonewline
jsr ssd1306_setcolumn
lda tflags ; Check scroll flag
beq nonewline
jsr ssd1306_scrolldown
nonewline:
rts

backspace:
;jsr serial_tx ; Echo back the backspace/del
lda cursor
bne noroll ; No roll back to 127
lda #128
noroll:
sec
sbc #1
sta cursor ; Save
and #$0F ; Discard page
cmp #$0F ; Wrapped back a line
bne nocolwrap
ldy #0
sty tflags ; Scroll off
nocolwrap:
jsr ssd1306_setcolumn ; Set new column
lda cursor
lsr
lsr
lsr
lsr ; Shift bits to get current line (16 chars per line == first four bits = character = next three bits line)
jsr ssd1306_setline

clc ; Write
jsr i2c_start
lda #$40 ; Co bit 0, D/C 1
sta outb
ldy #9
send0:
jsr i2cbyteout ; cmd byte + 8 x Send 0
dey
bne send0
jsr i2c_stop

lda cursor
and #$0F ; Discard page
jsr ssd1306_setcolumn ; Set new column
lda cursor
lsr
lsr
lsr
lsr ; Shift bits to get current line (16 chars per line == first four bits = character = next three bits line)
jsr ssd1306_setline
zeropos:
rts

newline:
;jsr serial_tx ; Echo the newline
lda cursor
adc #16
and #$70 ; Ensure range - ignore character position
sta cursor
lda scroll
asl ; Convert scroll offset to cursor count - units. 8 << 2 == 16 == Second line
clc ; Need this?
adc cursor
and #$70 ; Throw away top bit since scroll offset might have it set
bne nowrap ; Now factoring in scroll offset!
ldy #1
sty tflags
nowrap:
lda cursor
lsr
lsr
lsr
lsr ; Shift bits to get current line (16 chars per line == first four bits = character = next three bits line)
jsr ssd1306_setline
lda #0
jsr ssd1306_setcolumn ; CR
lda tflags
beq notscrolling
jsr ssd1306_scrolldown
notscrolling:
rts

ssd1306_scrolldown:
  lda #$d3
  jsr ssd1306_cmd
  lda scroll
  adc #8 ; Doesn't care about bits 6+7
  sta scroll
  sta outb
  jsr i2cbyteout
  jsr i2c_stop

  clc ; Write
  jsr i2c_start
  lda #$40 ; Co bit 0, D/C 1
  sta outb
  ldy #128 ; Command byte + One line/page... Writing the last column might increase the page pointer..
  ; And the last column should always be clear anyway, so 128 instead of 129 so we don't reset to the first
  ;column on the wrong page.
sendblanks:
  jsr i2cbyteout ; Send 0
  dey
  bne sendblanks
  jsr i2c_stop
  jsr ssd1306_resetcolumn ; Column always 0 after scroll
  rts

ssd1306_resetcolumn:
  lda #$21 ; Set column command (0-127)
  jsr ssd1306_cmd
  jsr i2cbyteout ; outb already 0
  lda #$7f ; 127
  sta outb
  jsr i2cbyteout
  jsr i2c_stop
  rts

ssd1306_setcolumn:
  asl ; 15 >> >> >> 120
  asl
  asl
  pha
  lda #$21 ; Set column command (0-127)
  jsr ssd1306_cmd
  pla
  sta outb
  jsr i2cbyteout
  lda #$7f ; 127
  sta outb
  jsr i2cbyteout
  jsr i2c_stop
  rts

;Takes line(page) in A
ssd1306_setline:
  pha ; Save line
  lda #$22 ; Set page cmd
  jsr ssd1306_cmd
  pla ; Fetch line
  sta outb
  jsr i2cbyteout
  lda #7 ; Ensure range
  sta outb
  jsr i2cbyteout
  jsr i2c_stop
  rts

;Takes command in A
ssd1306_cmd:
  pha ; Save command
  lda #$3c ; SSD1306 address @delete @todo I already should have the address stored
  sta I2CADDR
  clc ;Write flag @why
  jsr i2c_start ; @why should this be started already?
  ;A is 0 == Co = 0, D/C# = 0
  sta outb
  jsr i2cbyteout
  pla ; Fetch command
  sta outb
  jsr i2cbyteout
  rts

serial_wstring:
  ldy #0
  txstringloop:
  lda (stringp),y
  beq sent
  jsr serial_tx
  iny
  bne txstringloop
  jmp sent ; In case of overflow

ssd1306_wstring:
  ldy #0
  stringloop:
    lda (stringp),y
    beq sent
    sty xtmp
    jsr ssd1306_sendchar
    ldy xtmp
    iny
    bne stringloop
  sent:
    rts

; Delay: do nothing for .25 seconds
qsdelay:
  lda #244
  sta WTD1KDI ; 244 * 1024 = 249856 ~= quarter second
  waitqs:
    lda READTDI
    bne waitqs ; Loop until timer runs out
  rts

; jsr = 6 cycles
; sta (zp) = 3 cycles
; (WTD8DI -1) * 8 cycles
; We can ignore branches while timer not 0
;lda (zp) = 3 cycles
; bne = 2 cycles (not taken since timer expired)
; rts = 6 cycles
; = 20 + ((WTD8DI - 1) * 8) cycles

delay_short:
  sta WTD8DI ; Divide by 8 = A contains ticks to delay/8
  shortwait:
    nop; Sample every 8 cycles instead of every 6
    lda READTDI
    bne shortwait
  rts

;Returns byte in A - assumes 9600 baud = ~104us/bit, 1 cycle = 1us (1 MHz)
;We should call this ASAP when RX pin goes low - let's assume it just happened (13 cycles ago)
serial_rx:
  ;Minimum 13 cycles before we get here
  lda #34 ; 1.5 period-ish ; 2 cycles - 15 for 9600 baud, 34 for 4800
  jsr delay_short ; 140c
  ldx #8 ; 2 cycles
  ;149 cycles to get here
  serial_rx_loop: ;103 cycles
    lda DRA ; Read RX bit 0 ; 3 cycles
    lsr ; Shift received bit into carry - in many cases might be safe to just lsr DRA ; 2 cycles
    ror inb ; Rotate into MSB 5 cycles
    lda #22 ; 2 cycles ;9 for 9600 baud, 22 for 4800 baud (add 104us == 104 / 8 = 13)
    jsr delay_short ; Delay until middle of next bit - overhead; 84 cycles
    nop ; 2c
    dex ; 2c
    bne serial_rx_loop ; 3 cycles
  ; Should already be in the middle of the stop bit
  ; We can ignore the actual stop bit and use the time for other things
  ; Received byte in inb
  lda inb ; Put in A
  rts

;Transmit byte in A 
serial_tx:
  sta outb
  lda #$fd ; Inverse bit 1
  and DRA
  sta DRA ; Start bit
  lda #21 ; 2c ; 9600 = 8, 4800 = 21
  jsr delay_short ; 20 + (8-1)*8 = 76c ; Start bit total 104 cycles - 104 cycles measured
  nop ; 2c
  nop ; 2c
  ldx #8 ; 2c
  serial_tx_loop:
  lsr outb ; 5c
  lda DRA ; 3c
  bcc tx0 ; 2/3c
  ora #2 ; TX bit is bit 1 ; 2c
  bcs bitset ; BRA 3c
  tx0:
  nop ; 2c
  and #$fd ; 2c
  bitset:
  sta DRA ; 3c
  ; Delay one period - overhead ; 101c total ; 103c measured
  lda #21 ; 2c ; 9600 8, 4800 21
  jsr delay_short ; 20 + (8-1)*8 = 76c
  dex ; 2c
  bne serial_tx_loop ; 3c
  nop; 2c ; Last bit 98us counted, 100us measured
  nop; 2c
  nop; 2c
  nop; 2c
  lda DRA ;3c
  ora #2 ; 2c
  sta DRA ; Stop bit 3c
  lda #21 ; 2c ; 9600 8, 4800 21
  jsr delay_short
  rts

;Prints A to LCD screen
printbyte:
  pha ; Save A
  jsr bytetoa
  pha
  lda xtmp
  jsr ssd1306_sendchar
  pla
  jsr ssd1306_sendchar
  pla ; Restore A
  rts

; This SR puts LSB in A and MSB in HXH - as ascii using hextoa.
bytetoa: 
    pha
    lsr
    lsr
    lsr
    lsr
    clc
    jsr hextoa
    sta xtmp
    pla
    and #$0F
    jsr hextoa
    rts

hextoa:
  ; wozmon-style
  ;    and #%00001111  
  ; Mask LSD for hex print.
  ; Already masked when we get here.
  ora #'0'        ; Add '0'.
  cmp #'9'+1      ; Is it a decimal digit?
  bcc ascr        ; Yes, output it.
  adc #$06        ; Add offset for letter.
  ascr:
      rts


; Display initialization commands ends with $FF
ssd1306_inittab:
  .byte $ae   ; Turn off display
  .byte $d5   ; set display clock divider
  .byte $f0   ; 0x80 default - $f0 is faster for less tearing
  .byte $a8   ; set multiplex
  .byte $3f   ; for 128x64
  .byte $40   ; Startline 0
  .byte $8d   ; Charge pump
  .byte $14   ; VCCstate 14
  .byte $a1   ; Segment remap
  .byte $c8   ; Com output scan direction
  .byte $20   ; Memory mode
  .byte $00   ;
  .byte $da   ; Com-pins
  .byte $12
  .byte $fe   ; Set contrast - full power!
  .byte $7f   ; About half
  .byte $d9   ; Set precharge
  .byte $11   ; VCC state 11
  .byte $a4   ; Display all on resume
  .byte $af   ; Display on
  .byte $b0, $10, $00 ; Page 0, column 0.
  .byte $ff ; Stop byte

; Include the font file for the display
.include "./95char5x7font.s" 

.segment "VECTORS6502"
.ORG $fffa
.word nmi,reset,irq
.reloc
