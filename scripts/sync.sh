#!/usr/bin/env bash
# 把本机改过的配置收进仓库并推回 GitHub（macOS / Linux）。
# Windows 用 scripts/sync.ps1，逻辑一样。
#
#   bash scripts/sync.sh
#   bash scripts/sync.sh -m "vim: 加了 NERDTree"
#   bash scripts/sync.sh --no-push
#   bash scripts/sync.sh --check          # 只看看改了什么，不提交
#
# 注意： chezmoi re-add 只同步「非模板」文件。
# 模板管理的文件（settings.json / config.toml / profile 等）改了要用：
#   chezmoi merge ~/.claude/settings.json     或   chezmoi edit ~/.claude/settings.json
set -uo pipefail

MESSAGE=""
NO_PUSH=0
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message) MESSAGE="$2"; shift 2 ;;
    --no-push) NO_PUSH=1; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m!! %s\033[0m\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

has chezmoi >/dev/null 2>&1 || { echo '先跑 bootstrap.sh 装 chezmoi' >&2; exit 1; }
SOURCE="$(chezmoi source-path)"
[ -d "$SOURCE/.git" ] || { echo "$SOURCE 不是 git 仓库，不能提交回去" >&2; exit 1; }
info "source = $SOURCE"

if [ "$CHECK" = 0 ]; then
  step 're-add：把本机文件拷回 source state'
  chezmoi re-add
fi

step '看仓库里变了什么'
git -C "$SOURCE" add -A
STAGED="$(git -C "$SOURCE" diff --cached --name-only)"
if [ -z "$STAGED" ]; then step '没有变化，收工'; exit 0; fi
printf '%s\n' "$STAGED" | sed 's/^/    /'
git -C "$SOURCE" diff --cached --stat | sed 's/^/    /'

# ------------------------------------------------ 密钥扫描（防手滑提交到公网仓库）
step '扫描密钥'
DIFF="$(git -C "$SOURCE" diff --cached -U0)"
HITS=""
for p in 'sk-[A-Za-z0-9]{20,}' 'ghp_[A-Za-z0-9]{20,}' 'github_pat_[A-Za-z0-9_]{20,}' \
         'AKIA[0-9A-Z]{16}' 'xox[baprs]-[A-Za-z0-9-]{10,}' '-----BEGIN [A-Z ]*PRIVATE KEY'; do
  printf '%s' "$DIFF" | grep -Eq "$p" && HITS="$HITS
  正则：$p"
done
printf '%s' "$DIFF" | grep -iqE '(api[_-]?key|secret|token|password)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,}' \
  && HITS="$HITS
  正则：key=value 形式"

if [ -n "$HITS" ]; then
  warn "检测到疑似真实密钥，已拒绝提交：$HITS"
  warn '把真值挪到 ~/.config/chezmoi/chezmoi.toml（不进 Git），'
  warn '仓库里改成 {{ dig "dashscopeApiKey" "" . | quote }} 这种模板写法，再跑一次。'
  warn '确认是误报的话手动提交： git -C "$SOURCE" commit'
  exit 1
fi
info '干净'

if [ "$CHECK" = 1 ]; then
  git -C "$SOURCE" reset -q
  step '--check：已撤销暂存，什么都没提交'
  exit 0
fi

[ -n "$MESSAGE" ] || MESSAGE="sync from $(hostname)"
step "commit： $MESSAGE"
git -C "$SOURCE" commit -m "$MESSAGE"

if [ "$NO_PUSH" = 1 ]; then
  info '--no-push，没推送'
else
  step 'push'
  git -C "$SOURCE" push || warn 'push 失败（私有仓库要认证），手动 git push 一次即可'
fi

step '完成。别的机器上： chezmoi update'
