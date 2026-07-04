#!/usr/bin/env python3
import math, wave, struct, random
from pathlib import Path

SR = 44100
BPM = 84
BEAT = 60.0 / BPM
BARS = 8
DUR = BEAT * 4 * BARS
OUT = Path('/Users/J/Documents/LanternHollow/assets/audio')
OUT.mkdir(parents=True, exist_ok=True)
random.seed(7)

NOTE = {
    'D3':146.83,'E3':164.81,'F#3':185.00,'G3':196.00,'A3':220.00,'B3':246.94,'C#4':277.18,
    'D4':293.66,'E4':329.63,'F#4':369.99,'G4':392.00,'A4':440.00,'B4':493.88,'C#5':554.37,
    'D5':587.33,'E5':659.25,'F#5':739.99,'G5':783.99,'A5':880.00,'B5':987.77,'C#6':1108.73,
    'D6':1174.66,'E6':1318.51,'F#6':1479.98,'A6':1760.00
}
SCALE = ['D4','E4','F#4','A4','B4','D5','E5','F#5','A5']

def env(t, dur, a=0.01, r=0.2):
    if t < 0 or t > dur: return 0.0
    if t < a: return t/a
    tail = max(0.0, (dur-t)/max(r, 1e-6))
    return min(1.0, tail)

def sine(f,t): return math.sin(2*math.pi*f*t)
def tri(f,t):
    return 2*abs(2*((f*t)%1)-1)-1

def bell(f, t, dur):
    e = math.exp(-4.8*t/dur) if t >= 0 else 0
    return e*(sine(f,t)*0.75 + sine(f*2.01,t)*0.18 + sine(f*3.02,t)*0.08)

def soft_pad(f,t):
    return 0.45*sine(f,t)+0.30*sine(f*1.005,t)+0.20*sine(f*2,t)

def add_note(buf, start, dur, freq, amp=0.3, wavefn=bell, pan=0.5):
    i0=max(0,int(start*SR)); i1=min(len(buf), int((start+dur)*SR))
    for i in range(i0,i1):
        tt=i/SR-start
        if wavefn == bell:
            v=bell(freq,tt,dur)*amp
        elif wavefn == tri:
            v=tri(freq,tt)*env(tt,dur,0.005,dur*0.7)*amp
        elif wavefn == soft_pad:
            v=soft_pad(freq,tt)*env(tt,dur,0.8,1.6)*amp
        else:
            v=sine(freq,tt)*env(tt,dur,0.01,0.2)*amp
        # constant power pan
        l=math.cos(pan*math.pi/2); r=math.sin(pan*math.pi/2)
        buf[i][0]+=v*l; buf[i][1]+=v*r

def add_noise(buf,start,dur,amp=0.1,pan=0.5,hp=False):
    i0=max(0,int(start*SR)); i1=min(len(buf), int((start+dur)*SR)); prev=0
    for i in range(i0,i1):
        tt=i/SR-start
        n=random.uniform(-1,1)
        if hp:
            out=n-prev; prev=n; n=out
        v=n*env(tt,dur,0.002,dur*0.5)*amp
        l=math.cos(pan*math.pi/2); r=math.sin(pan*math.pi/2)
        buf[i][0]+=v*l; buf[i][1]+=v*r

def makebuf(dur=DUR): return [[0.0,0.0] for _ in range(int(dur*SR))]

def write(path, buf):
    # gentle limiter + fade edges for loops
    n=len(buf); fade=int(0.05*SR)
    mx=max(max(abs(l),abs(r)) for l,r in buf) or 1
    gain=min(0.92/mx,1.0)
    with wave.open(str(path),'w') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        for i,(l,r) in enumerate(buf):
            f=1.0
            if i<fade: f=i/fade
            elif i>n-fade: f=(n-i)/fade
            l=max(-1,min(1,l*gain*f)); r=max(-1,min(1,r*gain*f))
            w.writeframes(struct.pack('<hh', int(l*32767), int(r*32767)))

def stem_base():
    b=makebuf()
    for bar in range(BARS):
        st=bar*4*BEAT
        for note in ['D3','A3','B3','F#3']:
            add_note(b, st, 4*BEAT, NOTE[note], 0.045, soft_pad, 0.5)
        add_note(b, st, 2.8*BEAT, NOTE['D4'], 0.07, tri, 0.35)
        add_note(b, st+2*BEAT, 1.8*BEAT, NOTE['A3'], 0.055, tri, 0.65)
    write(OUT/'music_01_base_garden.wav', b)

