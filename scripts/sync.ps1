<#
  把本机改过的配置收进仓库并推回 GitHub（Windows）。
  macOS / Linux 用 scripts/sync.sh，逻辑一样。

      .\scripts\sync.ps1                       # re-add → 扫密钥 → commit → push
      .\scripts\sync.ps1 -Message "vim: 加了 NERDTree"
      .\scripts\sync.ps1 -NoPush               # 只 commit 不 push
      .\scripts\sync.ps1 -Check                # 只给我看改了什么，不写任何东西

  注意： chezmoi re-add 只会同步「非模板」文件。
  被 chezmoi 模板管理的文件（settings.json / config.toml / profile 等）改了要用：
      chezmoi merge ~/.claude/settings.json    或   chezmoi edit ~/.claude/settings.json
#>
[CmdletBinding()]
param(
    [string] $Message = '',
    [switch] $NoPush,
    [switch] $Check
)

$ErrorActionPreference = 'Stop'

function Step([string] $m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Info([string] $m) { Write-Host "    $m" }
function Warn([string] $m) { Write-Host "    !! $m" -ForegroundColor Yellow }

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) { throw '先跑 bootstrap.ps1 装 chezmoi' }

$source = (chezmoi source-path).Trim()
if (-not (Test-Path (Join-Path $source '.git'))) { throw "$source 不是 git 仓库，不能提交回去" }
Info "source = $source"

if (-not $Check) {
    Step 're-add：把本机文件拷回 source state'
    chezmoi re-add
}

Step '看仓库里变了什么'
& git -C $source add -A
$staged = & git -C $source diff --cached --name-only
if (-not $staged) { Step '没有变化，收工'; return }
$staged | ForEach-Object { Info $_ }
& git -C $source diff --cached --stat | ForEach-Object { Write-Host "    $_" }

# ------------------------------------------------ 密钥扫描（防手滑提交到公网仓库）
Step '扫描密钥'
$patterns = @(
    'sk-[A-Za-z0-9]{20,}',          # DashScope / OpenAI 风格
    'ghp_[A-Za-z0-9]{20,}',
    'github_pat_[A-Za-z0-9_]{20,}',
    'AKIA[0-9A-Z]{16}',
    'xox[baprs]-[A-Za-z0-9-]{10,}',
    '-----BEGIN [A-Z ]*PRIVATE KEY',
    '(?i)(api[_-]?key|secret|token|password)\s*[:=]\s*["'']?[A-Za-z0-9_\-/+]{16,}'
)
$diffText = & git -C $source diff --cached -U0 | Out-String
$hits = @()
foreach ($p in $patterns) { if ($diffText -match $p) { $hits += $p } }
if ($hits.Count) {
    Warn '检测到疑似真实密钥，已拒绝提交：'
    $hits | ForEach-Object { Warn "  正则：$_" }
    Warn '把真值挪到 ~/.config/chezmoi/chezmoi.toml（不进 Git），'
    Warn '仓库里改成 {{ dig "dashscopeApiKey" "" . | quote }} 这种模板写法，再跑一次。'
    Warn ('确认是误报的话手动提交： git -C "' + $source + '" commit')
    return
}
Info '干净'

if ($Check) { & git -C $source reset -q; Step '-Check：已撤销暂存，什么都没提交'; return }

# ------------------------------------------------ commit / push
if (-not $Message) { $Message = 'sync from ' + (Get-CimInstance Win32_ComputerSystem).Name }
Step "commit： $Message"
& git -C $source commit -m $Message

if ($NoPush) { Info '-NoPush，没推送' }
else {
    Step 'push'
    & git -C $source push
    if ($LASTEXITCODE) { Warn 'push 失败（私有仓库要认证），手动 git push 一次即可' }
}

Step '完成。别的机器上： chezmoi update'
