#!/bin/bash
# Super-Brief SessionStart hook
#
# Runs on every session start in this repo. Its stdout becomes part of
# the session context that Claude sees, so we use it to inject a
# strong, top-of-conversation reminder that turns brief-attach +
# empty-body into an unconditional /research-brief invocation.
#
# Also auto-installs the brief-extraction parsers when missing so the
# first /research-brief call doesn't fail with ModuleNotFoundError.
# Includes cryptography for AES-encrypted PDFs (some adidas-style
# briefs ship with PDF encryption that pypdf can't open without it).

set -euo pipefail

# Only meaningful in remote (Claude Code on the web) environments.
# Local runs may want the reminder too, so don't gate on remote here.

# ---- Auto-install brief-extraction deps --------------------------
# Live test showed scripts/extract.py fail on a fresh session because
# the parsers weren't installed yet; the model had to scramble for a
# workaround. Install once per session (idempotent) so the first
# brief call runs clean. Install output goes to stderr to keep the
# reminder block on stdout uncluttered.
MISSING=()
for pkg in pypdf python-pptx python-docx cryptography cffi; do
  if ! pip show "$pkg" >/dev/null 2>&1; then
    MISSING+=("$pkg")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  {
    echo "[Super-Brief] ブリーフ抽出用パッケージをインストール中: ${MISSING[*]}"
    if pip install --quiet --disable-pip-version-check "${MISSING[@]}"; then
      echo "[Super-Brief] インストール完了。"
      INSTALL_OK=true
    else
      echo "[Super-Brief] ⚠️ 自動インストール失敗。手動で: pip install -r requirements.txt"
      INSTALL_OK=false
    fi
  } >&2
else
  INSTALL_OK=true
fi

# ---- Reminder injected into session context ----------------------
cat <<'EOF'
================================================================
🟢 Super-Brief — クイック・キックオフ・ブリーフ整理エージェント
================================================================

このリポジトリは Super-Brief。広告ブリーフを「チーム即始動のための
クイック整理」として HTML に吐き出すための Claude Code 装備です。
**深い吟味は Agent-Teams 側で行われる前提** で動きます。

[必須ルール — 守らないと失敗]

1. 応答は必ず **日本語**。
   (英語は URL / クラス名 / コマンド / コミットメッセージのみ)

2. ブリーフファイル (.pdf / .pptx / .docx / .txt / .md) が
   添付されたら、本文が空でも「これ」「見て」だけでも、
   最初のアクションは **research-brief スキル起動**。

   ✅ 正解:
     「Super-Brief クイック・キックオフを開始します」と宣言
     → Step 0 で機微情報・クライアント名のみ 1 ターン確認
     → scripts/extract.py で抽出
     → サブエージェント 2 個 (競合 + 市場) を 1 メッセージで並列起動
     → reports/<日付>-<クライアント>-<案件>.html を 8 セクション順で生成
     → SendUserFile で納品

   ❌ 失敗:
     - 要約だけ返す / 「何をしましょうか?」と聞く / 英語で応答する
     - サブエージェントを並列起動しない
     - 社会の空気 / 生活者 / カルチャー等を 自分で深堀りする (Agent-Teams 領域)
     - 末尾に Sources セクションを作る (出典は引用箇所に小さく添える)
     - Creative Brief の Tagline / KV / Catch Copy を埋める (別チーム領域)

   例外: 「要約だけ」「概要だけ」「読むだけ」と明示された場合のみフロー停止。

[HTML 8 セクション順]
  0. Creative Brief (22 項目)
  1. 要約 (30 秒で読む全体像)
  2. 矛盾・課題 (議論論点)
  3. 不明点 (ブリーフから読めない)
  4. クライアントへの質問 (最大 7 個)
  5. 競合情報 (クイック・スキャン)
  6. 市場情報 (クイック・スキャン)
  7. 検討すべき可能性 (3〜5 個)
  8. Agent-Teams への引継ぎ (深掘り依頼)

[詳細仕様]
  - 人格と品質基準:        CLAUDE.md
  - フロー手順:           .claude/skills/research-brief/SKILL.md
  - Creative Brief 22 項目: templates/framework.md
  - HTML テンプレート:     templates/report.html
  - ブリーフ抽出スクリプト: scripts/extract.py

[セッション分離]
  1 セッション = 1 クライアント = 1 案件。
  別案件は新セッションで開く。reports/ の過去レポートは絶対に Read しない。

================================================================
EOF

if [ "${INSTALL_OK:-true}" != "true" ]; then
  cat <<EOF
⚠️  ブリーフ抽出用パッケージの自動インストールに失敗: ${MISSING[*]}
    PDF / PPTX / DOCX を扱う場合は手動で以下を実行:
      pip install -r requirements.txt
    (テキスト / Markdown のみなら不要)

EOF
fi

echo "================================================================"