def stem_planting():
    b=makebuf()
    pattern=['D4','A4','F#4','E4','D4','B4','A4','F#4']
    for k in range(BARS*8):
        st=k*(BEAT/2)
        add_note(b, st, 0.34, NOTE[pattern[k%len(pattern)]], 0.10, tri, 0.35+0.3*((k%2)))
    write(OUT/'music_02_planting_pulse.wav', b)

def stem_bloom():
    b=makebuf()
    melody=['A5','B5','D6','F#5','E5','A5','D6','C#6']
    for k in range(BARS*4):
        st=k*BEAT + (0.04 if k%2 else 0)
        add_note(b, st, 0.95, NOTE[melody[k%len(melody)]], 0.12, bell, 0.2+0.6*((k%4)/3))
        if k%4==3:
            add_note(b, st+0.25, 1.2, NOTE['A6'], 0.06, bell, 0.75)
    write(OUT/'music_03_bloom_sparkle.wav', b)

def stem_fairy():
    b=makebuf()
    notes=['D6','E6','F#6','A6','F#6','E6']
    for k in range(BARS*16):
        st=k*(BEAT/4)
        if k%3!=0:
            add_note(b, st, 0.18, NOTE[notes[k%len(notes)]], 0.055, bell, random.random())
        if k%4==0:
            add_noise(b, st, 0.11, 0.025, random.random(), hp=True)
    write(OUT/'music_04_fairy_flutter.wav', b)

def stem_moonwell():
    b=makebuf()
    for bar in range(BARS):
        st=bar*4*BEAT
        for note in ['B3','F#4','A4','D5']:
            add_note(b, st, 4*BEAT, NOTE[note], 0.045, soft_pad, 0.5)
        add_note(b, st+1.5*BEAT, 2.5*BEAT, NOTE['C#5'], 0.045, bell, 0.72)
    write(OUT/'music_05_moonwell_shimmer.wav', b)

def stem_cosmic():
    b=makebuf()
    for bar in range(BARS):
        st=bar*4*BEAT
        for note in ['D4','F#4','A4','C#5']:
            add_note(b, st, 4*BEAT, NOTE[note], 0.04, soft_pad, 0.5)
        add_note(b, st+2*BEAT, 2*BEAT, NOTE['D6'], 0.045, bell, 0.25)
        add_note(b, st+3*BEAT, 1.5*BEAT, NOTE['A5'], 0.035, bell, 0.8)
    write(OUT/'music_06_constellation_pad.wav', b)

def sfx(name, parts, dur=1.0):
    b=makebuf(dur)
    for kind, start, d, note, amp, pan in parts:
        if kind=='noise': add_noise(b,start,d,amp,pan,True)
        else: add_note(b,start,d,NOTE[note],amp,bell if kind=='bell' else tri,pan)
    write(OUT/name, b)

stem_base(); stem_planting(); stem_bloom(); stem_fairy(); stem_moonwell(); stem_cosmic()
sfx('sfx_plant.wav',[('noise',0,0.16,'D4',0.05,0.5),('bell',0.05,0.45,'D5',0.25,0.5)],0.65)
sfx('sfx_bloom.wav',[('bell',0,0.65,'A5',0.22,0.35),('bell',0.10,0.8,'D6',0.18,0.65),('bell',0.22,0.85,'F#6',0.13,0.5)],1.1)
sfx('sfx_harvest.wav',[('bell',0,0.35,'D6',0.20,0.35),('bell',0.06,0.38,'A5',0.16,0.55),('bell',0.12,0.42,'F#5',0.13,0.75)],0.75)
sfx('sfx_upgrade.wav',[('bell',0,0.5,'D5',0.18,0.25),('bell',0.11,0.6,'F#5',0.16,0.5),('bell',0.22,0.8,'A5',0.14,0.75)],1.0)
sfx('sfx_fairy.wav',[('noise',0,0.12,'D4',0.025,0.3),('bell',0.02,0.25,'E6',0.10,0.7),('bell',0.10,0.25,'A6',0.07,0.45)],0.45)
sfx('sfx_ascend.wav',[('bell',0,1.4,'D5',0.22,0.25),('bell',0.18,1.7,'A5',0.20,0.5),('bell',0.42,2.0,'D6',0.18,0.75),('noise',0.05,0.8,'D4',0.04,0.5)],2.4)
print('generated audio files in', OUT)
for f in sorted(OUT.glob('*.wav')):
    print(f.name)
