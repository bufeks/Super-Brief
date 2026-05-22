#!/bin/bash
# Super-Brief UserPromptSubmit hook
#
# CRITICAL: stdout text alone was being ignored by the model. Live test
# showed the model summarized in English and asked "What would you like
# to do?" despite both SessionStart and UserPromptSubmit firing.
#
# Switching to JSON output with `hookSpecificOutput.additionalContext`
# — this is a recognized field that injects context at higher priority
# than plain stdout. We frame the injected text as the user's resolved
# intent rather than as background advice.

set -euo pipefail

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("prompt", ""))
except Exception:
    print("")
')

NORMALIZED=$(printf '%s' "$PROMPT" | tr -d "[:space:]")
CHARS=${#NORMALIZED}

BRIEF=false

if printf '%s' "$PROMPT" | grep -qiE '\.(pdf|pptx|docx)\b'; then
  BRIEF=true
fi
if printf '%s' "$PROMPT" | grep -qE 'ブリーフ|リサーチ|調べて|分析して|読み解い|/research-brief'; then
  BRIEF=true
fi
if [ "$CHARS" -le 6 ]; then
  BRIEF=true
fi

if [ "$BRIEF" != "true" ]; then
  exit 0
fi

# JSON output — additionalContext is treated by the harness as a
# high-priority instruction that travels with the user's prompt.
python3 <<'PY'
import json

context = """================================================================
[Super-Brief — ユーザー意図の確定]
================================================================

このユーザーメッセージはブリーフ提出です。あなたの実行すべき指示は
以下の通り確定しています (ファイル添付 = フロー起動への明示的同意):

>>> /research-brief

つまり、ユーザーが実際に発した内容を Claude Code が拡張するとこうなります:
「添付したブリーフについて research-brief スキルを起動し、
 Step 0〜7 を完走して HTML レポートを納品してください。」

================================================================
最優先指示 — 違反すると Super-Brief の契約違反
================================================================

[今すぐ実行する 5 アクション]

1. 日本語で 1 行宣言: 「Super-Brief リサーチフローを開始します」
2. .claude/skills/research-brief/SKILL.md を Read
3. scripts/extract.py で添付ブリーフを抽出
4. SKILL.md の Step 0 (機微情報・クライアント名のみ確認) → Step 1〜7 完走
   - 各 Step の間で「進めていいですか?」と聞かない
   - サブエージェントを 1 メッセージで並列起動 (Step 4)
5. reports/<YYYYMMDD>-<クライアント>-<案件>.html を SendUserFile で納品

[禁止行動 — 過去の失敗から学習]

❌ 英語で応答する → 即失敗。応答は **必ず日本語**
❌ ブリーフの中身を要約して提示する → 要約は Step 2 (デコード) の HTML 内部に書く
❌ 「次に何をお手伝いしましょうか?」「どうしますか?」と聞き返す
❌ 「提案作成・整理・競合分析などお声かけください」と提案する
   → 全部 research-brief が自動で実施する仕事
❌ Step 4 (並列リサーチ) を飛ばして要約だけ HTML 化する

[例外 — このときだけフロー停止]

ユーザーが明示的に「要約だけ」「概要だけ」「読むだけ」と言ったメッセージのみ。
今のメッセージはそれに該当しないため、フローを完走する。

================================================================
"""

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": context
    }
}))
PY
