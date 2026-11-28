"""ICONS ARE 2 CELLS (AGENTS.md rule 20) — no text-default (1-cell) emoji and no U+FE0F anywhere under script/.
A text-default emoji (⚙ ☁ 🗑 ⚠ ▶ ...) is 1 cell in the width table but some terminals draw it wider, which shows as a gap between icon and text.
Use a wide emoji (🔧 ⛅ 🚮 ❗ ⏩ ...) written bare.  The listed exceptions are typographic marks, not icons."""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('icons')
TEXT_DEFAULT = set('©®‼⁉™ℹ↩↪⌨⏏⏭⏮⏯⏱⏲⏸⏹⏺Ⓜ▪▫▶◀◻◼☀☁☂☃☄☎☑☘☝☠☢☣☦☪☮☯☸☹☺♀♂♟♠♣♥♦♨♻♾⚒⚔⚕⚖⚗⚙⚛⚜⚠⚧⚰⚱⛈⛏⛑⛓⛩⛰⛱⛴⛷⛸⛹✂✈✉✌✍✏✒✔✖✝✡✳✴❄❇❣❤➡⤴⤵⬅⬆⬇〰〽㊗㊙')
TEXT_DEFAULT -= set('©®™')                                   # plain typography
TEXT_DEFAULT |= {chr(c) for c in (0x1F321, 0x1F324, 0x1F325, 0x1F326, 0x1F327, 0x1F328, 0x1F329, 0x1F32A, 0x1F32B, 0x1F32C, 0x1F336, 0x1F37D, 0x1F396, 0x1F397,
    0x1F399, 0x1F39A, 0x1F39B, 0x1F39E, 0x1F39F, 0x1F3CB, 0x1F3CC, 0x1F3CD, 0x1F3CE, 0x1F3D4, 0x1F3D5, 0x1F3D6, 0x1F3D7, 0x1F3D8, 0x1F3D9, 0x1F3DA, 0x1F3DB,
    0x1F3DC, 0x1F3DD, 0x1F3DE, 0x1F3DF, 0x1F3F3, 0x1F3F5, 0x1F3F7, 0x1F43F, 0x1F441, 0x1F4FD, 0x1F549, 0x1F54A, 0x1F56F, 0x1F570, 0x1F573, 0x1F574, 0x1F575,
    0x1F576, 0x1F577, 0x1F578, 0x1F579, 0x1F587, 0x1F58A, 0x1F58B, 0x1F58C, 0x1F58D, 0x1F590, 0x1F5A5, 0x1F5A8, 0x1F5B1, 0x1F5B2, 0x1F5BC, 0x1F5C2, 0x1F5C3,
    0x1F5C4, 0x1F5D1, 0x1F5D2, 0x1F5D3, 0x1F5DC, 0x1F5DD, 0x1F5DE, 0x1F5E1, 0x1F5E3, 0x1F5E8, 0x1F5EF, 0x1F5F3, 0x1F5FA, 0x1F6CB, 0x1F6CD, 0x1F6CE, 0x1F6CF,
    0x1F6E0, 0x1F6E1, 0x1F6E2, 0x1F6E3, 0x1F6E4, 0x1F6E5, 0x1F6E9, 0x1F6F0, 0x1F6F3)}
# (basename, text that marks the exempt line): a hand-padded marker column or a doc comment, never a row icon
EXEMPT = [('bashbasicsbyvk_smartmenu.sh', 'mark="▶ "'), ('bashbasicsbyvk_loadtime_report', 'mark ='), ('bashbasicsbyvk_loadtime_report', 'Enter pressed'),
          ('bashbasicsbyvk_viewport.sh', '#'), ('bashbasicsbyvk_favourites.sh', '↪ moved to')]
for p in bvk.all_files():
    b = os.path.basename(p)
    for n, line in enumerate(bvk.read(p).split('\n'), 1):
        R.check()
        bad = [c for c in line if c in TEXT_DEFAULT or c == '\ufe0f'] + (['\\ufe0f'] if '\\ufe0f' in line.lower() else [])
        if not bad: continue
        if any(b == eb and (m in line if m != '#' else line.lstrip().startswith('#')) for eb, m in EXEMPT): continue
        R.add('icons:%s:%d' % (bvk.rel(p).replace('/', '_'), n), '%s:%d has a 1-cell emoji %s (use a 2-cell one, bare: AGENTS.md rule 20)' % (bvk.rel(p), n, ' '.join('U+%04X' % ord(c[0]) for c in sorted(set(bad)))))
sys.exit(R.finish())
