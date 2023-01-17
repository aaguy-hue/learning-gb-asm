INCLUDE "include/hardware.inc"

SECTION "Header", ROM0[$100]

    jr EntryPoint

    ds $150 - @, 0 ; make space for header

EntryPoint:
    ; Turn on sound
    ld a, %11111111
    ld [rAUDENA], a

    ; Don't turn the LCD off before VBLANK
WaitVBlank:
    ; keep looping while the scanline is less than 144, greater than 144 means that it's vblank so we can break out of the loop and turn off the LCD
    ; https://invisibleup.neocities.org/articles/18/
    ld a, [rLY]
    cp 144
    jr c, WaitVBlank
    
    ; Turn off the LCD so we can write to VRAM (you can't write to VRAM when the LCD is on)
    xor a, a
    ld [rLCDC], a

    ; Copy DMA routine to HRAM
    ; I can write another copy loop and use ldh instead to make things more optimal, but it adds a little more complexity to the code and is probably not necessary
    ld de, DMARoutine
    ld hl, hOAMDMA
    ld bc, DMARoutineEnd - DMARoutine
    call Memcpy

    ; Copy the tile data
    ld de, BgTiles ; de is the starting address of where the tiles are defined
    ld hl, _VRAM + $1000 ; hl is the address we'll copy the tiles to, we'll start by copying to $9000 and continuing to $9001, $9002, etc
    ld bc, BgTilesEnd - BgTiles ; bc is how many bytes to copy
    call Memcpy
    
    ; Copy the paddle tile
    ld de, Sprites.paddle ; Address of paddle data
    ld hl, _VRAM ; Where to copy paddle tiles to
    ld bc, Sprites.paddleEnd - Sprites.paddle ; how much data to copy
    call Memcpy
    
    ; Copy the ball tile
    ld de, Sprites.ball ; src
    ld hl, _VRAM + $10 ; dest
    ld bc, Sprites.ballEnd - Sprites.ball ; len
    call Memcpy

    ; Clear the OAM because it's initialized to a ton of random values 
    xor a, a ; set a to 0, xor is 1 cpu cycle, ld is 2, so it's better to use xor
    ld b, 160 ; how much is left to traverse through oam
    ld hl, wShadowOAM ; start of oam
ClearOam:
    ld [hli], a
    dec b
    jr nz, ClearOam

    ; Create the paddle
    ld hl, wShadowOAM ; start of oam
    xor a, a
    ld [hli], a ; y = 128
    ld [hli], a ; x = 40
    ld [hli], a ; tile id = 0
    ld [hli], a ; don't set any attrs

    ; Create the ball
    ld [hli], a ; y = 100
    ld [hli], a ; x = 16
    inc a
    ld [hli], a ; tile id = 1
    xor a, a
    ld [hl], a ; don't set any flags

    ; Update OAM
    call hOAMDMA

    ; Enable the VBlank interrupt by writing to interrupt enable register
    ld a, IEF_VBLANK
    ldh [rIE], a

    ; Clear the interrupt flags of leftover values so random interrupts don't get called
    xor a, a
    ldh [rIF], a

    ; Globally enable interrupts
    ei

    ; Initialize variables
    ld [wCurKeys], a
    ld [wNewKeys], a

    jp Title

    
TitleInit:
    halt
    
    ; Turn off the LCD (we do this only if we're resetting, otherwise it's already off at the start)
    xor a, a
    ld [rLCDC], a

    ; Hide ball & paddle
    xor a, a
    ld [wShadowOAM], a
    ld [wShadowOAM + 1], a
    ld [wShadowOAM + 4], a
    ld [wShadowOAM + 5], a
    call hOAMDMA

Title:
    ld de, TitleTileMap
    ld hl, _SCRN0
    ld bc, TitleTileMapEnd - TitleTileMap
    call Memcpy

    ; Turn on LCD and enable background and objects
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_OBJON
    ld [rLCDC], a

    ; During the first blank frame, initialize display registers
    ld a, %11100100
    ld [rBGP], a ; set background palette
    ld [rOBP0], a ; set object palette 0

TitleLoop:
    halt
    call Input

    ld a, [wCurKeys]
    bit 3, a
    jp z, TitleLoop

GameInit:
    halt

    ; Turn off the LCD so we have free VRAM access
    xor a, a
    ld [rLCDC], a

    ; Initialize ball count
    ld a, 3
    ld [wBallCount], a

    ; Initialize ball speed
    ld a, 1
    ld [wBallSpeedX], a
    ld [wBallSpeedY], a

    ; Copy the tilemap to VRAM
    ld de, GameTileMap ; start of data
    ld hl, _SCRN0 ; where to copy data to
    ld bc, GameTileMapEnd - GameTileMap ; how much data
    call Memcpy

    
GameReset:
    call UpdateBallCount
    ; Put the paddle in the center
    ld a, 128 + 16
    ld [wShadowOAM], a
    ld a, 40 + 8
    ld [wShadowOAM + 1], a

    ; Put the ball in the center
    ld a, 100 + 16
    ld [wShadowOAM + 4], a
    ld a, 16 + 8
    ld [wShadowOAM + 5], a

    call hOAMDMA

    ; Turn on the LCD
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_OBJON
    ld [rLCDC], a

GameLoop: ; main loop
    ; Cycle of: VBLANK happens -> run instructions -> wait for VBLANK again, then repeat
    halt ; wait until interrupt (only vblank is enabled)

    ; Check the current keys EACH FRAME
    call Input

    ; Process input
    ; Check if left button pressed
.check_left:
    ld a, [wCurKeys]
    bit 5, a ; see if the bit for left is 1
    jp z, .check_right ; if it's not set, check for right

; What to do if left button pressed
.process_left:
    ; decrement the x value
    ld a, [wShadowOAM + 1]
    dec a

    ; if we're at the end of the playable screen, do nothing, else move left
    cp a, 15
    jp z, .paddle_end
    ld [wShadowOAM + 1], a

    ; exit func
    jp .paddle_end

; Check if right button pressed
.check_right:
    ld a, [wCurKeys]
    bit 4, a
    jp z, .paddle_end

; What to do if right button pressed
.process_right:
    ; increment the x value
    ld a, [wShadowOAM + 1]
    inc a

    ; see if we're at the end of the playable area, if so, do nothing, else move right
    cp a, 105
    jp z, .paddle_end
    ld [wShadowOAM + 1], a

.paddle_end

    ; Check for collisions between the ball and walls
WallXCollision:
    ld a, [wShadowOAM + 5]
    cp a, 15
    jp z, WallCollideX
    cp a, 105
    jp c, WallYCollision

WallCollideX:
    call BounceX
    jp PaddleCollision
    
WallYCollision:
    ld a, [wShadowOAM + 4]
    cp a, 23
    call z, BounceY
    cp a, 146 ; 144 + a little more to make it touch the grass
    jp nc, Reset ; you would lose in this case
    ; call nc, BounceY

PaddleCollision:
    ; Check for collisions between the ball and paddle
    ld a, [wShadowOAM + 0] ; check the y
    ld hl, wShadowOAM + 4
    sub a, [hl]
    cp a, -7 ; check if it's between the top (check if higher than center + 3)
    jp nc, XCheck
    cp a, 7 ; or the bottom (check if lower than or at center + 3, 3 means it slightly goes inside the paddle but it looks less weird than 8)
    jp nc, BrickCollision
XCheck:
    ld a, [wShadowOAM + 1] ; check the x
    ld hl, wShadowOAM + 5
    sub a, [hl]
    cp a, -5 ; check if it's between the left side (check if left of center)
    jp nc, Collide
    cp a, 5 ; or the right side (check if right of center or at center)
    jp nc, BrickCollision

Collide:
    ; If there's a collision, make the speed the opposite
    call BounceX
    call BounceY
    call Sounds.hit

BrickCollision:
    ; Check for collisions between the ball and bricks
    ld a, [wShadowOAM + 4]
    ld e, a ; e = y
    ld a, [wShadowOAM + 5]
    ld c, a ; c = x

    inc e
    call IsBrick ; check above
    cp a, 0
    jp nz, BrickCollisionY

    inc c
    call IsBrick ; check diagonal top right
    cp a, 0
    jp nz, BrickCollisionDiagonal
    
    dec e
    call IsBrick ; check right
    cp a, 0
    jp nz, BrickCollisionSide

    dec e
    call IsBrick ; check diagonal bottom right
    cp a, 0
    jp nz, BrickCollisionDiagonal

    dec c
    call IsBrick ; check below
    cp a, 0
    jp nz, BrickCollisionY

    dec c
    call IsBrick ; check diagonal bottom left
    cp a, 0
    jp nz, BrickCollisionDiagonal
    
    inc e
    call IsBrick ; check left
    cp a, 0
    jp z, CollisionEnd

BrickCollisionDiagonal:
    push af ; save the isbrick return value
    call BounceX
    call BounceY
    jp BrickCollided

BrickCollisionSide:
    push af ; save the isbrick return value
    call BounceX
    jp BrickCollided

BrickCollisionY:
    push af ; save the isbrick return value
    call BounceY

BrickCollided:
    call Sounds.hit
    pop af
    cp a, 1
    jp z, BrickLeftDisappear
    jp BrickRightDisappear

BrickRightDisappear:
    ; make the brick disappear
    ld [hl], $08
    dec hl
    ld [hl], $08
    jp CollisionEnd

BrickLeftDisappear:
    ; make the brick disappear
    ld [hl], $08
    inc hl
    ld [hl], $08

CollisionEnd:
    ; Update the ball
    call UpdateBall

FrameEnd:
    ; Initiate OAM DMA transfer
    call hOAMDMA

    ; Continue the loop
    jp GameLoop


; Get input from the user
Input:
    ; Poll half the controller
    ld a, P1F_GET_BTN
    call .onenibble
    ld b, a ; B7-4 = 1; B3-0 = unpressed buttons
    
    ; Poll the other half
    ld a, P1F_GET_DPAD
    call .onenibble
    swap a ; A3-0 = unpressed directions; A7-4 = 1
    xor a, b ; A = pressed buttons + directions
    ld b, a ; B = pressed buttons + directions
  
    ; And release the controller
    ld a, P1F_GET_NONE
    ldh [rP1], a
  
    ; Combine with previous wCurKeys to make wNewKeys
    ld a, [wCurKeys]
    xor a, b ; A = keys that changed state
    and a, b ; A = keys that changed to pressed
    ld [wNewKeys], a
    ld a, b
    ld [wCurKeys], a
    ret
  
  .onenibble
    ldh [rP1], a ; switch the key matrix
    call .knownret ; burn 10 cycles calling a known ret
    ldh a, [rP1] ; ignore value while waiting for the key matrix to settle
    ldh a, [rP1]
    ldh a, [rP1] ; this read counts
    or a, $F0 ; A7-4 = 1; A3-0 = unpressed keys
  .knownret
    ret

; Updates the ball
; No params
UpdateBall:
    ; Move the ball up by the y speed
    ld hl, wBallSpeedY
    ld a, [wShadowOAM + 4]
    add a, [hl]
    ld [wShadowOAM + 4], a
    
    ; Move the ball up by the x speed
    ld hl, wBallSpeedX
    ld a, [wShadowOAM + 5]
    add a, [hl]
    ld [wShadowOAM + 5], a
    
    ret

; Makes the ball x speed the opposite
BounceX:
    ld a, [wBallSpeedX]
    ld b, a
    xor a, a
    sub a, b
    ld [wBallSpeedX], a
    ret
    
; Makes the ball y speed the opposite
BounceY:
    ld a, [wBallSpeedY]
    ld b, a
    xor a, a
    sub a, b
    ld [wBallSpeedY], a
    ret


; updates the ball count
UpdateBallCount:
    ld a, [wBallCount]
    cp a, 3
    jp nz, .two
    ld a, $2D
    ld [_SCRN0 + (TileMapBallCount - GameTileMap)], a
    ret

.two
    ld a, [wBallCount]
    cp a, 2
    jp nz, .one
    ld a, $2C
    ld [_SCRN0 + (TileMapBallCount - GameTileMap)], a
    ret
    
.one
    ld a, [wBallCount]
    cp a, 1
    jp nz, .zero
    ld a, $2B
    ld [_SCRN0 + (TileMapBallCount - GameTileMap)], a
    ret
    
.zero
    ld a, [wBallCount]
    cp a, 0
    ld a, $2A
    ld [_SCRN0 + (TileMapBallCount - GameTileMap)], a
    ret


; Makes the screen black, goes back to title screen if lose, else reduce ball count
Reset:
    
    call Sounds.lose
    
    ld a, [wBallCount]
    sub a, 1
    ld [wBallCount], a
    
    cp a, 0
    jp nz, .wait
    ld a, %1111111
    ld [rBGP], a ; set background palette
    ld [rOBP0], a ; set object palette 0

    call UpdateBallCount

.wait
    ; I probably should have done a loop but um I was lazy
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt
    halt

    ld a, [wBallCount]
    cp a, 0
    jp nz, GameReset

    ld a, 3
    ld [wBallCount], a
    jp TitleInit

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

; ; Copy bytes from one area to another for 1bpp images
; ; @param de: Source
; ; @param hl: Destination
; ; @param bc: Length
; Memcpy1bpp:
;     ld a, [de]
;     ld [hli], a
;     ld [hli], a ; copy twice for 1bpp
;     inc de
;     dec bc
;     ld a, b
;     or a, c
;     jr nz, Memcpy
;     ret

; Get the address of the tile in WRAM from some xy position of the ball
; @param c: the x position of the ball
; @param e: the y position of the ball
; @returns hl: the address of the tile
GetTile:
    ; there is no scroll, so we divide coordinates by tile size (8x8) to get tile coords
    ; use tile coords to check the tilemap

    ; account for the 8x16 offset
    ld a, c
    sub a, 8
    ld c, a

    ld a, e
    sub a, 16
    ld e, a

    ; divide both nums by 8 by right shifting by 3
    sra c
    sra c
    sra c
    sra e
    sra e
    sra e
    
    ; each line has 32 tiles, so we need to multiply y by 32
    ld h, e
    ld e, 32
    call Mul16

    ; then use the x as the offset to get to the correct addr
    ld b, 0
    add hl, bc
    
    ; Then add that to where the tiles are stored
    ld bc, _SCRN0
    add hl, bc
    ret


; Checks if an xy position is a brick
; @param c: the x position of the ball
; @param e: the y position of the ball
; @returns a: 0 if no, 1 if yes and it's the left side, 2 if yes and right side
IsBrick:
    call GetTile

    ; Check if the tile is 6 (right)
    ld a, 5 + 1
    sub a, [hl]
    jp z, .right

    ; Check if the tile is 5 (left)
    cp a, 1
    ret z

    ; return 0 otherwise
    xor a, a
    ret

.right:
    ld a, 2
    ret

Sounds::
; Make a sound when something is hit
.hit::
    ; sound channel 2: pulse
    ld a, %00011111
    ld [rNR21], a ; set waveform + length timer
    ld a, %1111111
    ld [rNR22], a ; set volume
    ld a, %00010011
    ld [rNR23], a ; low 8 bits of wave
    ld a, %11000001
    ld [rNR24], a ; start the sound + high 3 bits of wave
    ret

; button presses on the main menu (menu isn't yet implemented, so this is unused)
.btn_press::
    ; sound channel 1: pulse + sweep
    ld a, %0011011
    ld [rNR10], a ; set sweep
    ld a, %00011111
    ld [rNR11], a ; set waveform + length timer
    ld a, %1111111
    ld [rNR12], a ; set volume
    ld a, %11111111
    ld [rNR13], a ; low 8 bits of wave
    ld a, %11000111
    ld [rNR14], a ; start the sound + high 3 bits of wave
    ret

; Make a beep sound (unused, I just made this since in case I want to use it)
.beep::
    ; sound channel 2: pulse
    ld a, %00011111
    ld [rNR21], a ; set waveform + length timer
    ld a, %1111111
    ld [rNR22], a ; set volume
    ld a, %00000000
    ld [rNR23], a ; low 8 bits of wave
    ld a, %11000100
    ld [rNR24], a ; start the sound + high 3 bits of wave
    ret

; Make a lose sound
.lose::
    ; sound channel 1: pulse w/ wavelength sweep
    ld a, %0111001
    ld [rNR10], a ; set sweep
    ld a, %00000110
    ld [rNR11], a ; set waveform + length timer
    ld a, %1111111
    ld [rNR12], a ; set volume
    ld a, %00100111
    ld [rNR13], a ; low 8 bits of wave
    ld a, %11000010
    ld [rNR14], a ; start the sound + high 3 bits of wave
    ret

; Multiply 2 8-bit numbers (adapted from https://wikiti.brandonw.net/index.php?title=Z80_Routines:Math:Multiplication)
; @param h: number 1
; @param e: number 2
; @returns hl: result
Mul16::
    ld	d, 0
    sla	h
    sbc	a, a
    and	e
    ld	l, a
    
    ld	b, 7
 .loop:
    add	hl, hl
    jr	nc, @+3
    add	hl, de
    
    dec b
    jr nz, .loop
    
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

    ; When VBLANK happens, the interrupt will switch execution to what's here
SECTION "VBlank Interrupt", ROM0[$0040]
VBlankInterrupt:
    ; Jump away to another section, since the VBlank interrupt code can only have 8 bytes
    jp VBlankHandler


SECTION "VBlank Handler", ROM0
VBlankHandler:
    ; reti = ei *newline* ret, basically just returning and enabling interrupts
    reti

SECTION "Tiles", ROM0
BgTiles:
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33322222
    dw `33322222
    dw `33322222
    dw `33322211
    dw `33322211
    dw `33333333
    dw `33333333
    dw `33333333
    dw `22222222
    dw `22222222
    dw `22222222
    dw `11111111
    dw `11111111
    dw `33333333
    dw `33333333
    dw `33333333
    dw `22222333
    dw `22222333
    dw `22222333
    dw `11222333
    dw `11222333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33322211
    dw `33322211
    dw `33322211
    dw `33322211
    dw `33322211
    dw `33322211
    dw `33322211
    dw `33322211
    dw `22222222
    dw `20000000
    dw `20111111
    dw `20111111
    dw `20111111
    dw `20111111
    dw `22222222
    dw `33333333
    dw `22222223
    dw `00000023
    dw `11111123
    dw `11111123
    dw `11111123
    dw `11111123
    dw `22222223
    dw `33333333
    dw `11222333
    dw `11222333
    dw `11222333
    dw `11222333
    dw `11222333
    dw `11222333
    dw `11222333
    dw `11222333
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `11001100
    dw `11111111
    dw `11111111
    dw `21212121
    dw `22222222
    dw `22322232
    dw `23232323
    dw `33333333
    ; Paste your logo here:
    dw `33000000
    dw `33000000
    dw `33000000
    dw `33000000
    dw `33111100
    dw `33111100
    dw `33111111
    dw `33111111
    dw `33331111
    dw `00331111
    dw `00331111
    dw `00331111
    dw `00331111
    dw `00331111
    dw `11331111
    dw `11331111
    dw `11333300
    dw `11113300
    dw `11113300
    dw `11113300
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `00003333
    dw `00000033
    dw `00000033
    dw `00000033
    dw `11000033
    dw `11000033
    dw `11111133
    dw `11111133
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11113311
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `33111111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11331111
    dw `11330000
    dw `11330000
    dw `11330000
    dw `33330000
    dw `11113311
    dw `11113311
    dw `00003311
    dw `00003311
    dw `00003311
    dw `00003311
    dw `00003311
    dw `00333311
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11111133
    dw `11113333
    INCBIN "include/hourglass.2bpp"
BgTilesEnd:

TitleTileMap: ; note to self: only the first 20 are visible w/o scrolling, other 12 tiles only show after scrolling
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $3C, $4C, $3F, $3B, $45, $49, $4F, $4E, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $4A, $6B, $5E, $6C, $6C, $1A, $08, $4D, $4E, $3B, $4C, $4E, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08 ; PRESS START PORTION
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
TitleTileMapEnd:

GameTileMap:
    db $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $02, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $08, $08, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $71
TileMapBallCount: db $2D
    db $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $08, $08, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $0A, $0B, $0C, $0D, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $0E, $0F, $10, $11, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $12, $13, $14, $15, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $16, $17, $18, $19, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
    db $04, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $07, $03, $03, $03, $03, $03, $03, $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
GameTileMapEnd:

Sprites:
.paddle:
    dw `03333330
    dw `30000003
    dw `03333330
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
.paddleEnd:

.ball:
    dw `00000000
    dw `00000000
    dw `00033000
    dw `00311300
    dw `00311300
    dw `00033000
    dw `00000000
    dw `00000000
.ballEnd:

SECTION "Joypad Variables", WRAM0
wCurKeys: db
wNewKeys: db

SECTION "Global Variables", WRAM0
wBallSpeedX: db ; speed x
wBallSpeedY: db ; speed y
wBallCount: db

SECTION "Shadow OAM", WRAM0, ALIGN[8]
wShadowOAM:: ds 40 * 4 ; 40 possible sprites, 4 bytes each


SECTION "OAM DMA", HRAM
hOAMDMA:: ds DMARoutineEnd - DMARoutine ; allocate space to put the dma routine into
