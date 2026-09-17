<#
  Windows 软件安装（由 bootstrap.ps1 调用，也可以单独跑）。
  只装「软件」，配置文件是 chezmoi 的事。

      .\scripts\install-packages.ps1            # 缺什么装什么
      .\scripts\install-packages.ps1 -Upgrade   # 顺便升级已装的
      .\scripts\install-packages.ps1 -Fonts     # 顺便装 Nerd Font（oh-my-posh font install）

  要增减软件：改下面的 $wingetIds / $psModules / $npmList。
  ID 从哪来： winget search 关键字
#>
[CmdletBinding()]
param(
    [switch] $Upgrade,
    [switch] $Fonts,
    [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Continue'

$wingetIds = @(
    'Git.Git'                        # git
    'Microsoft.PowerShell'           # pwsh 7
    'Microsoft.WindowsTerminal'      # 终端
    'JanDeDobbeleer.OhMyPosh'        # 提示符
    'twpayne.chezmoi'                # dotfiles 引擎
    'astral-sh.uv'                   # python 环境/包管理（替代 conda）
    'BurntSushi.ripgrep.MSVC'        # rg
    'junegunn.fzf'                   # 模糊搜索
    'BurntSushi.fd'                  # fd
    'sharkdp.bat'                    # bat
)
$psModules = @('Terminal-Icons', 'PSReadLine')
# Nerd Font： oh-my-posh font list 看名字
$nordFonts = @('CaskaydiaCove', 'JetBrainsMono', 'MesloLGM')

function Step([string] $m) { Write-Host "`n--- $m" -ForegroundColor Cyan }
function Info([string] $m) { Write-Host "    $m" }
function Warn([string] $m) { Write-Host "    !! $m" -ForegroundColor Yellow }
function Has([string] $name) { [bool] (Get-Command $name -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join [IO.Path]::PathSeparator
}

function Test-WingetInstalled([string] $id) {
    $out = winget list --id $id --accept-source-agreements 2>$null
    return ($LASTEXITCODE -eq 0 -and ($out | Select-String -SimpleMatch $id))
}

function Install-Winget([string] $id) {
    if (Test-WingetInstalled $id) {
        if ($Upgrade) { Step "升级 $id"; winget upgrade --id $id -e --source winget --accept-package-agreements --accept-source-agreements }
        else { Info "已装：$id" }
        return
    }
    Step "安装 $id"
    winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE) { Warn "$id 安装失败（$LASTEXITCODE），跳过" }
}

if (-not (Has 'winget')) {
    Warn '没有 winget（App Installer）。要么手动装它，要么用 choco： choco install -y git pwsh ...'
    if (-not (Has 'choco')) { return }
    $chocoIds = @('git', 'pwsh', 'oh-my-posh', 'chezmoi', 'uv', 'ripgrep', 'fzf')
    foreach ($id in $chocoIds) { Step "choco install $id"; choco install -y $id }
    return
}

# ------------------------------------------------------- 1. winget 包
Step 'winget 包'
foreach ($id in $wingetIds) { Install-Winget $id }
Refresh-Path

# node：已经有 nvm/node 就不动，否则装官方 LTS
if (-not ((Has 'node') -or (Has 'nvm'))) {
    Install-Winget 'OpenJS.NodeJS.LTS'
    Refresh-Path
}
elseif (-not (Has 'node')) {
    Warn '有 nvm 但当前没激活 node：跑一次  nvm install 24 ; nvm use 24'
}

if (-not (Has 'chezmoi')) { Install-Winget 'twpayne.chezmoi'; Refresh-Path }

# ------------------------------------------------------- 2. npm 全局 CLI（和 macOS/Linux 共用一份清单）
Step 'npm 全局 CLI'
if (-not (Has 'npm')) {
    Warn '没有 npm，跳过'
}
else {
    if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
    $list = Join-Path $RepoRoot 'scripts\npm-packages.txt'
    if (Test-Path $list) {
        $pkgs = Get-Content $list | Where-Object { $_ -and $_ -notmatch '^\s*#' }
        Info "共 $($pkgs.Count) 个"
        npm install -g @($pkgs) 2>&1 | ForEach-Object { "$_" } | Select-Object -Last 5
        if ($LASTEXITCODE) { Warn 'npm install -g 有报错，看上面输出（公司网可能要代理，见 ~/.npmrc）' }
    }
    else { Warn "找不到 $list" }
}

# ------------------------------------------------------- 3. PowerShell 模块
Step 'PowerShell 模块'
if ($PSVersionTable.PSVersion.Major -ge 6 -or (Has 'pwsh')) {
    $sh = if (Has 'pwsh') { 'pwsh' } else { 'powershell' }
    & $sh -NoProfile -Command {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        foreach ($m in 'Terminal-Icons', 'PSReadLine') {
            if (-not (Get-InstalledModule $m -ErrorAction SilentlyContinue)) {
                Write-Host "    Install-Module $m"
                Install-Module $m -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
            }
            else { Write-Host "    已装：$m" }
        }
    }
}

# ------------------------------------------------------- 4. vim 插件（plug.vim 由 chezmoi 下载）
Step 'vim 插件'
$vims = @()
if (Has 'vim') { $vims += (Get-Command 'vim').Source }
$gitBash = if (Test-Path "$env:LOCALAPPDATA\Programs\Git\usr\bin\vim.exe") { "$env:LOCALAPPDATA\Programs\Git\usr\bin\vim.exe" }
elseif (Test-Path "$env:ProgramFiles\Git\usr\bin\vim.exe") { "$env:ProgramFiles\Git\usr\bin\vim.exe" }
else { $null }
if ($gitBash -and ($vims -notcontains $gitBash)) { $vims += $gitBash }   # Git-Bash 里的 MSYS vim 插件目录是 ~/.vim
if (-not $vims.Count) { Warn '没找到 vim，跳过' }
foreach ($v in $vims) {
    Info "PlugInstall with $v"
    & $v -es -c 'PlugInstall' -c 'qa!' 2>&1 | Select-Object -Last 3
}

# ------------------------------------------------------- 5. python（uv 管理，不用 conda）
Step 'Python（uv）'
if (Has 'uv') {
    Info 'uv python install 3.13'
    uv python install 3.13 2>&1 | Select-Object -Last 2
}
else { Warn '没有 uv，跳过 python' }

# ------------------------------------------------------- 6. 字体（可选，要人盯着点确认）
if ($Fonts -and (Has 'oh-my-posh')) {
    Step 'Nerd Font'
    foreach ($f in $nordFonts) { Info "oh-my-posh font install $f"; oh-my-posh font install $f }
}
elseif ($Fonts) { Warn '没有 oh-my-posh' }
else { Info '要装 Nerd Font 的话： .\scripts\install-packages.ps1 -Fonts' }

Refresh-Path
Step '软件安装完成'
