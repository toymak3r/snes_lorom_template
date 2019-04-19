.include "snes.inc"
.include "global.inc"
.smart
.export main, nmi_handler

USE_PSEUDOHIRES = 0
USE_INTERLACE = 0

.segment "ZEROPAGE"
nmis: .res 1
oam_used: .res 2

.segment "BSS"

OAM:   .res 512
OAMHI: .res 512
; OAMHI contains bit 8 of X and the size bit for each sprite.
; It's a bit wasteful of memory, as the 512-byte OAMHI needs to be
; packed by software into 32 bytes before being sent to the PPU, but
; it makes sprite drawing code much simpler.  The OBC1 used in the
; game Metal Combat: Falcon's Revenge performs the same packing
; function in hardware, possibly as a copy protection method.

.segment "CODE"
;;
; Minimalist NMI handler that only acknowledges NMI and signals
; to the main thread that NMI has occurred.
.proc nmi_handler
  seta16
  phb
  phk         ; set data bank to bank 0 (because banks $40-$7D
  plb         ; and $C0-$FF can't reach low memory)
  inc a:nmis
  bit a:NMISTATUS
  plb
  rti
.endproc

;;
; This program doesn't use IRQs either.
.proc irq_handler
  rti
.endproc

.segment "CODE1"
; init.s sends us here
.proc main

  ; In the same way that the CPU of the Commodore 64 computer can
  ; interact with a floppy disk only through the CPU in the 1541 disk
  ; drive, the main CPU of the Super NES can interact with the audio
  ; hardware only through the sound CPU.  When the system turns on,
  ; the sound CPU is running the IPL (initial program load), which is
  ; designed to receive data from the main CPU through communication
  ; ports at $2140-$2143.  Load a program and start it running.
  jsl spc_boot_apu

  jsl load_bg_tiles  ; fill pattern table
  jsl draw_bg        ; fill nametable
  jsl load_player_tiles
  
  phk
  plb
  
  ; Program the PPU for the display mode
  seta8
  stz BGMODE     ; mode 0 (four 2-bit BGs) with 8x8 tiles
  stz BGCHRADDR  ; bg planes 0-1 CHR at $0000
  lda #$4000 >> 13
  sta OBSEL      ; sprite CHR at $4000, sprites are 8x8 and 16x16
  lda #>$6000
  sta NTADDR+0   ; plane 0 nametable at $6000
  sta NTADDR+1   ; plane 1 nametable also at $6000
  ; set up plane 0's scroll
  stz BGSCROLLX+0
  stz BGSCROLLX+0
  lda #$FF
  sta BGSCROLLY+0  ; The PPU displays lines 1-224, so set scroll to
  sta BGSCROLLY+0  ; $FF so that the first displayed line is line 0
  
.if ::USE_PSEUDOHIRES
  ; set up plane 1's scroll, offset by 4 pixels, to show
  ; the half-pixels of pseudohires
  lda #4
  sta BGSCROLLX+2
  stz BGSCROLLX+2
  lda #$FF
  sta BGSCROLLY+2
  sta BGSCROLLY+2
  lda #%00000010   ; enable plane 1 for left halves
  sta BLENDSUB
phbit = SUB_HIRES  ; split horizontal pixels
.else
phbit = 0
.endif

.if ::USE_INTERLACE
ilbit = INTERLACE
.else
ilbit = 0
.endif

  lda #phbit|ilbit
  sta PPURES
  lda #%00010001  ; enable sprites and plane 0
  sta BLENDMAIN
  lda #VBLANK_NMI|AUTOREAD  ; but disable htime/vtime IRQ
  sta PPUNMI

  ; Set up game variables, as if it were the start of a new level.
  stz player_facing
  stz player_dxlo
  lda #184
  sta player_yhi
  setaxy16
  stz player_frame_sub
  lda #48 << 8
  sta player_xlo

forever:

  jsl move_player

  ; Draw the player to a display list in main memory
  setaxy16
  stz oam_used
  jsl draw_player_sprite

  ; Mark remaining sprites as offscreen, then convert sprite size
  ; data from the convenient-to-manipulate format described by
  ; psycopathicteen to the packed format that the PPU actually uses.
  ldx oam_used
  jsl ppu_clear_oam
  jsl ppu_pack_oamhi

  ; Backgrounds and OAM can be modified only during vertical blanking.
  ; Wait for vertical blanking and copy prepared data to OAM.
  jsl ppu_vsync
  jsl ppu_copy_oam
  seta8
  lda #$0F
  sta PPUBRIGHT  ; turn on rendering

  ; wait for control reading to finish
  lda #$01
padwait:
  bit VBLSTATUS
  bne padwait
  stz BGSCROLLX
  stz BGSCROLLX

  jmp forever
.endproc



