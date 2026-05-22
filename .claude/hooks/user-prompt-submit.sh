#!/bin/bash
# Super-Brief UserPromptSubmit hook
#
# Fires on every user prompt submission. Stdout becomes context for
# THAT specific turn — much closer to the user's message than the
# SessionStart hook output, so the model can't gloss over it.
#
# We inject a forceful "INVOKE research-brief NOW" reminder when the
# prompt looks like a brief submission:
#   - mentions a brief-shaped file extension (.pdf/.pptx/.docx)
#   - contains keywords like ブリーフ / リサーチ / 調べて / 分析して
#   - is empty or near-empty (typical of "just attached the file")
# Otherwise we stay silent to avoid noise on unrelated messages.

set -euo pipefail

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("prompt", ""))
except Exception:
    print("")
')

# Strip whitespace for length check
NORMALIZED=$(printf '%s' "$PROMPT" | tr -d "[:space:]")
CHARS=${#NORMALIZED}

BRIEF=false

# (1) File extension hint
if printf '%s' "$PROMPT" | grep -qiE '\.(pdf|pptx|docx)\b'; then
  BRIEF=true
fi

# (2) Brief / research keyword
if printf '%s' "$PROMPT" | grep -qE 'ブリーフ|リサーチ|調べて|分析して|読み解い|/research-brief'; then
  BRIEF=true
fi

# (3) Empty / very-short prompt — likely a bare file attachment
if [ "$CHARS" -le 6 ]; then
  BRIEF=true
fi

if [ "$BRIEF" != "true" ]; then
  exit 0
fi

cat <<'EOF'

================================================================
🚨 [Super-Brief 強制リマインダー] このメッセージはブリーフ提出の可能性大
================================================================

ファイル添付 = ユーザーからの「リサーチフロー起動への明示的同意」。
追加確認は不要。次のアクションは以下の **一択** です:

1. 「Super-Brief リサーチフローを開始します」と日本語で宣言
2. ファイル添付なら scripts/extract.py で本文抽出
3. .claude/skills/research-brief/SKILL.md の Step 0〜7 を完走
   - Step 0 ではクライアント名・機微情報の有無のみ確認 (1 問だけ)
   - 以降は「進めていいですか?」と聞かず一気に走る
4. reports/<YYYYMMDD>-<クライアント>-<案件>.html を生成
5. SendUserFile で HTML を渡し、重要発見 3 個と未解決の問いをチャットで報告

❌ ここで陥りがちな失敗モード (絶対に避ける):
  - ブリーフを要約して「次に何をお手伝いしましょうか?」と返す
  - 「競合分析やスケジュール組み立てなどお声かけください」と提案する
  - これら全ては research-brief が自動で実施すべき内容。
    ユーザーは「研究してくれ」と既に頼んでいる。

例外 (このときだけフローを止める):
  ユーザーが明示的に「要約だけ」「概要だけ」「読むだけ」と言った場合のみ。

================================================================
EOF
