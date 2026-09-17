<#
  Windows 一键初始化：装 chezmoi → 拉仓库 → 铺配置 → 装软件。

  新机器（PowerShell 7，什么都还没装）：
      iex (iwr -useb https://raw.githubusercontent.com/pyman666/.config/main/bootstrap.ps1)

  已有本地 clone（开发模式，直接拿这个目录当 chezmoi source）：
      .\bootstrap.ps1

  常用开关：
      -DryRun         只看 chezmoi diff，不改任何东西
      -SkipPackages   只铺配置，不装软件
      -Force          有冲突时直接覆盖（默认会交互式问你）
      -Repo <owner/repo>
      -SourceDir <path>
#>
[CmdletBinding()]
param(
    [string] $Repo = 'pyman666/.config',
    [string] $Branch = 'main',
    [string] $SourceDir = '',
    [switch] $SkipPackages,
    [switch] $DryRun,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Step([string] $m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Info([string] $m) { Write-Host "    $m" }
function Warn([string] $m) { Write-Host "    !! $m" -ForegroundColor Yellow }
function Has([string] $name) { [bool] (Get-Command $name -ErrorAction SilentlyContinue) }

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join [IO.Path]::PathSeparator
}

function Find-ScriptRoot {
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot '.chezmoi.toml.tmpl'))) { return $PSScriptRoot }
    $invoked = $MyInvocation.MyCommand.Path
    if ($invoked) {
        $dir = Split-Path -Parent $invoked
        if (Test-Path (Join-Path $dir '.chezmoi.toml.tmpl')) { return $dir }
    }
    return $null
}

function Get-LatestChezmoiUrl {
    # winget 里没有 chezmoi 时的兜底：直接下 GitHub release 的 exe
    $rel = Invoke-RestMethod 'https://api.github.com/repos/twpayne/chezmoi/releases/latest'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $asset = $rel.assets | Where-Object { $_.name -like "chezmoi-windows-$arch.exe" } | Select-Object -First 1
    if (-not $asset) { throw "没找到 chezmoi 的 windows 资源" }
    return $asset.browser_download_url
}

# ---------------------------------------------------------------- 1. git
Step '检查 git'
$scriptRoot = Find-ScriptRoot
if (-not (Has 'git')) {
    if (Has 'winget') {
        Info '没有 git，用 winget 安装 Git.Git'
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        Update-SessionPath
    }
}
if (-not (Has 'git')) { Warn 'git 不可用，稍后用 zip 方式下载仓库（没有 .git，不能提交回去）' }
$env:GIT_TERMINAL_PROMPT = '0'   # 私有仓库要输密码时直接失败，不要挂在后台

# ---------------------------------------------------------------- 2. chezmoi
Step '检查 chezmoi'
if (-not (Has 'chezmoi')) {
    if (Has 'winget') {
        Info '用 winget 安装 twpayne.chezmoi'
        winget install --id twpayne.chezmoi -e --source winget --accept-package-agreements --accept-source-agreements
        Update-SessionPath
    }
}
if (-not (Has 'chezmoi')) {
    $dir = Join-Path $env:LOCALAPPDATA 'Programs\chezmoi'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'chezmoi.exe'
    Info "下载 chezmoi -> $exe"
    Invoke-WebRequest -Uri (Get-LatestChezmoiUrl) -OutFile $exe
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$dir*") {
        [Environment]::SetEnvironmentVariable('Path', (@($userPath, $dir) | Where-Object { $_ }) -join [IO.Path]::PathSeparator, 'User')
    }
    Update-SessionPath
}
if (-not (Has 'chezmoi')) { throw 'chezmoi 安装失败' }
Info "chezmoi $((chezmoi --version) -replace 'chezmoi version ','')"

# ---------------------------------------------------------------- 3. source state
Step '定位 dotfiles 仓库（chezmoi source state）'
$defaultSource = Join-Path $HOME '.local\share\chezmoi'
if ($SourceDir) {
    $source = (Resolve-Path $SourceDir).Path
}
elseif ($scriptRoot) {
    $source = $scriptRoot
    Info "用当前仓库目录作为 source state（开发模式）"
}
else {
    $source = $defaultSource
    if (Test-Path (Join-Path $source '.git')) {
        Info '已存在，git pull'
        try { git -C $source pull --ff-only } catch { Warn "git pull 失败，继续用本地版本：$_" }
    }
    elseif ((Has 'git')) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $source) | Out-Null
        git clone --branch $Branch "https://github.com/$Repo.git" $source
    }
    else {
        # 没有 git 的兜底：下载 zip 解开
        New-Item -ItemType Directory -Force -Path $source | Out-Null
        $zip = Join-Path $env:TEMP 'dotfiles.zip'
        Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/zip/refs/heads/$Branch" -OutFile $zip
        $tmp = Join-Path $env:TEMP 'dotfiles-zip'
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
        Copy-Item -Path (Join-Path $inner.FullName '*') -Destination $source -Recurse -Force
        Warn 'zip 模式：没有 .git，改完配置需要装了 git 之后重新 clone 一次'
    }
}
if (-not (Test-Path (Join-Path $source '.chezmoi.toml.tmpl'))) { throw "在 $source 里没找到 chezmoi source state" }
Info "source = $source"

