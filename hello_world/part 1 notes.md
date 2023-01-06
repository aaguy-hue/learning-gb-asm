# Notes

## Reference
Instruction reference (asm): https://rgbds.gbdev.io/docs/gbz80.7 or `man gbz80`

Hardware.inc, boilerplate: https://rgbds.gbdev.io/

Pandocs (gameboy internals): https://gbdev.io/pandocs/

## Compilation
### Compile With:
```sh
rgbasm -L -o hello-world.o hello-world.asm
rgblink -o hello-world.gb hello-world.o
rgbfix -v -p 0xFF hello-world.gb
```

### Why?
Process: Source code → rgbasm → Object files → rgblink → “Raw” ROM → rgbfix → “Fixed” ROM.

rgbasm is an assembler
 - It generates blocks of code by reading the source and hardware.inc
   - Hardware.inc contains some constants related to hardware
 - Not enough info to make full ROM
 - .o files = object files, intermediary files

rgblink is a linker
 - Take the .o file(s), link them into a single ROM
 - Fill in the missing info
 - after being linked, the ROM is still not yet usable

rgbfix fills in the header
 - The header has info like the game name, gbc compat, etc
 - 3 required fields, nintendo logo, ROM size, and two checksums (header checksum + .gb file checksum)
 - The -v means to make the header valid (add nintendo logo, compute two checksums)
 - The -p 0xFF means to pad ROM to a valid size and put that size in the header

## How are games run?

### How does the console boot?
When booting up, the gameboy runs the boot ROM, which:
 - Reads the nintendo logo
 - Displays the boot animation
 - Checks the logo (anti-piracy, no longer matters due to Sega v. Accolade)
 - Checks the checksum of the header
 - If either of the previous two fail, the boot ROM locks up

### How do games run?
When the console begins, it starts at $0000.

It then runs the boot ROM, a program burned in the CPU.

It does the following:
 - Reads the nintendo logo
 - Displays the boot animation
 - Checks the logo (anti-piracy, no longer matters due to Sega v. Accolade)
 - Checks the checksum of the header
 - If either of the previous two fail, the boot ROM locks up

After all this, the boot ROM shows the gameboy boot-up animation and then
plays a sound.

The boot ROM then hands off control to the game ROM at $00FF.
For this reason, your game starts executing at $0100

When you run asm, each line is executed sequentially.
Eventually, this does something.

## GB Format

### Sections
Sections are contiguous ranges of memory. By default, the place that they end up is not known in advance. You can do something like `rgblink hello-world.o -m hello-world.map` to generate a "map file" that lists the sections.

Sections are not split by RBDS so that means all the instructions go in order!!!

Note that you NEED to put a section at the start or you'll get an error.

Section names can be any string (even blank), but must be unique.
Sections need to specify a memory type as well.

Some sections need to span specific ranges, like the header, so you can specify
a starting address in the HEADER directive rather than having it be random.

### Header
The ROM's header goes from `$0100` to `$014F`

The header contains metadata about the ROM. It is info like the game title, gbc compatibility, size, and 2 checksums.
https://gbdev.io/pandocs/The_Cartridge_Header

Most information in the header was not important on actual hardware, since things like size is determined by the amount of data a cartidge can store, not the header size. This type of info was only used to help Nintendo manufacture games.

The thing is though that this information is VERY important for emulators, since they don't even know what hardware you want to use. The header contains some critical information for emulators.

To ensure that no code goes within the header, you need to reserve space with `ds`.

## Bases and Numbers
rgbds asm has:
 - hex prefix is `$`
 - binary prefix is `%`
 - octal prefix is `&`, but is never used since you usually deal w/ 8-bit nums

You can put underscores between digits if numbers are too long `%10_1010`

## Debugging
Debugging appears to be VERY similar between emulators (at the very least, in emulicious and bgb)

In emulicious, go to `Tools -> Debugger`.

The debugger has some parts.
 - Top right = register viewer (shows CPU and hardware registers)
 - Top left = code viewer  (shows asm code)
 - Bottom left = data viewer ()
 - Bottom right = stack viewer ()

## Hardware
### CPU Registers
CPU Registers = small chunks of memory directly embedded in CPU (game boy has 10 bytes)

They are the CPU's "workspace".

Usually, operations will NOT be performed on data in memory, but rather, on data stored in registers.

**Register Types**
- General Purpose Registers (GPR):
  - Mostly used to store any data
  - Some are special though
  - Game boy CPU has 7 8-bit GPRs: `a`, `b`, `c`, `d`, `e`, `h`, `l`
    - 7-bit = nums up to 255
  - `a` register is accumulator
  - rest of registers are paired up, `bc`, `de`, `hl`
    - Called *register pairs*
    - Each pair is basically acts like a 16-bit register
    - The pairs are not separate, if `b` is `$C0` and `c` is `$DE`, `bc` is `$C0DE`
    - You can modify the pairs, this will also modify the individual registers and vice verca

