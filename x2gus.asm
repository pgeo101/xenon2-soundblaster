; Experimental Xenon II GF1 native sample player. 386+, EMS, 256K GUS.
; Music: four GF1 voices, 50 Hz commands. Effects: eight independent voices.
; PIO sample upload at startup. No GUS DMA/IRQ, no DOS calls in game audio hook.
bits 16
cpu 386
org 100h
jmp start
base dw 0
old81 dd 0
old8 dd 0
hooked db 0
timer_hooked db 0
gus_ready db 0
speaker_bits db 0
ems_handle dw 0ffffh
ems_frame dw 0
ems_pages dw 0
file_handle dw 0ffffh
file_size dd 0
last_status db 0
fill_chunk dw 0
mode db 0
test_duration dw 146
playing db 0
position dw 0
phase dd 0
next_fx db 4
fx_busy times 8 dw 0
music_starts dw 0
music_stops dw 0
fx_count dw 0
fx_invalid dw 0
fx_counts times 25 dw 0
tick_count dd 0
loop_count dd 0
ems_errors dw 0
exec_error dw 0
exit_code db 0
parent_ss dw 0
parent_sp dw 0
saved_ss dw 0
saved_sp dw 0
call_ax dw 0
return_ax dw 0
chain_count db 3
standalone_time dw 0
file_pcm db 'X2GUS.SEQ',0
file_bank db 'X2GUS.BNK',0
file_exe db 'X2GAME.EXE',0
file_log db 'X2GUS.LOG',0
env_name db 'ULTRASND='
empty_tail db 0,13
exec_block dw 0,empty_tail,0,5ch,0,6ch,0
msg_title db 'Xenon II native GUS experimental player',13,10,'Loading music commands into EMS and samples into GF1 RAM...',13,10,'$'
msg_ready db 'GUS ready. Launching X2GAME.EXE.',13,10,'$'
msg_test db 'GUS music/effects test (/TEST: 8 s, /LOOPTEST: 203 s).',13,10,'$'
msg_done db 'GUS voices stopped; memory and vectors restored. See X2GUS.LOG.',13,10,'$'
msg_ems db 'EMS unavailable or insufficient (enable at least 512 KB free EMS).',13,10,'$'
msg_file db 'Missing or invalid X2GUS.SEQ / X2GUS.BNK.',13,10,'$'
msg_gus db 'GUS RAM test failed at ULTRASND base address.',13,10,'$'
msg_config db 'Set ULTRASND for a configured GUS (base 210..260 hex).',13,10,'$'
msg_exec db 'Cannot execute X2GUS.EXE.',13,10,'$'
start:
 cli
 mov ax,cs
 mov ds,ax
 mov es,ax
 mov ss,ax
 mov sp,stack_end
 sti
 cld
 in al,61h
 and al,3
 mov [speaker_bits],al
 mov bx,(resident_end-$$+100h+15)/16
 mov ah,4ah
 int 21h
 jc error_ems
 cmp byte [80h],0
 je .normal
 mov byte [mode],1
 mov al,[83h]
 or al,20h
 cmp al,'l'
 jne .normal
 mov word [test_duration],3700
.normal:
 call parse_env
 jc error_config
 mov dx,msg_title
 call print
 call load_pcm
 jc error_load
 call init_gus
 jc error_gus
 call load_bank
 jc error_file
 mov ax,3581h
 int 21h
 mov [old81],bx
 mov [old81+2],es
 mov ax,2581h
 mov dx,sound_hook
 int 21h
 mov byte [hooked],1
 call install_volume
 push cs
 pop es
 in al,61h
 and al,0fch
 out 61h,al
 cmp byte [mode],0
 jne standalone
 mov dx,msg_ready
 call print
 mov ax,cs
 mov [exec_block+4],ax
 mov [exec_block+8],ax
 mov [exec_block+12],ax
 mov [parent_ss],ss
 mov [parent_sp],sp
 mov bx,exec_block
 mov dx,file_exe
 mov ax,4b00h
 int 21h
 cli
 mov bx,cs
 mov ds,bx
 mov es,bx
 mov ss,[parent_ss]
 mov sp,[parent_sp]
 sti
 jnc finish
 mov [exec_error],ax
 mov dx,msg_exec
 jmp error
