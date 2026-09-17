#!/usr/bin/env bash
# macOS / Linux 一键初始化：装 chezmoi -> 拉仓库 -> 铺配置 -> 装软件。
#
# 新机器：
#   bash <(curl -fsSL https://raw.githubusercontent.com/pyman666/.config/main/bootstrap.sh)
# 或者先 clone 再跑：
#   git clone https://github.com/pyman666/.config ~/.dotfiles && bash ~/.dotfiles/bootstrap.sh
#
# 选项： --repo owner/name  --branch main  --source DIR  --skip-packages  --dry-run  --force
set -euo pipefail

REPO="${REPO:-pyman666/.config}"
BRANCH="${BRANCH:-main}"
SOURCE_DIR="${SOURCE_DIR:-}"
SKIP_PACKAGES=0
DRY_RUN=0
FORCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --source) SOURCE_DIR="$2"; shift 2 ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE="--force"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m!! %s\033[0m\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
case "$OS" in Darwin) PLATFORM=macos ;; Linux) PLATFORM=linux ;; *) warn "未识别的系统 $OS"; PLATFORM=unknown ;; esac
info "平台： $PLATFORM"

# ---------------------------------------------------------------- 1. git
step '检查 git'
if ! has git; then
  warn '没有 git。'
  if [ "$PLATFORM" = macos ]; then echo '    xcode-select --install   # 或者 brew install git'
  else echo "    sudo apt-get install -y git   # Debian/Ubuntu；Fedora: sudo dnf install git"; fi
  exit 1
fi

# ---------------------------------------------------------------- 2. chezmoi
step '检查 chezmoi'
if ! has chezmoi; then
  mkdir -p "$HOME/.local/bin"
  if [ "$PLATFORM" = macos ] && has brew; then
    brew install chezmoi
  else
    info '官方脚本装到 ~/.local/bin（不需要 sudo）'
    sh -c "$(curl -fsSL get.chezmoi.io)" -- -b "$HOME/.local/bin"
  fi
  PATH="$HOME/.local/bin:$PATH"
fi
if ! has chezmoi; then
  warn 'chezmoi 没装上。把 ~/.local/bin 加进 PATH 后重试，或看 https://www.chezmoi.io/install/'
  exit 1
fi
info "chezmoi $(chezmoi --version | head -1)"

# ---------------------------------------------------------------- 3. source state
step '定位 dotfiles 仓库（chezmoi source state）'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -n "$SOURCE_DIR" ]; then
  SOURCE="$SOURCE_DIR"
elif [ -f "$script_dir/.chezmoi.toml.tmpl" ]; then
  SOURCE="$script_dir"
  info '用当前仓库目录（开发模式）'
else
  SOURCE="$HOME/.local/share/chezmoi"
  if [ -d "$SOURCE/.git" ]; then
    info '已存在，git pull'
    git -C "$SOURCE" pull --ff-only || warn 'git pull 失败，用本地版本继续'
  else
    mkdir -p "$(dirname "$SOURCE")"
    git clone --branch "$BRANCH" "https://github.com/$REPO.git" "$SOURCE"
  fi
fi
[ -f "$SOURCE/.chezmoi.toml.tmpl" ] || { echo "在 $SOURCE 里没找到 chezmoi source state" >&2; exit 1; }
info "source = $SOURCE"

# ---------------------------------------------------------------- 4. 探测本机已有值（迁移无损）
step '探测本机已有配置（姓名/邮箱/代理/密钥/公司域）'
export DOTFILES_GIT_NAME="${DOTFILES_GIT_NAME:-$(git config --global user.name || true)}"
export DOTFILES_GIT_EMAIL="${DOTFILES_GIT_EMAIL:-$(git config --global user.email || true)}"
export DOTFILES_PROXY="${DOTFILES_PROXY:-$(git config --global https.proxy || true)}"
[ -n "$DOTFILES_GIT_NAME" ] && info "user.name = $DOTFILES_GIT_NAME"
[ -n "$DOTFILES_GIT_EMAIL" ] && info "user.email = $DOTFILES_GIT_EMAIL"
[ -n "$DOTFILES_PROXY" ] && info "proxy = $DOTFILES_PROXY"

if [ -z "${DOTFILES_GIT_CREDENTIALS:-}" ] && [ -f "$HOME/.gitconfig" ]; then
  DOTFILES_GIT_CREDENTIALS="[$(awk '
    /^\[credential "/ { url=$0; sub(/^\[credential "/, "", url); sub(/".*/, "", url); have=1; next }
    have && /provider[ \t]*=/ { p=$0; sub(/^[^=]*=[ \t]*/, "", p); gsub(/[ \t]/, "", p);
      printf "%s{\"url\":\"%s\",\"provider\":\"%s\"}", (n++ ? "," : ""), url, p; have=0 }
  ' "$HOME/.gitconfig")]"
  export DOTFILES_GIT_CREDENTIALS
  [ "$DOTFILES_GIT_CREDENTIALS" != '[]' ] && info "credential 段已迁移"
fi

if [ -z "${DASHSCOPE_API_KEY:-}" ]; then
  for f in "$HOME/.pi/agent/models.json" "$HOME/.claude/settings.json" "$HOME/.config/chezmoi/chezmoi.toml"; do
    [ -f "$f" ] || continue
    DASHSCOPE_API_KEY="$(grep -o 'sk-[A-Za-z0-9]\{16,\}' "$f" | head -1 || true)"
    [ -n "$DASHSCOPE_API_KEY" ] && { info "找到 API key（来自 $(basename "$f")，已隐藏）"; break; }
  done
  export DASHSCOPE_API_KEY="${DASHSCOPE_API_KEY:-}"
fi
if [ -z "$DASHSCOPE_API_KEY" ]; then
  printf '    DashScope API key (sk-...)，直接回车跳过，之后 chezmoi edit-config 再填： '
  read -r DASHSCOPE_API_KEY || true
  export DASHSCOPE_API_KEY
fi

# ---------------------------------------------------------------- 5. apply
step 'chezmoi init --apply'
if [ "$DRY_RUN" = 1 ]; then
  chezmoi --source "$SOURCE" init
  chezmoi --source "$SOURCE" diff
  warn '-dry-run：没有改动任何文件'
  exit 0
fi
chezmoi init --apply --source "$SOURCE" -v $FORCE

# ---------------------------------------------------------------- 6. 软件
if [ "$SKIP_PACKAGES" = 1 ]; then
  step '跳过软件安装（--skip-packages）'
else
  step '安装软件（brew / apt / npm / vim 插件）'
  bash "$SOURCE/scripts/install-packages.sh" || warn '软件安装部分失败，看上面输出'
fi

# ---------------------------------------------------------------- 7. 收尾
step '完成'
info '配置状态：  chezmoi status'
info '看差异：    chezmoi diff'
info '改配置：    chezmoi edit ~/.claude/settings.json ; chezmoi apply'
info '机器相关值： chezmoi edit-config   （~/.config/chezmoi/chezmoi.toml，不进 Git）'
info '收回去推送： bash '"$SOURCE"'/scripts/sync.sh'
