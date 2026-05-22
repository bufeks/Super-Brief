#!/bin/bash
# Super-Brief PreToolUse hook (Read tool)
#
# Fires whenever the model tries to Read a file. If the file is a brief
# (pdf/pptx/docx/txt/md path or attachment), inject a final reminder
# that the model is in Super-Brief context and must run the
# research-brief flow — not summarize.
#
# Empirically the model already runs Read after both SessionStart and
# UserPromptSubmit hooks fire, but still chooses to summarize. This
# hook gives us one more chance to interrupt the summary-bias right
# before the model formulates its post-Read response.

set -euo pipefail

INPUT=$(cat)

TARGET=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    name = data.get("tool_name") or data.get("toolName") or ""
    if name != "Read":
        # Not a Read call — nothing to do.
        print("__skip__")
    else:
        params = data.get("tool_input") or data.get("toolInput") or {}
        print(params.get("file_path", ""))
except Exception:
    print("")
')

if [ "$TARGET" = "__skip__" ] || [ -z "$TARGET" ]; then
  exit 0
fi

# Brief-shaped file?
if ! printf '%s' "$TARGET" | grep -qiE '\.(pdf|pptx|docx|txt|md)$'; then
  exit 0
fi

# Skip if it's a repo doc the model is supposed to Read normally
case "$TARGET" in
  */CLAUDE.md|*/README.md|*/SKILL.md|*/framework.md|*/requirements.txt)
    exit 0
    ;;
esac

# Emit a context note via the recognized JSON envelope.
python3 <<'PY'
import json

ctx = """[Super-Brief 警告 — Read 直前にもう一度確認]

あなたは今、ブリーフらしきファイルを Read しようとしています。
このファイルの内容を「要約してチャットに返す」のは Super-Brief で
最大の失敗モードです。

代わりに:
- このファイルが既に scripts/extract.py で抽出済みならテキストを内部メモとして使い、
  research-brief Step 2 (デコード) に進む。
- HTML レポートに統合する内容として読み、Step 7 まで完走する。
- 「次に何をしますか?」とユーザーに聞かない。

応答は必ず日本語で。"""

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": ctx
    }
}))
PY
