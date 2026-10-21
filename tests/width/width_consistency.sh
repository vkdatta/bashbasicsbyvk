#!/usr/bin/env bash
# Caret / width guard.  bash tests/width/width_consistency.sh
# (1) known characters measure like a real terminal (wcwidth): 🗄️ 👁️ ⚠️ ℹ️ = 1 cell, 📁 ✅ ❌ = 2 (a wrong width put the caret
#     one cell to the right on every prompt that starts with 🗄️)
# (2) _bvk_dispw (caret / fit) and _vp_cells (menus) always agree
# (3) every non-ASCII character used in a read -p / prompt string in script/ is measured identically by both
# (4) nobody writes a second emoji width table: 0x1F300 may only appear in the viewport helper / the JS Emoji_Presentation tests
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
source "$ROOT/script/file/engine/bashbasicsbyvk_viewport.sh" 2>/dev/null
declare -F _vp_cpw >/dev/null || { echo "FAIL _vp_cpw missing"; exit 1; }

chk() {  # text expected label
  _bvk_dispw "$1"; local a=$_BVK_W; _vp_cells "$1"; local b=$_vp_w
  [ "$a" = "$2" ] && [ "$b" = "$2" ] && ok "$3 = $2" || bad "$3: dispw=$a cells=$b expected $2"
}
chk "🗄️" 1 "file cabinet + VS16"
chk "🗄️  Back up" 10 "backup prompt start"
chk "👁️" 1 "eye + VS16"; chk "⚠️" 1 "warning"; chk "ℹ️" 1 "info"; chk "✏️" 1 "pencil"; chk "⚙️" 1 "gear"; chk "⏱️" 1 "stopwatch"
chk "🖥️" 1 "desktop"; chk "🗑️" 1 "wastebasket"
chk "📁" 2 "folder"; chk "👤" 2 "bust"; chk "🚫" 2 "no entry"; chk "💳" 2 "card"; chk "✅" 2 "check"; chk "❌" 2 "cross"; chk "⭐" 2 "star"
chk "日本" 4 "CJK"; chk "é" 1 "latin"; chk "abc" 3 "ascii"

# (3) every non-ASCII char in prompt-like lines
bad_n=0; seen=" "
while IFS= read -r ch; do
  [[ "$seen" == *" $ch "* ]] && continue; seen+="$ch "
  _bvk_dispw "$ch"; a=$_BVK_W; _vp_cells "$ch"; b=$_vp_w
  [ "$a" = "$b" ] || { bad "dispw($ch)=$a but cells=$b"; bad_n=1; }
done < <(grep -rhE 'read .*-p|_ask=|p_[a-z]+=' "$ROOT/script" 2>/dev/null | grep -o . | LC_ALL=C.UTF-8 grep -P '[^\x00-\x7F]' | sort -u)
[ "$bad_n" = 0 ] && ok "both width functions agree on every prompt character"

# (4)
hits=$(grep -rnE '0x1F[0-9A-Fa-f]{3}' "$ROOT/script" | grep -v 'bashbasicsbyvk_viewport.sh')
[ -z "$hits" ] && ok "no second emoji width table" || { bad "extra width table:"; echo "$hits"; }
[ "$fail" = 0 ] && echo "width consistency: OK" || echo "width consistency: FAILED"
exit "$fail"