- Special Purpose Registers:
  - `f` register, stores flags, see comparision section
  - PC (program counter) register, stores the address of the instruction being executed
    - same as the IP (instruction pointer) on other systems
    - see jumps section for more info

### Memory
Memory is made of cells that store numbers (before magnetic disk drives, these cells stored current, which was how numbers were stored).

Memory is a long array of numbers stored in cells.
The Game Boy stores 8-bit numbers in each cell.

**Types of Memory on Game Boy**
- RAM
  - Random Access Memory
  - Volatile Memory
  - Can be written to
- ROM
  - Read Only Memory
  - Volatile Memory
  - Cannot be written to, transistors are literally hardcoded
- Flash Memory
  - Rarely used in game boy games, not very important
  - Non-volatile 
- VRAM (video memory)
  - Stores things like tiles, etc

**Memory Addresses**
Because of reasons below, the CPU has a *memory map* of *logical addresses*/*virtual addresses* to *physical addresses*. Physical addresses are numbers that point to cells on memory chips. Logical addresses are generated by the CPU in the perspective of a program.

Logical addresses don't physically exist, while physical addresses do.

The MMU (memory management unit) maps logical addresses to physical addresses.

The importance of logical addresses are that they allow memory to be contiguous within a program. If logical addresses didn't exist, it would be very hard to program.

The game boy has 16-bit logical addresses, so there are 2^16 logical addresses (these are just numbers and there will be 2^16 possibilities, hence 2^16 addresses). There are only 57760 accessible bytes of physical memory, so you should avoid using the extra 7776 logical addresses.

To make memory addresses easier to access, labels exist.


## Game Logic

### Infinite Loop
At the end of the hello world program, there is the following:
```
Done:
  jp Done
```
This is an infinite loop, it makes sure that the CPU is constantly running our game. Otherwise, it'll execute random parts of memory as if it was code and maybe crash the game.

## Graphics
### Tiles
Since the game boy is very weak, instead of writing tons of pixels, tiles exist.

Tiles are "patterns" that have 8x8 pixels in them. Each of these "patterns", or tiles, have an ID that tilemaps refer to. Note that multiple tiles can have the same ID.

Since you can reuse these tiles, LOTS of memory is saved.

Each pixel stores a single color value. Game boy palettes store 4 colors, you can either use color 0, 1, 2, or 3. As a result, each pixel stores two bits.

For this reason, the game boy has `2 bpp`, or two bits per pixel.

**Tile Encoding**

Since each pixel is 2 bits, each row of 8 pixels is 2 bytes, and each tile is 16 bytes. However, the tiles are encoded pretty weirdly in memory.

Tiles are encoded row-by-row. Let's say that the bits of the pixels in one row are `10 01 11 01 00 11 10 01`. The first bit of each pixel would be `10100110` and the second bits would be `01110101`. Each row is stored with the second bits in front and the first bits afterward, so this row would be encoded as `0111010110100110`.

### Palettes
The tiles store indices for colors, but palettes store what those colors should be. Basically, tiles store an outline while palettes color those in. There are a few palettes. BGP is background palette, OBP0 and OBP1, which are object palette 0 and 1.

The palette is a single byte storing what each index maps to.

In the palette, color 0 is "white", color 1 is "light gray", color 2 is "dark gray", and color 3 is "black".

An example palette is `$E4`, or `%11100100`. If you split it in four groups of two, the last group is color 0, and the first group is color 3.

Changing the palette can make things like transitions and more!

### Tilemaps
The tilemaps are made up of lots of IDs. By putting all these tiles together, you can make a single image!

## Assembly Code
Note that asm code is almost entirely line-by-line.

### Accessing Registers
To access a register, just type in the name of the register. To access a register pair, type in the name of the pair such as `de`.

In order to increment the value in the register after the memory is accessed, you can put a `+` or `i`. For example, you can do `ld [hli], a` to copy `a` into the byte `hl` points to, then increment the value of `hl` by 1.

To decrement the value by 1, you would instead put a `-` or `d`, so something like `ld [hl-], a`.

### Symbols
"'A name attached to a value', usually a number"

- Label
  - Let you attach a name to a byte of memory, so if you put `MyLabel:` at some point in the program, you can put in `MyLabel` in other parts of the program where you would instead put a memory address to refer to that address
- Constant
  - `@` refers to the current memory address
- Macro
- String equate

### Instruction format
Instructions have:
- a mnemonic (their name)
- operands (what they act on)

EX: melt the chocolate and butter in a saucepan, the mnemonic is melt (verb), operands are chocolate and butter (subjects), sentence is the instruction

### Expressions
In RGBDS asm, expressions can be anywhere.


### Constants
Constants are names with values attached to them, so when the assembler makes the game, it replaces constants with actual values.

### Comparison
See the instructions category for different instructions.

When you use `cp`, you subtract the value from `a`, just like `sub`, but you don't store the result.
All it does is set flag then set flags.

Every time an arithmetic operation happens, these flags are all set.

The `f` register has 4 bits, each called a flag.

- Z: Zero bit
  - Set when an operation equals 0
- N: Addition/Subtraction
- H: Half-Carry
- C: Carry
  - Set when an operation overflows or underflows
  - If an operation doesn't do either, this bit is cleared
  - Overflow is when you add two values and get a number *smaller* than what you started with
    - This happens when you do something like adding 220 to 60, which is 280, which is 9 bits when the gb only stores 8 bits, causing the 9th bit to be dropped, making the value 24 and the carry bit will be set
    - AKA you actually do (260 + 60) mod 256
  - Underflow is when you subtract two values and get a number *greater* than what you started with
    - This happens when you do something like subtracting 220 from 60. Similarly to overflow you will do modulo and get 196 bc that's the value of (60 - 220) mod 256

### Using `cp` to compare values:

**Equality:** Check for the zero bit is set, if you do `cp 6` and this it is set, that means a - 6 = 0, which means a == 6

**Inequality:** Check if zero bit is not set

**Less Than:** Check if carry bit is set, If you do `cp 9` and the carry bit is set, then `a` must be less than 9

**Greater Than or Equal to**: Check if carry bit is not set

### Jumps
The PC register stores the address of the currently running instruction.

As the CPU reads instructions, it increments PC, so you go to the next instruction.

Jump instructions write some other value to PC, letting you jump to that part of the program.

`jp` just sets PC to the value of its argument.

`jp` with two arguments performs a conditional jump.
Below are the types of conditions.

| Name        | Mnemonic       |
| ----------- | -------------- |
| Zero        | `z`            |
| Non-zero    | `nz`           |
| Carry       | `c`            |
| Non-carry   | `nc`           |


### Instructions
RHS usually refers to right hand side and LHS is left hand side, aka the two arguments.

**Comments:** Semicolons denote comments, comments -> end of line are ignored by `rgbasm`

**Get Value at Address**:
- Putting brackets around a number gets the value at that address
- EX: `ld a [$C0DE]` copies into a the value at `$C0DE`

Memory:
|   Instruction  |   Mnemonic   |                Effect                |      Example     |           LHS              |           RHS           | Notes |
| -------------- | ------------ | ------------------------------------ | ---------------- | -------------------------- | ----------------------- | ----- |
| Load           | `ld`         | Copy value from RHS to LHS           | `ld a 1`         | Where to copy              | What to copy            | You cannot copy two bytes directly to each other, you need to ld the source byte to a register then that register to the destination byte
| Define Space   | `ds`         | Fill a range of memory with RHS      | `ds $150 - @, 0` | How many bytes to allocate | (optional) what val is each reserved byte set to?

Operations:
|   Instruction  |   Mnemonic   |                Effect                |      Example     | Notes                                        |
| -------------- | ------------ | ------------------------------------ | ---------------- | -------------------------------------------- |
| Increment      | `inc`        | Increment the value of the argument  | `inc bc`         | Doesn't update flags with 16-bit operations since this is reused with things like `[hli]`
| Decrement      | `dec`        | Decrement the value of the argument  | `dec bc`         | Doesn't update flags with 16-bit operations since this is reused with things like `[hld]`
| Add            | `add`        | Add the value of the argument to `a` | `add 5`          |
| Subtract       | `sub`        | Subtract the value of the argument from `a` | `sub 3`   |

Bitwise Operations:
|   Instruction  |   Mnemonic   |                Effect                |      Example     |
| -------------- | ------------ | ------------------------------------ | ---------------- |
| Or             | `or`         | Do a bitwise or of RHS and LHS, store result in LHS  | `or a b`         |

Comparison:
|   Instruction  |   Mnemonic   |                Effect                |      Example     |
| -------------- | ------------ | ------------------------------------ | ---------------- |
| Compare        | `cp`         | Compare value with what `a` contains | `cp 12`          |

Jumping:
|   Instruction    |   Mnemonic   |                Effect                |      Example     |
| ---------------- | ------------ | ------------------------------------ | ---------------- |
| Jump             | `jp`         | Jump execution to a location         | `jp Entrypoint`  |
| Conditional Jump | `jp`         | Jump if LHS condition is true        | `jp nz, Loop`  |
| Jump Relative    | `jr`         | Jump to a location close by          |
| Call             | `call`       | Call a subroutine                    |
| Return           | `ret`        | Return from a subroutine             |


### Directives
Some instructions are for CPU, some for programmer (comments), but directives are for RGBDS when assembling.

Directives:
|  Directive  |                Effect                |      Example                    |         Notes         |
| ----------- | ------------------------------------ | ------------------------        | --------------------- |
| INCLUDE     | Copy paste a file into your file     | `INCLUDE hardware.inc`          | None                  |
| SECTION     | Declare a new section                | `SECTION "Header", ROM0[$100]`  | `[addr]` syntax lets you force the section's starting address to be addr |
