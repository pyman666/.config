#!/usr/bin/env bash
# macOS / Linux 软件安装（bootstrap.sh 调用，也可以单独跑）。
# 只装软件；配置文件归 chezmoi。
set -uo pipefail

# brew 装的东西（macOS；Linux 上装了 brew 也用同一份）
BREW_PKGS=(
  git
  vim
  zsh
  ripgrep
  fd
  bat
  fzf
  jq
  uv
  fnm
  node
  python@3.13
)
# 没有 brew 时的 apt 名字
APT_PKGS=(git vim zsh ripgrep fd-find bat fzf jq python3 python3-pip curl)

has() { command -v "$1" >/dev/null 2>&1; }
step() { printf '\n\033[36m--- %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m!! %s\033[0m\n' "$*"; }

OS="$(uname -s)"
case "$OS" in Darwin) PLATFORM=macos ;; *) PLATFORM=linux ;; esac

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ------------------------------------------------------- 1. 包管理器
step '包管理器'
if has brew; then
  info 'brew install（已有的会自动跳过）'
  for p in "${BREW_PKGS[@]}"; do
    brew list --formula "$p" >/dev/null 2>&1 || brew install "$p" || warn "$p 安装失败，跳过"
  done
elif [ "$PLATFORM" = linux ] && has apt-get; then
  info 'apt-get install'
  sudo apt-get update
  sudo apt-get install -y "${APT_PKGS[@]}" || warn 'apt 安装部分失败'
  # uv / rust 系工具 apt 版本太老，单独装官方脚本
  has uv || { info '装 uv'; curl -LsSf https://astral.sh/uv/install.sh | sh; }
elif [ "$PLATFORM" = linux ] && has dnf; then
  info 'dnf install'
  sudo dnf install -y git vim zsh ripgrep fd-find bat fzf jq python3 || warn 'dnf 安装部分失败'
  has uv || { info '装 uv'; curl -LsSf https://astral.sh/uv/install.sh | sh; }
else
  warn '没找到 brew / apt / dnf，请手动安装：git vim zsh ripgrep fd fzf uv fnm node python'
fi

# chezmoi 兜底（正常由 bootstrap.sh 负责）
if ! has chezmoi; then
  info '装 chezmoi'
  mkdir -p "$HOME/.local/bin"
  sh -c "$(curl -fsSL get.chezmoi.io)" -- -b "$HOME/.local/bin" || warn 'chezmoi 安装失败'
fi

# ------------------------------------------------------- 2. node / npm 全局 CLI
step 'npm 全局 CLI'
if ! has node && ! has npm; then
  warn '没有 node/npm。macOS： fnm install --lts && fnm default lts-latest（或 brew install node）'
else
  if ! has fnm && has curl; then
    info '装 fnm（node 版本管理）'
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell || warn 'fnm 安装失败'
  fi
  [ -s "$HOME/.local/share/fnm/fnm" ] && eval "$("$HOME/.local/share/fnm/fnm" env)" 2>/dev/null
  export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"
  if ! has node; then
    info '用 fnm 装 node LTS'
    fnm install --lts && fnm default lts-latest && fnm use lts-latest || warn 'node 安装失败'
  fi
  if has npm && [ -f "$repo_root/scripts/npm-packages.txt" ]; then
    mapfile -t pkgs < <(grep -v '^\s*#' "$repo_root/scripts/npm-packages.txt" | grep -v '^\s*$')
    info "npm install -g： ${pkgs[*]}"
    npm install -g "${pkgs[@]}" || warn 'npm 全局安装部分失败（公司网可能需要代理）'
  elif ! has npm; then
    warn '没有 npm，跳过 CLI 安装'
  fi
fi

# ------------------------------------------------------- 3. PowerShell（oh-my-posh 提示符用）
step 'PowerShell'
if [ "$PLATFORM" = macos ] && has brew && ! has pwsh; then
  brew install --cask powershell || warn 'powershell 安装失败（可跳过）'
elif ! has pwsh; then
  info 'Linux 上装 pwsh 见 https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux'
fi
has oh-my-posh || { [ "$PLATFORM" = macos ] && has brew && brew install oh-my-posh; } || info 'oh-my-posh 可选，跳过'

# ------------------------------------------------------- 4. vim 插件（plug.vim 由 chezmoi external 下载）
step 'vim 插件'
if has vim; then
  info 'PlugInstall'
  vim -es -c 'PlugInstall' -c 'qa!' 2>&1 | tail -3
else
  warn '没有 vim'
fi

# ------------------------------------------------------- 5. python（uv 管理，不用 conda）
step 'Python（uv）'
if has uv; then
  uv python install 3.13 || warn 'uv python install 失败'
  # 需要 ~/.zshrc 里那个全局 venv 的话：
  #   uv venv ~/.venvs/py313 --python 3.13 && ~/.venvs/py313/bin/python -m pip install <你常用的包>
  [ -d "$HOME/.venvs/py313" ] || info '提示： zshrc 里的 ~/.venvs/py313 需要自己建（上面有注释）'
else
  warn '没有 uv'
fi

# ------------------------------------------------------- 6. shell
step '默认 shell'
if [ "$PLATFORM" != macos ] && has zsh && [ "$SHELL" != "$(command -v zsh)" ]; then
  info "想用 zsh： chsh -s $(command -v zsh)   （然后重开终端）"
fi

if has git; then
  git config --global core.excludesfile >/dev/null 2>&1 || true   # 全局 ignore 用 ~/.config/git/ignore，git 自动认
fi

step '软件安装完成'
