#!/bin/bash
# Super-Brief PreToolUse hook — hard-block repo pollution
#
# Super-Brief is a config-only repo. Brief inputs and research output
# MUST NOT be committed or PR'd. Live test showed the model open a PR
# with a 250-line brief-derived markdown despite multiple soft guard-
# rails — Claude Code on the web's default "open a PR when done"
# behaviour was overriding our text instructions. This hook denies the
# dangerous tool calls so the model can't make them at all.

set -euo pipefail

INPUT=$(cat)
export SUPERBRIEF_HOOK_INPUT="$INPUT"

exec python3 - <<'PY'
import json, os, re, sys

raw = os.environ.get("SUPERBRIEF_HOOK_INPUT", "")
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

tool = data.get("tool_name") or data.get("toolName") or ""
params = data.get("tool_input") or data.get("toolInput") or {}

def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)

# ---- Bash guard: git write-ops and gh PR ops ----
# Block only when the operation would push BRIEF/RESEARCH content.
# Config-only commits (changes within .claude/, scripts/, templates/,
# CLAUDE.md, README.md, .gitignore, requirements.txt) are fine.
def repo_paths_are_config_only(repo, paths):
    config_prefixes = (
        ".claude/", "scripts/", "templates/",
    )
    config_files = {
        "CLAUDE.md", "README.md", ".gitignore", "requirements.txt",
    }
    for p in paths:
        if p in config_files:
            continue
        if any(p.startswith(prefix) for prefix in config_prefixes):
            continue
        return False
    return True

def git_staged_or_changed(repo):
    import subprocess
    try:
        out = subprocess.check_output(
            ["git", "-C", repo, "diff", "--cached", "--name-only"],
            stderr=subprocess.DEVNULL,
        ).decode().splitlines()
        # Also include unstaged changes that might get added by `git add .`
        out2 = subprocess.check_output(
            ["git", "-C", repo, "diff", "--name-only"],
            stderr=subprocess.DEVNULL,
        ).decode().splitlines()
        untracked = subprocess.check_output(
            ["git", "-C", repo, "ls-files", "--others", "--exclude-standard"],
            stderr=subprocess.DEVNULL,
        ).decode().splitlines()
        return list({*out, *out2, *untracked})
    except Exception:
        return []

if tool == "Bash":
    cmd = (params.get("command") or "").strip()
    patterns = [
        (r"\bgit\s+add\b",         "git add"),
        (r"\bgit\s+commit\b",      "git commit"),
        (r"\bgit\s+push\b",        "git push"),
        (r"\bgh\s+pr\s+create\b",  "gh pr create"),
        (r"\bgh\s+pr\s+edit\b",    "gh pr edit"),
    ]
    for pat, name in patterns:
        if re.search(pat, cmd):
            repo = "/home/user/Super-Brief"
            paths = git_staged_or_changed(repo)
            if paths and repo_paths_are_config_only(repo, paths):
                # Config-only iteration — allow.
                sys.exit(0)
            deny(
                "Super-Brief は設定専用リポジトリです。"
                f"リサーチ成果物に対する `{name}` は禁止。\n"
                f"今ステージ/変更されている対象外パス: {[p for p in paths if not (p in {'CLAUDE.md','README.md','.gitignore','requirements.txt'} or any(p.startswith(x) for x in ('.claude/','scripts/','templates/')))]}\n"
                "納品は reports/ への HTML 書き出し + SendUserFile のみ。"
            )
    sys.exit(0)

# ---- GitHub MCP guard ----
github_blocked = {
    "mcp__github__create_pull_request",
    "mcp__github__push_files",
    "mcp__github__create_or_update_file",
    "mcp__github__delete_file",
    "mcp__github__create_branch",
}
if tool in github_blocked:
    deny(
        f"Super-Brief は設定専用リポジトリです。`{tool}` を使った "
        "リサーチ成果物の push / PR 化は禁止。\n"
        "納品は SendUserFile による HTML 直接送付のみ。"
    )

# ---- Write guard ----
if tool == "Write":
    path = params.get("file_path") or ""
    norm = os.path.normpath(path)

    # Anything outside the repo is fine (e.g. /tmp work files).
    if not (norm.startswith("/home/user/Super-Brief") or norm.startswith("Super-Brief/")):
        sys.exit(0)

    allowed_prefixes = (
        "/home/user/Super-Brief/reports/",
        "/home/user/Super-Brief/.claude/",
        "/home/user/Super-Brief/scripts/",
        "/home/user/Super-Brief/templates/",
        "Super-Brief/reports/",
        "Super-Brief/.claude/",
        "Super-Brief/scripts/",
        "Super-Brief/templates/",
    )
    allowed_files = {
        "/home/user/Super-Brief/CLAUDE.md",
        "/home/user/Super-Brief/README.md",
        "/home/user/Super-Brief/.gitignore",
        "/home/user/Super-Brief/requirements.txt",
    }
    if norm in allowed_files or any(norm.startswith(p) for p in allowed_prefixes):
        sys.exit(0)

    # Inside repo but outside the allow-list — block brief-shaped artefacts.
    if re.search(r"\.(md|html|txt|pdf|pptx|docx)$", norm, re.I):
        deny(
            f"Super-Brief は設定専用リポジトリです。`{path}` への書き込みは禁止。\n"
            "リサーチ成果物は必ず reports/<YYYYMMDD>-<クライアント>-<案件>.html に "
            "書き出してください (reports/*.html は .gitignore 除外済み)。"
        )

sys.exit(0)
PY