standalone:
 mov ax,3508h
 int 21h
 mov [old8],bx
 mov [old8+2],es
 mov ax,2508h
 mov dx,test_timer
 int 21h
 mov byte [timer_hooked],1
 cli
 mov al,36h
 out 43h,al
 mov al,55h
 out 40h,al
 out 40h,al
 sti
 mov dx,msg_test
 call print
 mov ax,0200h
 int 81h
 xor ax,ax
 mov es,ax
 mov bx,[es:046ch]
 mov [standalone_time],bx
.wait:
 mov ax,[es:046ch]
 sub ax,[standalone_time]
 cmp ax,[test_duration]
 jae finish
 cmp ax,36
 jne .boom
 cmp word [fx_count],0
 jne .boom
 mov ax,0302h
 int 81h
.boom:
 mov ax,[es:046ch]
 sub ax,[standalone_time]
 cmp ax,73
 jne .wait
 cmp word [fx_count],1
 jne .wait
 mov ax,0306h
 int 81h
 jmp .wait
error_load:
 cmp byte [last_status],1
 je error_file
error_ems: mov dx,msg_ems
 jmp error
error_file: mov dx,msg_file
 jmp error
error_gus: mov dx,msg_gus
 jmp error
error_config: mov dx,msg_config
error:
 call print
 mov byte [exit_code],1
finish:
 call cleanup
 call write_log
 mov dx,msg_done
 call print
 mov al,[exit_code]
 mov ah,4ch
 int 21h
print:
 mov ah,9
 int 21h
 ret

parse_env:
 mov es,[2ch]
 xor di,di
.next:
 cmp byte [es:di],0
 je .bad
 push di
 mov si,env_name
 mov cx,9
 repe cmpsb
 pop di
 je .found
.skip:
 cmp byte [es:di],0
 lea di,[di+1]
 jne .skip
 jmp .next
.found:
 add di,9
 xor bx,bx
 mov cx,3
.hex:
 mov al,[es:di]
 inc di
 sub al,'0'
 cmp al,9
 ja .bad
 shl bx,4
 movzx ax,al
 or bx,ax
 loop .hex
 cmp byte [es:di],','
 jne .bad
 cmp bx,210h
 jb .bad
 cmp bx,260h
 ja .bad
 test bl,15
 jnz .bad
 mov [base],bx
 push cs
 pop es
 clc
 ret
.bad:
 push cs
 pop es
 stc
 ret

; BX=GF1 16-bit register, AX=value.
reg_write:
 push ax
 push dx
 mov dx,[base]
 add dx,103h
 mov al,bl
 out dx,al
 pop dx
 pop ax
 push dx
 mov dx,[base]
 add dx,104h
 out dx,ax
 pop dx
 ret

; BL=GF1 8-bit register, AL=value. The GUS SDK defines byte-register data at
; base+105h; keep those accesses byte-wide rather than synthesizing them via
; a word write to the 16-bit data port at base+104h.
reg_write8:
 push ax
 push dx
 mov ah,al
 mov dx,[base]
 add dx,103h
 mov al,bl
 out dx,al
 add dx,2
 mov al,ah
 out dx,al
 pop dx
 pop ax
 ret

reg_read:
 push dx
 mov dx,[base]
 add dx,103h
 mov al,bl
 out dx,al
 inc dx
 in ax,dx
 pop dx
 ret
select_voice:
 push dx
 mov dx,[base]
 add dx,102h
 out dx,al
 pop dx
 ret
; At least 4.8 us between writes of GF1 self-modifying control fields.
gf_delay:
 push cx
 push dx
 push ax
 mov dx,[base]
 add dx,107h
 mov cx,16
.loop: in al,dx
 loop .loop
 pop ax
 pop dx
 pop cx
 ret
control_write:
 call reg_write8
 call gf_delay
 call reg_write8
 ret