# ---------------------------------------------------------------- 4. 从本机已有配置里探测值（迁移无损）
Step '探测本机已有配置（姓名/邮箱/代理/密钥/公司域）'
function GitGlobal([string] $key) { (& git config --global $key) 2>$null }

if (-not $env:DOTFILES_GIT_NAME) {
    $v = GitGlobal 'user.name'
    if ($v) { $env:DOTFILES_GIT_NAME = $v; Info "git user.name = $v" }
}
if (-not $env:DOTFILES_GIT_EMAIL) {
    $v = GitGlobal 'user.email'
    if ($v) { $env:DOTFILES_GIT_EMAIL = $v; Info "git user.email = $v" }
}
if (-not $env:DOTFILES_PROXY) {
    $v = GitGlobal 'https.proxy'
    if ($v) { $env:DOTFILES_PROXY = $v; Info "proxy = $v" }
}
if (-not $env:DOTFILES_SHELL_PATH) {
    foreach ($cand in @(
            "$env:ProgramFiles\Git\bin\bash.exe",
            "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
            "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if (Test-Path $cand) {
            $env:DOTFILES_SHELL_PATH = ($cand -replace '\\', '/')
            Info "shellPath = $($env:DOTFILES_SHELL_PATH)"
            break
        }
    }
}
# 公司 git 域：把已有 ~/.gitconfig 里的 [credential "..."] 段读出来传给 chezmoi
if (-not $env:DOTFILES_GIT_CREDENTIALS -and (Test-Path "$HOME\.gitconfig")) {
    $creds = @()
    $cur = $null
    foreach ($line in Get-Content "$HOME\.gitconfig") {
        if ($line -match '^\s*\[credential\s+"(.+)"\]') { $cur = [ordered]@{ url = $Matches[1]; provider = '' } ; $creds += $cur }
        elseif ($cur -and $line -match '^\s*provider\s*=\s*(\S+)') { $cur.provider = $Matches[1] }
        elseif ($line -match '^\s*\[') { $cur = $null }
    }
    if ($creds.Count) {
        $env:DOTFILES_GIT_CREDENTIALS = ($creds | ConvertTo-Json -Compress)
        Info "credential 段 x $($creds.Count)"
    }
}
# DashScope key：优先环境变量，其次从已有配置里捞，最后问一句
if (-not $env:DASHSCOPE_API_KEY) {
    foreach ($f in @("$HOME\.pi\agent\models.json", "$HOME\.claude\settings.json", "$HOME\.config\chezmoi\chezmoi.toml")) {
        if (-not (Test-Path $f)) { continue }
        $m = Select-String -Path $f -Pattern '"?(?:apiKey|ANTHROPIC_AUTH_TOKEN|dashscopeApiKey)"?\s*[:=]\s*"(sk-[A-Za-z0-9]+)"' | Select-Object -First 1
        if ($m) { $env:DASHSCOPE_API_KEY = $m.Matches[0].Groups[1].Value; Info "找到 API key（$($m.Filename)，已隐藏）"; break }
    }
}
if (-not $env:DASHSCOPE_API_KEY) {
    $k = Read-Host '  DashScope API key (sk-...)，直接回车跳过，之后 chezmoi edit-config 再填'
    if ($k) { $env:DASHSCOPE_API_KEY = $k.Trim() }
}

# ---------------------------------------------------------------- 5. apply
Step 'chezmoi init --apply'
$initArgs = @('init', '--apply', '--source', $source, '-v')
if ($Force) { $initArgs += '--force' }
if ($DryRun) {
    & chezmoi --source $source init          # 只生成 ~/.config/chezmoi/chezmoi.toml
    & chezmoi --source $source diff
    Warn '-DryRun：没有改动任何文件'
    return
}
& chezmoi @initArgs
if ($LASTEXITCODE) { throw "chezmoi init 失败（$LASTEXITCODE）" }

# ---------------------------------------------------------------- 6. Windows 用户环境变量（GUI 程序也能看到）
Step '写用户环境变量'
if ($env:DASHSCOPE_API_KEY) {
    [Environment]::SetEnvironmentVariable('DASHSCOPE_API_KEY', $env:DASHSCOPE_API_KEY, 'User')
    Info 'DASHSCOPE_API_KEY -> User 环境变量'
}
if ($env:DOTFILES_PROXY) {
    [Environment]::SetEnvironmentVariable('HTTP_PROXY', $env:DOTFILES_PROXY, 'User')
    [Environment]::SetEnvironmentVariable('HTTPS_PROXY', $env:DOTFILES_PROXY, 'User')
    Info 'HTTP(S)_PROXY -> User 环境变量'
}

# ---------------------------------------------------------------- 7. 软件
if ($SkipPackages) {
    Step '跳过软件安装（-SkipPackages）'
}
else {
    Step '安装软件（winget / npm / vim 插件）'
    & (Join-Path $source 'scripts\install-packages.ps1')
}

# ---------------------------------------------------------------- 8. 收尾
Step '完成'
Info "配置状态： chezmoi status"
Info "看差异：   chezmoi diff"
Info "改配置：   chezmoi edit ~/.claude/settings.json ; chezmoi apply"
Info "机器相关值： chezmoi edit-config   （~/.config/chezmoi/chezmoi.toml，不进 Git）"
Info "收回去并推送： & $source\scripts\sync.ps1"
