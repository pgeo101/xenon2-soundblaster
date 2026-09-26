# Unified audio and volume implementation

## Shared executable

`XENON2.COM` is a DOS startup selector. It shrinks its allocation, EXECs `X2SB.COM` or `X2GUS.COM`, and returns the driver's exit code. Both drivers EXEC the same `X2GAME.EXE`. Only the selected driver allocates audio resources.

The version-checked patch changes twenty `INT 80h` calls to `INT 81h`, as in the prior builds. File offsets:

```
0D30 0D87 20F7 296C 450B 47A8 47CA 48A2 4911 498C
546E 5474 54F7 5D53 6069 611D 680E 683C 9383 DEBA
```

There is one additional instruction replacement at **file 0x66F3** (runtime main CS:5EF3): `E4 60` (`IN AL,60h`) becomes `CD 82` (`INT 82h`). This is the game's keyboard IRQ handler's scan-code read. Overall, 22 bytes differ from the original: twenty audio operands and two keyboard instruction bytes. The executable's size and relocation table are unchanged.

## Keyboard/volume handler

`volume.inc` is shared by both drivers. Each installs and later restores INT 82h. The handler reads port 60h once, adjusts the appropriate level for set-1 make codes 3Fh/40h/41h/42h (F5/F6/F7/F8), and returns the original scan code for other keys. The four function keys and their break codes return FFh, an ignored break code, so they do not become menu input or reassignable game actions.

The game's IRQ handler still owns keyboard acknowledgement through port 61h and the PIC EOI. No second IRQ1 handler is installed and no BIOS keystrokes are polled. The wrapper preserves registers and flags except AL, matching the original IN instruction's interface. It performs no DOS calls, mixing, or GUS register writes inside the keyboard interrupt.

Volumes are independent integer levels 0..10, initialized to 8, saturating at both ends. Changes are effective while effects/music are already running. They do not alter the music-playing flag or sample positions. INT 81h still replaces the original PC-speaker sound API.

## Sound Blaster scaling

`sb_volume_tables.inc` contains 11 x 256 signed-word rows for music and 11 x 256 for effects. For music byte x and level L, gain is `trunc((x-128)*L/20)`, retaining half-amplitude music headroom at L=10. For signed effect byte x, gain is `trunc(x*L/10)`. Effects were already resampled/scaled by 0.65 during asset generation.

The IRQ mixer chooses the row for each group once per 512-byte refill. A signed 16-bit buffer sums music and up to four effects, then saturates once to 8-bit unsigned PCM. At level zero each row is exactly zero. Lookup tables avoid runtime division per sample. The 1,024-byte DMA ring retains the existing ~47–93 ms buffering latency. Tables add 11,264 bytes of resident data; they contain no original game/audio payload.

`X2AUDIO.PCM` contains 2,105,493 unsigned music bytes followed by 88,909 signed effect bytes. Total 2,194,402 bytes, loaded into 134 EMS pages. The loop boundary remains at the end of the music, not the bank.

## GUS scaling

GUS volume registers are logarithmic. For nonzero L, the driver subtracts `round(-256*log2(L/10))*16` from the base voice volume, flooring underflow to zero. Level zero explicitly writes zero volume. The existing music envelope is scaled at every 50 Hz command update. The base volume of each effect voice is retained; a keyboard-change flag causes all eight effect voices to refresh on the next timer tick, so active sounds change as well as newly started sounds.

The signed sample bank remains 124,496 bytes; 9,580 x 32-byte music command frames occupy 19 EMS pages. GF1 voices 0..3 play music and 4..11 effects, with 14 active chip voices for a 44.1 kHz GF1 clock. PIO upload and the game's existing timer drive playback; no GUS DMA or IRQ is required.

For genuine GF1 compatibility, 8-bit GF1 registers are written byte-wide through base+105h while 16-bit registers retain word writes through base+104h. The driver also sets the 14-voice clock before initializing those voices, following the Gravis SDK ordering. On the tested GUS MAX, these changes correct the high-pitched/noisy music produced by the previous generic word-write path.

One-shot effects additionally re-latch their logarithmic volume immediately after the voice is started. The music path already performs a post-start volume write on its 50 Hz update; without the equivalent SFX write, the tested genuine GUS MAX received the effect requests but kept the effect voices silent. PicoGUS tolerated the earlier sequence.

## Amiga effect provenance

The separate 18-sample effect bank begins at decompressed executable offset **0x2B69C**. Records contain a big-endian byte length, big-endian rate, then signed 8-bit PCM. Initialization is near **0x1AE16**, descriptors near **0x1AF52**, raw dispatch near **0x1B072**. The separate synthesized-effect table near 0x1B392 is not emulated.

DOS sound ID 2 comes from the firing routine near runtime CS:4DF4–4E18; ID 6 follows debris creation near CS:1DD7/1DDD. Amiga debris routines select raw sample 3. The provisional DOS ID 0..24 map is:

```
0,2,0,1,6,4,3,5,6,7,8,9,10,11,12,13,14,15,16,17,2,4,5,7,9
```

ID 0 is ignored. The raw shot sample choice and most non-explosion assignments remain provisional. Both generators use the same mapping.

## Cleanup and scope

Both drivers restore INT 81h/82h, release EMS, restore speaker enable bits, and stop their audio. SB additionally restores its IRQ vector/PIC mask and mono mixer setting; GUS disables its voices/DAC. Neither preserves another application's in-progress sound-card playback. The 29-byte audit includes INT 8/9/0D/0F/81/82, PIC mask, free EMS pages, and largest free DOS allocation.

No on-screen overlay, persistent volume settings, firmware switching, or hardware auto-detection fallback is implemented. The selector chooses only a driver; PicoGUS must be set to that hardware mode before launch.
