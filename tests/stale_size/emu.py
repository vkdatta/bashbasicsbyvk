import os,pty,sys,time,select,struct,fcntl,termios,re
F = float(os.environ.get('TEST_TIME_FACTOR', '1') or 1)   # stretches every wait on an oversubscribed machine (see tests/run.sh)
root,stale,rows=sys.argv[1],sys.argv[2],int(sys.argv[3])
cols=80
pid,fd=pty.fork()
if pid==0:
    os.execvp('bash',['bash','harness.sh',root,stale])
fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack('HHHH',rows,cols,0,0))
# tiny VT emulator: screen + scrollback
screen=[[' ']*cols for _ in range(rows)]; scroll=[]; cy=0; cx=0
def lf():
    global cy
    if cy==rows-1:
        scroll.append(''.join(screen.pop(0)).rstrip()); screen.append([' ']*cols)
    else: cy+=1
def feed(data):
    global cy,cx
    s=data.decode('utf-8','replace'); i=0
    while i<len(s):
        c=s[i]
        if c=='\x1b':
            m=re.match(r'\x1b\[([?0-9;]*)([A-Za-z])',s[i:])
            if m:
                p,k=m.group(1),m.group(2); i+=m.end()
                n=int(p) if p.isdigit() else 1
                if k=='A': cy=max(0,cy-n)
                elif k=='K': 
                    if p in('2',): screen[cy]=[' ']*cols
                    else: screen[cy][cx:]=[' ']*(cols-cx)
                elif k=='J':
                    screen[cy][cx:]=[' ']*(cols-cx)
                    for y in range(cy+1,rows): screen[y]=[' ']*cols
                continue
            i+=1; continue
        if c=='\r': cx=0
        elif c=='\n': lf(); 
        elif c in '\x07': pass
        else:
            if cx>=cols: cx=0; lf()
            screen[cy][cx]=c; cx+=1
        i+=1
fed=[0]
def pump(t=0.4, stop=None):
    end=time.time()+t
    while True:
        left=end-time.time()
        if left<=0: return
        r,_,_=select.select([fd],[],[],min(0.02,left))
        if r:
            try: d=os.read(fd,65536)
            except OSError: return
            fed[0]+=len(d); feed(d)
        if stop and stop(): return
def settle(quiet=0.15, ceiling=3.0):
    quiet*=F; ceiling*=F       # until the app printed nothing for `quiet` s
    last=fed[0]; since=time.time(); end=time.time()+ceiling
    while time.time()<end:
        pump(0.02)
        if fed[0]!=last: last=fed[0]; since=time.time()
        elif time.time()-since>=quiet: return
def text(): return '\n'.join(scroll+[''.join(r) for r in screen])
pump(10*F, lambda: 'Cheat codes' in text()); settle(0.3)        # the screen is up (no blind 1 s)
for k in [b'\x1b[B',b'\x1b[B',b'\x1b[B','x'.encode(),b'\x7f',b'\x1b[A',b'\x1b[B',b'\x1b[6~',b'\x1b[B']:
    os.write(fd,k); settle(0.12,1.0)
settle(0.3)
allt=scroll+[''.join(r).rstrip() for r in screen]
print('header count (screen+scrollback):',sum('Cheat codes' in l for l in allt))
