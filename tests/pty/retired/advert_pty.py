"""ADVERT SCORE in the real app.  Types the commands of a screen into a real pty and scores what the screen advertises against what it takes.
   accepted    = typed words the screen reacts to (anything new on screen that is not "not available here" / "Invalid command")
   advertised  = keys in the footer (what is printed) and keys in cc (the Cheat codes list)
   coverage    = accepted ∩ cc / accepted × 100                    < 100  →  that menu needs an urgent fix
   phantom cc  = −100 each (cc lists a word the screen does not take)       phantom footer = −1000 each
usage: python3 tests/advert_pty.py [screen-substring]"""
import os, sys, re
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp
only = sys.argv[1] if len(sys.argv) > 1 else ''

NEVER = {'q', 'u', '=', 'kl', 'cd', '-u', 'd', 'x'}   # q leaves · u goes back · = filter · kl is `kill -9 -1` · cd opens a shell · -u upgrades · d / x delete            # q leaves, u goes back, = is the filter prefix; kl is `kill -9 -1`: it would kill the test itself
SILENT = {'clear', 'rf'}                  # run and print nothing: cannot be seen from outside, left out of both sides
STRUCT = {'u', 'q', '='}                  # universal, counted as accepted by definition (they cannot be probed without leaving)
BLOCK_NOTE = ('not available here', 'invalid command', 'invalid selection', 'not available in')   # compared in lower case

WORDY = {'fa', 'goto', 'gd'}                       # words that take an argument:  fa 1
DANGER = {'d-', 'x-', 'do-', 'up-', 'ux-', 'e-', 'rm-'}   # prefix commands that would delete / upload / expire something: not typed, listed as not judged
def probe_of(k): return k + '1' if k.endswith('-') else (k + ' 1' if k in WORDY else k)

class App(PtyApp):
    def __init__(self):
        def populate(home, work):
            for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
        super().__init__(root, 110, 44, populate)

def rows(a): return [l.rstrip() for l in a.scr.lines() if l.strip()]

def open_path(a, path):
    for step in path:
        if step.startswith('@'): a.line(step[1:]); a.settle(1.5); continue
        if step in ('s', 'h'): a.line(step); a.settle(0.7); continue
        n = None
        for l in rows(a):
            m = re.match(r'^\s*(\d+)\)\s+(?:\[.\]\s+)?(.*?)\s{2,}', l + '  ')
            if m and m.group(2).strip().startswith(step): n = m.group(1); break
        if n is None: return False
        a.line(n); a.settle(0.7)
    return True

def footer_keys(a):
    keys = set()
    for l in rows(a)[-6:]:
        for cell in re.split(r'\s{3,}', l.strip()):
            m = re.match(r'^([^\s)]+)\)\s+\S', cell)
            if m and not m.group(1).isdigit():
                k = m.group(1)
                if k == 'N': continue                          # "N) Open" is an instruction, not a typed word
                mm = re.match(r'^(.+-)N$', k)
                keys.add((mm.group(1) if mm else k).lower())   # "c-N" is the typed prefix "c-" 
    return keys

def cc_keys(a):
    a.line('cc'); a.settle(1.0)
    keys = set()
    for _ in range(25):                                    # the list scrolls: read, move down, read ... until nothing is below
        for l in rows(a):
            m = re.match(r'^\s*\d+\)\s+(\S+)\s{2,}', l + '  ')
            if m: keys.add(m.group(1).lower())
        if not any('more below' in l for l in rows(a)): break
        a.send('\x1b[6~'); a.settle(0.4)                    # Page Down: one key per send (several in one send are read as one)
    a.line('u'); a.settle(0.6)
    return keys

def map_words(mapname):
    ws = []
    p = os.path.join(root, 'script/file/cmdmap', mapname, 'bashbasicsbyvk_%s.map' % mapname)
    for l in open(p):
        m = re.match(r'^(\S+)\s+\.mapto\(\)', l)
        if m: ws.append(m.group(1))
    return ws