; The SDK full reset waits ten 4.8us-class delays. gf_delay is deliberately
; conservative (16 ISA reads rather than the SDK's seven), so five calls meet
; or exceed the documented settling window without relying on CPU speed.
gf_reset_delay:
 push cx
 mov cx,5
.loop:
 call gf_delay
 loop .loop
 pop cx
 ret
; EBP=byte address. Preserve AX (sample value).
set_dram:
 push eax
 push bx
 mov eax,ebp
 mov bx,43h
 call reg_write
 shr eax,16
 and al,0fh
 mov bl,44h
 call reg_write8
 pop bx
 pop eax
 ret
init_gus:
 mov bx,4ch
 xor ax,ax
 call reg_write8
 call gf_reset_delay
 mov al,1
 call reg_write8
 call gf_reset_delay
 ; Detect writable RAM before enabling audio. Two locations cover the bank span.
 xor ebp,ebp
 call ram_probe
 jc .bad
 mov ebp,1ffffh
 call ram_probe
 jc .bad
 mov byte [gus_ready],1

 ; Program the GF1 output clock before touching voice state. The original SDK
 ; does this before initializing the active voices; 14 voices gives 44.1 kHz.
 mov bl,0eh
 mov al,0cdh
 call reg_write8

 xor cx,cx
.voices:
 mov al,cl
 call select_voice
 xor bx,bx
 mov al,3
 call control_write
 mov bl,0dh
 mov al,3
 call control_write
 mov bl,9
 xor ax,ax
 call reg_write
 mov bl,0ch
 mov al,7
 call reg_write8
 inc cx
 cmp cx,14
 jb .voices

 mov bl,41h
 xor ax,ax
 call reg_write8
 mov bl,45h
 call reg_write8
 mov bl,49h
 call reg_write8
 mov bl,4ch
 mov al,3 ; run, DAC enabled, GF1 IRQs disabled
 call reg_write8
 mov dx,[base]
 mov al,9 ; line out on, line in off, latches stay enabled
 out dx,al
 clc
 ret
.bad: stc
 ret
ram_probe:
 call set_dram
 mov dx,[base]
 add dx,107h
 in al,dx
 mov ah,al
 mov al,55h
 out dx,al
 in al,dx
 cmp al,55h
 jne .bad
 mov al,0aah
 out dx,al
 in al,dx
 cmp al,0aah
 jne .bad
 mov al,ah
 out dx,al
 clc
 ret
.bad:
 mov al,ah
 out dx,al
 stc
 ret
load_bank:
 mov dx,file_bank
 mov ax,3d00h
 int 21h
 jc .bad
 mov [file_handle],ax
 xor ebp,ebp
.chunk:
 mov bx,[file_handle]
 mov dx,buffer
 mov cx,1024
 mov ah,3fh
 int 21h
 jc .bad
 test ax,ax
 jz .eof
 mov cx,ax
 mov si,buffer
.bytes:
 cmp ebp,bank_bytes
 jae .bad
 lodsb
 call set_dram
 mov dx,[base]
 add dx,107h
 out dx,al
 inc ebp
 loop .bytes
 jmp .chunk
.eof:
 cmp ebp,bank_bytes
 jne .bad
 mov bx,[file_handle]
 mov ah,3eh
 int 21h
 mov word [file_handle],0ffffh
 clc
 ret
.bad: stc
 ret

; Dedicated interrupt stack, interrupts stay disabled while programming GF1.
sound_hook:
 mov [cs:call_ax],ax
 mov ax,ss
 mov [cs:saved_ss],ax
 mov [cs:saved_sp],sp
 mov ax,cs
 mov ss,ax
 mov sp,irq_stack_end
 mov ax,[cs:call_ax]
 pushad
 push ds
 push es
 push cs
 pop ds
 cld
 mov [return_ax],ax
 cmp ah,0
 je .tick
 cmp ah,1
 je .stop
 cmp ah,2
 je .song
 cmp ah,3
 je .effect
 cmp ah,4
 je .resume
 cmp ah,11h
 je .query
 jmp .done
.tick:
 call timer_tick
 jmp .done
.stop:
 call stop_all
 jmp .done
.song:
 test al,al
 jnz .gameover
 call music_start
 jmp .done
.gameover:
 call stop_all
 mov al,19 ; digital end cue, sample bank entry 17
 call effect_start
 jmp .done
.effect:
 call effect_start
 jmp .done
.resume:
 mov byte [playing],1
 jmp .done
.query:
 xor ax,ax
 mov si,fx_busy
 mov cx,8
.q: or ax,[si]
 add si,2
 loop .q
 test ax,ax
 setnz al
 mov byte [return_ax],al
 jmp .done
.done:
 pop es
 pop ds
 popad
 mov ax,[cs:saved_ss]
 mov ss,ax
 mov sp,[cs:saved_sp]
 mov ax,[cs:return_ax]
 iret

timer_tick:
 add dword [phase],1092250 ; 50 * PIT divisor 21845
 cmp dword [phase],1193182
 jb .done
 sub dword [phase],1193182
 inc dword [tick_count]
 mov si,fx_busy
 mov cx,8
.busy:
 cmp word [si],0
 je .next
 dec word [si]
.next: add si,2
 loop .busy
 call refresh_fx_volume
 cmp byte [playing],0
 je .done
 call music_tick
.done: ret
music_start:
 inc word [music_starts]
 call stop_music
 mov word [position],0
 mov dword [phase],0
 mov byte [playing],1
 call music_tick
 ret
stop_music:
 mov byte [playing],0
 xor cx,cx
.loop:
 mov al,cl
 call select_voice
 mov bx,0
 mov al,3
 call control_write
 inc cx
 cmp cx,4
 jb .loop
 ret
stop_all:
 inc word [music_stops]
 call stop_music
 mov cx,4
.loop:
 mov al,cl
 call select_voice
 xor bx,bx
 mov al,3
 call control_write
 inc cx
 cmp cx,12
 jb .loop
 push cs
 pop es
 mov di,fx_busy
 mov cx,8
 xor ax,ax
 rep stosw
 ret
music_tick:
 mov dx,[ems_handle]
 mov ah,47h
 int 67h
 test ah,ah
 jnz .error
 mov bx,[position]
 shr bx,9 ; 512 rows/page, 32 bytes/row
 mov dx,[ems_handle]
 mov ax,4400h
 int 67h
 test ah,ah
 jnz .restore_error
 mov si,[position]
 and si,511
 shl si,5
 mov es,[ems_frame]
 mov di,row
 mov cx,16
.copy:
 mov ax,[es:si]
 mov [di],ax
 add si,2
 add di,2
 loop .copy
 mov dx,[ems_handle]
 mov ah,48h
 int 67h
 test ah,ah
 jnz .error
 xor cx,cx
 mov di,row
.voice:
 mov al,cl
 call select_voice
 mov ax,[di]
 cmp ax,254
 je .stop
 cmp ax,255
 je .params
 cmp ax,19
 jae .error
 push cx
 push di
 shl ax,4
 mov si,sample_table
 add si,ax
 call voice_sample
 pop di
 pop cx
 ; Amiga stereo layout: 0/3 left, 1/2 right.
 mov bx,0ch
 xor ax,ax
 cmp cl,0
 je .pan
 cmp cl,3
 je .pan
 mov al,0fh
.pan: call reg_write8
.params:
 mov bx,1
 mov ax,[di+2]
 call reg_write
 mov bx,9
 mov ax,[di+4]
 call scale_music_volume
 call reg_write
 jmp .advance
.stop:
 xor bx,bx
 mov al,3
 call control_write
.advance:
 add di,8
 inc cx
 cmp cx,4
 jb .voice
 inc word [position]
 cmp word [position],sequence_frames
 jb .done
 mov word [position],0
 inc dword [loop_count]
.done: ret
.restore_error:
 mov dx,[ems_handle]
 mov ah,48h
 int 67h
.error:
 inc word [ems_errors]
 mov byte [exit_code],1
 call stop_music
 ret
; SI=16-byte sample descriptor. Voice already selected.
voice_sample:
 xor bx,bx
 mov al,3
 call control_write
 mov bx,0dh
 mov al,3
 call control_write
 mov bx,2
 mov ax,[si]
 call reg_write
 mov bl,3
 mov ax,[si+2]
 call reg_write
 mov bl,4
 mov ax,[si+4]
 call reg_write
 mov bl,5
 mov ax,[si+6]
 call reg_write
 mov bl,0ah
 mov ax,[si]
 call reg_write
 mov bl,0bh
 mov ax,[si+2]
 call reg_write
 mov bl,1
 mov ax,[si+8]
 call reg_write
 mov bl,9
 mov ax,[si+10]
 cmp si,sample_table+19*16
 jb .music_volume
 call scale_fx_volume
 jmp .set_volume
.music_volume:
 call scale_music_volume
.set_volume:
 call reg_write
 xor bx,bx
 xor ax,ax
 call control_write
 ret

effect_start:
 cmp al,25
 jae .invalid
 test al,al
 jz .done
 movzx bx,al
 shl bx,1
 inc word [fx_counts+bx]
 shr bx,1
 movzx si,byte [fx_map+bx]
 shl si,4
 add si,sample_table
 mov al,[next_fx]
 call select_voice
 movzx di,al
 sub di,4
 shl di,1
 mov ax,[si+12]
 mov [fx_busy+di],ax
 mov ax,[si+10]
 mov [fx_volumes+di],ax
 call voice_sample
 ; Genuine GF1 hardware needs the effect volume re-latched after GO. Music
 ; already gets a post-start 0x09 write from music_tick; one-shot effects did
 ; not, which left them silent on a tested GUS MAX while PicoGUS played them.
 mov byte [volume_dirty],1
 call refresh_fx_volume
 inc byte [next_fx]
 cmp byte [next_fx],12
 jb .count
 mov byte [next_fx],4
.count:
 inc word [fx_count]
.done: ret
.invalid:
 inc word [fx_invalid]
 ret

fx_volumes times 8 dw 0
scale_music_volume:
 push bx
 mov bx,[music_level]
 jmp scale_volume
scale_fx_volume:
 push bx
 mov bx,[fx_level]
scale_volume:
 test bx,bx
 jz .mute
 shl bx,1
 sub ax,[gus_attenuation+bx]
 jnc .done
.mute: xor ax,ax
.done:
 pop bx
 ret
refresh_fx_volume:
 cmp byte [volume_dirty],0
 je .done
 mov byte [volume_dirty],0
 mov cx,4
 xor di,di
.loop:
 mov al,cl
 call select_voice
 mov bx,9
 mov ax,[fx_volumes+di]
 call scale_fx_volume
 call reg_write
 add di,2
 inc cx
 cmp cx,12
 jb .loop
.done: ret
gus_attenuation:
 dw 0,13600,9504,7120,5408,4096,3024,2112,1312,624,0

test_timer:
 push ax
 xor ax,ax
 int 81h
 dec byte [cs:chain_count]
 jnz .ack
 mov byte [cs:chain_count],3
 pop ax
 jmp far [cs:old8]
.ack:
 mov al,20h
 out 20h,al
 pop ax
 iret
cleanup:
 call remove_volume
 pushf
 cli
 cmp byte [gus_ready],0
 je .timer
 call stop_all
 mov bx,4ch
 mov al,1
 call reg_write8
.timer:
 popf
 cmp byte [timer_hooked],0
 je .hook
 cli
 mov al,36h
 out 43h,al
 xor al,al
 out 40h,al
 out 40h,al
 sti
 push ds
 mov dx,[old8]
 mov ax,2508h
 mov ds,[old8+2]
 int 21h
 pop ds
.hook:
 cmp byte [hooked],0
 je .memory
 push ds
 mov dx,[old81]
 mov ax,2581h
 mov ds,[old81+2]
 int 21h
 pop ds
.memory:
 mov dx,[ems_handle]
 cmp dx,0ffffh
 je .file
 mov ah,45h
 int 67h
.file:
 mov bx,[file_handle]
 cmp bx,0ffffh
 je .speaker
 mov ah,3eh
 int 21h
.speaker:
 in al,61h
 and al,0fch
 or al,[speaker_bits]
 out 61h,al
 push cs
 pop es
 ret

load_pcm:
 mov byte [last_status],1
 mov ax,3d00h
 mov dx,file_pcm
 int 21h
 jc .bad
 mov [file_handle],ax
 mov bx,ax
 xor cx,cx
 xor dx,dx
 mov ax,4202h
 int 21h
 jc .bad
 mov [file_size],ax
 mov [file_size+2],dx
 cmp dword [file_size],sequence_frames*32
 jne .bad
 xor cx,cx
 xor dx,dx
 mov ax,4200h
 int 21h
 jc .bad
 mov byte [last_status],2
 ; EMM signature at offset 0Ah in the INT 67 handler segment.
 mov ax,3567h
 int 21h
 cmp dword [es:0ah],'EMMX'
 jne .bad
 cmp dword [es:0eh],'XXX0'
 jne .bad
 mov ah,40h
 int 67h
 test ah,ah
 jnz .bad
 mov ah,41h
 int 67h
 test ah,ah
 jnz .bad
 mov [ems_frame],bx
 mov eax,[file_size]
 add eax,16383
 shr eax,14
 mov [ems_pages],ax
 mov bx,ax
 mov ah,43h
 int 67h
 test ah,ah
 jnz .bad
 mov [ems_handle],dx
 mov ah,47h
 int 67h
 test ah,ah
 jnz .bad
 xor bp,bp
.pages:
 mov dx,[ems_handle]
 mov bx,bp
 mov ax,4400h
 int 67h
 test ah,ah
 jnz .restore_bad
 ; Fill page padding with unsigned PCM silence.
 mov es,[ems_frame]
 xor di,di
 mov ax,8080h
 mov cx,8192
 rep stosw
 mov bx,[file_handle]
 mov eax,[file_size]
 movzx ecx,bp
 shl ecx,14
 sub eax,ecx
 cmp eax,16384
 jbe .read_size
 mov ax,16384
.read_size:
 mov cx,ax
 mov [fill_chunk],cx
 xor dx,dx
 push ds
 mov ds,[ems_frame]
 mov ah,3fh
 int 21h
 pop ds
 jc .read_bad
 cmp ax,[fill_chunk]
 jne .read_bad
 inc bp
 cmp bp,[ems_pages]
 jb .pages
 mov ah,48h
 mov dx,[ems_handle]
 int 67h
 test ah,ah
 jnz .bad
 mov bx,[file_handle]
 mov ah,3eh
 int 21h
 mov word [file_handle],0ffffh
 push cs
 pop es
 clc
 ret
.read_bad:
 mov byte [last_status],1
.restore_bad:
 mov ah,48h
 mov dx,[ems_handle]
 int 67h
.bad:
 push cs
 pop es
 stc
 ret

write_log:
 call volume_log
 push cs
 pop es
 movzx eax,word [base]
 mov di,log_base
 call hex8
 movzx eax,word [music_starts]
 mov di,log_starts
 call hex8
 movzx eax,word [music_stops]
 mov di,log_stops
 call hex8
 movzx eax,word [fx_count]
 mov di,log_fx
 call hex8
 movzx eax,word [fx_invalid]
 mov di,log_invalid
 call hex8
 mov eax,[tick_count]
 mov di,log_ticks
 call hex8
 mov eax,[loop_count]
 mov di,log_loops
 call hex8
 movzx eax,word [ems_errors]
 mov di,log_ems
 call hex8
 movzx eax,word [exec_error]
 mov di,log_exec
 call hex8
 movzx eax,word [position]
 mov di,log_pos
 call hex8
 mov si,fx_counts
 mov di,log_counts
 mov bp,25
.fx:
 movzx eax,word [si]
 call hex8
 inc di
 add si,2
 dec bp
 jnz .fx
 xor cx,cx
 mov dx,file_log
 mov ah,3ch
 int 21h
 jc .done
 mov bx,ax
 mov dx,log_start
 mov cx,log_end-log_start
 mov ah,40h
 int 21h
 mov ah,3eh
 int 21h
.done: ret
hex8:
 mov cx,8
.loop:
 rol eax,4
 mov bl,al
 and bl,15
 add bl,'0'
 cmp bl,'9'
 jbe .digit
 add bl,7
.digit:
 mov [di],bl
 inc di
 loop .loop
 ret
log_start db 'X2GUS experimental native GF1 diagnostics (hex)',13,10,'Base='
log_base db '00000000',13,10,'Music starts='
log_starts db '00000000',13,10,'Music stops='
log_stops db '00000000',13,10,'Digital FX requests='
log_fx db '00000000',13,10,'Unsupported FX requests='
log_invalid db '00000000',13,10,'50 Hz updates='
log_ticks db '00000000',13,10,'Music loops='
log_loops db '00000000',13,10,'EMS errors='
log_ems db '00000000',13,10,'EXEC error='
log_exec db '00000000',13,10,'Final music frame='
log_pos db '00000000',13,10,'FX counts by DOS ID 0..24:',13,10
log_counts times 25 db '00000000 '
 db 13,10
 db 'Music volume (0..10)='
log_music_level db '00000000',13,10,'Effects volume (0..10)='
log_fx_level db '00000000',13,10,'F5/F6/F7/F8 key counts='
log_volume_keys times 4 db '00000000 '
 db 13,10
log_end:
%include "volume.inc"
%include "assets.inc"
row times 32 db 0
buffer times 1024 db 0
align 16
irq_stack times 2048 db 0
irq_stack_end:
stack times 2048 db 0
stack_end:
resident_end:
