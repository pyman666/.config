$ompPackage = Get-ChildItem "C:\Program Files\WindowsApps" -Directory -Filter "ohmyposh.cli_*" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$env:POSH_THEMES_PATH = Join-Path $ompPackage.FullName "themes"

oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression

Import-Module Terminal-Icons

Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView


$env:HTTP_PROXY="http://127.0.0.1:3128"
$env:HTTPS_PROXY="http://127.0.0.1:3128"
$env:NODE_USE_ENV_PROXY="1"
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8