SEEDS = {'Settings > Display > Group by': ['clr', '1']}   # a stateful screen: put it in two different states so a command's effect is visible
SCREENS = [   # name, path ("@word" = typed from the main list), owning map
    ('Main list',           [],                          'main'),
    ('Settings',            ['s'],                       'settings'),
    ('Settings > Display',  ['s', 'Display'],            'settings'),
    ('Settings > Display > Group by', ['s', 'Display', 'Group by'], 'settings'),
    ('Home',                ['h'],                       'home'),
    ('Switch',              ['@sw'],                     'switch'),
    ('Functions',           ['@fx'],                     'fx'),
    ('Links (api)',         ['@api'],                    'api'),
    ('Backups (bk)',        ['@bk'],                     'api'),
    ('Pending',             ['@pn'],                     'pending'),
    ('Infinity stones',     ['@i'],                      'infinity'),
    ('Find',                ['@f'],                      'find'),
    ('Organise',            ['@z'],                      'organise'),
    ('Transfer',            ['@t'],                      'transfer'),
    ('Upgrade',             ['@-u'],                     'upgrade'),
    ('Auth users',          ['@-auth'],                  'auth'),
]
tot_bad = 0
for name, path, mp in SCREENS:
    if only and only not in name: continue
    a = App()
    try:
        if not open_path(a, path): print('SKIP %s: could not open (%s)' % (name, path)); continue
        F = footer_keys(a); C = cc_keys(a)
        NOTE = ('❌', '🔴', '📜', '❗', '💡')
        def body(a): return [l for l in rows(a)[1:-1] if not l.strip().startswith(NOTE)]    # the screen without its first (status) row, the prompt and a note
        a.line('='); a.settle(0.4); home_body = body(a)
        universe = sorted((set(map_words(mp)) | (set(map_words('main')) if mp == 'main' else set()) | C | F | {'?', 'print', 'cc', 'loadtime', 'clr', 'a', 'd'}) - NEVER - STRUCT)
        accepted = set(); unjudged = set(); control = None
        for w in universe:
            if w in DANGER: unjudged.add(w); continue
            if control is None:                                  # what the screen says to a prefix it does not have
                a.line('='); a.settle(0.3); cb = rows(a); a.line('zq-1'); a.wait(lambda: rows(a) != cb and rows(a)[-1].strip() == 'Select:', 3.0); a.settle(0.4)
                control = [l for l in rows(a) if l not in cb and not l.strip().startswith('Select:')]
            argd = w.endswith('-') or w in WORDY or w.startswith('.')
            for seed in SEEDS.get(name, [None]):
                if seed is not None and seed != w: a.line(seed); a.settle(0.4)
                a.line('='); a.settle(0.3)                     # "=" + Enter: a no-op that clears the note of the last word (an empty Enter would toggle the highlighted row)
                before = rows(a); a.line(probe_of(w)); a.wait(lambda: rows(a) != before and rows(a)[-1].strip() == 'Select:', 3.0); a.settle(0.4); after = rows(a)
                new = [l for l in after if l not in before and not l.strip().startswith('Select:')]   # the echo of what was typed is not a reaction
                notes = BLOCK_NOTE if not argd else tuple(n for n in BLOCK_NOTE if n != 'invalid selection')   # "Invalid selection" is how a list answers a valid prefix with a wrong number
                rej = any(any(n in l.lower() for n in notes) for l in new)
                if argd and new == control: continue              # the same answer a prefix that does not exist gets: proves nothing
                if new and not rej: accepted.add(w); break
            else:
                if argd: unjudged.add(w)        # a prefix / argument word that shows nothing in this state: cannot be judged from outside
            # back to the screen (a command may have opened another screen)
            for _ in range(3):
                if len(rows(a)) > 1 and rows(a)[-1].strip().startswith('Select') and body(a) == home_body: break
                a.line('u'); a.settle(0.5)
            else:
                a.close(); a = App(); open_path(a, path)
        A = (accepted | STRUCT) - SILENT - unjudged
        Cc = C - SILENT - unjudged; Ff = F - SILENT - unjudged
        cov = 100.0 * len(A & Cc) / len(A) if A else 100.0
        ph_cc = sorted(Cc - A - {'cc'} - NEVER); ph_ft = sorted(Ff - A - {'cc'})   # kl is never typed by the test (kill -9 -1): not judged
        score = cov - 100 * len(ph_cc) - 1000 * len(ph_ft)
        miss = sorted(A - Cc)
        print('%-32s coverage %5.1f   phantom cc %d   phantom footer %d   SCORE %.0f' % (name, cov, len(ph_cc), len(ph_ft), score))
        if unjudged: print('    not judged (needs items / dangerous):', ' '.join(sorted(unjudged)))
        if miss: print('    accepted but not in cc:', ' '.join(miss))
        if ph_cc: print('    in cc but not accepted:', ' '.join(ph_cc))
        if ph_ft: print('    in footer but not accepted:', ' '.join(ph_ft))
        if cov < 100 or ph_cc or ph_ft: tot_bad += 1
    finally: a.close()
print('ALL OK (every screen scores 100)' if not tot_bad else '%d screen(s) below 100 — urgent fix' % tot_bad); sys.exit(1 if tot_bad else 0)
