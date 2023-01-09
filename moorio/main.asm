INCLUDE "hardware.inc"

SECTION "Header", ROM0[$100]
    nop
    jr WaitVBlank ; first 4 bytes jump to the code
    ds $150 - @, 0 ; make space for header

WaitVBlank:
    ld a, [rLY]
    cp a, 144
    jp c, WaitVBlank

    ; turn off lcd so we can write to vram and oam
    xor a, a
    ld [rLCDC], a

    ; load dma routine into hram
    ld de, DMARoutine
    ld hl, hOAMDMA
    ld bc, DMARoutineEnd - DMARoutine
    call Memcpy

    ; add background and character tiles to vram

    ; Clear the OAM because it's initialized to a ton of random values 
    xor a, a ; set a to 0, xor is 1 cpu cycle, ld is 2, so it's better to use xor
    ld b, 160 ; how much is left to traverse through oam
    ld hl, wShadowOAM ; start of oam
ClearOam:
    ld [hli], a
    dec b
    jr nz, ClearOam

    ; add all the objects to oam

    ; update oam
    call hOAMDMA

    ; Turn on LCD and enable background and objects
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_OBJON
    ld [rLCDC], a

    ; During the first blank frame, initialize display registers
    ld a, %11100100
    ld [rBGP], a ; set background palette
	ld a, %11100100
	ld [rOBP0], a ; set object palette 0

    ; Enable the VBlank interrupt by writing to interrupt enable register
	ld a, IEF_VBLANK
	ldh [rIE], a

	; Clear the interrupt flags of leftover values so random interrupts don't get called
	xor a, a
	ldh [rIF], a

	; Globally enable interrupts
	ei

	; Initialize joypad vars
	ld [wCurKeys], a
	ld [wNewKeys], a

Main:
    halt ; wait for vblank interrupt
    
    ; your code here

FrameEnd:
    call hOAMDMA ; update oam
    jp Main ; continue the loop

; Copy bytes from one area to another
; @param de: Source
; @param hl: Destination
; @param bc: Length
Memcpy:
	ld a, [de]
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or a, c
	jr nz, Memcpy
	ret


SECTION "OAM DMA Subroutine", ROM0
DMARoutine:
    ld a, HIGH(wShadowOAM)
    ld [rDMA], a ; this starts the dma transfer

    ; wait 160 microseconds for the dma transfer to complete
    ld a, 40 
.wait:
    dec a
    jr nz, .wait
    ret
DMARoutineEnd:


SECTION "Shadow OAM", WRAM0, ALIGN[8]
wShadowOAM:: ds 40 * 4 ; 40 possible sprites, 4 bytes each


SECTION "OAM DMA", HRAM
hOAMDMA:: ds DMARoutineEnd - DMARoutine ; allocate space to put the dma routine into


SECTION "Joypad Variables", WRAM0
wCurKeys: db
wNewKeys: db


; When VBLANK happens, the interrupt will switch execution to what's here
SECTION "VBlank Interrupt", ROM0[$0040]
VBlankInterrupt:
    ; Jump away to another section, since the VBlank interrupt code can only have 8 bytes
    jp VBlankHandler


SECTION "VBlank Handler", ROM0
VBlankHandler:
    ; reti = ei *newline* ret, basically just returning and enabling interrupts
    reti
