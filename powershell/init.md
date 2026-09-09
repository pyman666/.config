# 安装插件

*升级 PowerShell*

`winget install --id Microsoft.PowerShell --source winget`
`pwsh`

*插件*

`winget install --id JanDeDobbeleer.OhMyPosh --source winget`
`Install-Module Terminal-Icons -Scope CurrentUser`
`Install-Module PSReadLine -AllowClobber -Force`

*字体* 

`oh-my-posh font install CaskaydiaCove`
`oh-my-posh font install JetBrainsMono`
`oh-my-posh font install MesloLGM`

`oh-my-posh font list`

主题

`$env:POSH_THEMES_PATH`


# 配置

`$PROFILE`

`. $PROFILE`