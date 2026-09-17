# dotfiles（chezmoi）

一台新电脑 → 一条命令 → 我的 shell / git / vim / PowerShell / AI CLI 配置全部就位。

配置用 [chezmoi](https://www.chezmoi.io) 铺，软件装由 bootstrap 脚本负责，密钥永远不进 Git。

---

## 新电脑怎么恢复

**Windows**（PowerShell 7，什么都不用先装）

```powershell
iex (iwr -useb https://raw.githubusercontent.com/pyman666/.config/main/bootstrap.ps1)
```

**macOS / Linux**

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/pyman666/.config/main/bootstrap.sh)
```

脚本做的事：查 git → 装 chezmoi → clone 这个仓库 → `chezmoi init --apply`（铺配置）→
写用户环境变量 → `scripts/install-packages.*`（装 winget/brew/npm/vim 插件）。
中途会用 `git config --global`、已有的 `~/.pi/agent/models.json`、`DASHSCOPE_API_KEY` 等
把本机的值读出来，所以老机器上重跑是**无损接管**，不会把你现有的东西写没。

已经 clone 下来了就直接跑 `.\bootstrap.ps1` / `bash bootstrap.sh`（当前目录会被当作 chezmoi
source state，开发模式，改完就能 apply 看效果）。

只想看会改什么： `.\bootstrap.ps1 -DryRun` / `bash bootstrap.sh --dry-run`

---

## 为什么要分三层

| 层 | 在哪 | 内容 |
| --- | --- | --- |
| **配置文件** | 这个仓库（进 Git） | `~/.vimrc`、`~/.gitconfig`、`~/.claude/settings.json`… 里**我自己的**设置 |
| **机器/密钥** | `~/.config/chezmoi/chezmoi.toml`（**不进 Git**） | API key、姓名邮箱、公司代理、公司 git 域、Git Bash 路径 |
| **软件** | `bootstrap.*` + `scripts/install-packages.*` | git / pwsh / vim / uv / ripgrep / fzf / npm 全局 CLI / vim 插件 |

`sk-xxx` 这种占位符不再是终态：模板里写 `{{ dig "dashscopeApiKey" "" . | toJson }}`，
apply 时从 chezmoi.toml 取真值填进去。改了 key → `chezmoi apply` → 所有工具一起更新。

---

## 目录里为什么是这些怪名字

chezmoi 按**文件名**决定「拷到哪儿、要不要渲染」：

| 名字 | 含义 |
| --- | --- |
| `dot_vimrc` | → `~/.vimrc`（`dot_` = 前置一个点） |
| `dot_config/opencode/…` | → `~/.config/opencode/…` |
| `Documents/PowerShell/…` | → `~/Documents/PowerShell/…`（无前缀 = 原样，Windows 专属） |
| `xxx.tmpl` | 当 Go 模板渲染后再写（注入密钥/代理/OS 分支） |
| `.chezmoiignore.tmpl` | 哪些目标这台机器不要（按 OS 排除） |
| `.chezmoiexternal.toml.tmpl` | 要从网上拉的文件（vim-plug 的 `plug.vim`） |
| `.chezmoi.toml.tmpl` | 生成 `~/.config/chezmoi/chezmoi.toml` 的模板 |
| `.chezmoiprivate` | 含密钥的文件名，`chezmoi add` 时提醒别提交 |
| `README.md`、`bootstrap.*`、`scripts/` | 仓库自己的东西，已在 `.chezmoiignore` 里排除（**注意**：无前缀的文件 chezmoi 会当目标复制，所以必须列出来） |

## 当前铺哪些文件

| 目标 | Windows | macOS / Linux |
| --- | --- | --- |
| `~/.vimrc` | ✅ 同一份（`plug#begin()` 自己找插件目录） | ✅ |
| `~/.gitconfig` | ✅ `autocrlf = true` | ✅ `autocrlf = input` |
| `~/.config/git/ignore` | ✅ | ✅ |
| pwsh profile | `~/Documents/PowerShell/` | `~/.config/powershell/`（另一份，逻辑不同） |
| shell rc | —（pwsh + Git Bash） | `~/.zshrc` |
| `~/.claude/settings.json` | ✅ 含 `CLAUDE_CODE_USE_POWERSHELL_TOOL` | ✅ 去掉该项 |
| `~/.codex/config.toml` | ✅ `[projects.'c:\users\…']` | ✅ `[projects.'/home/…']` |
| `~/.pi/agent/{settings,models}.json` | ✅ `shellPath` = Git Bash | ✅ `/bin/zsh`、`/bin/bash` |
| `~/.config/opencode/opencode.json` | ✅ | ✅ |
| vim-plug | `~/vimfiles` **和** `~/.vim`（Win32 vim 与 Git-Bash vim 两套目录） | `~/.vim` |

Windows 和 mac/Linux **不需要分两个仓库、也不用两套脚本**：差异全在上面这些条件分支里，
一份 source state 出三种结果。真·只有某平台要的文件（`.zshrc`、Windows profile 目录）
用 `.chezmoiignore.tmpl` 按 OS 排除。

---

## 日常操作

```sh
chezmoi status            # 哪些和本机不一致
chezmoi diff              # 具体差在哪
chezmoi edit ~/.claude/settings.json   # 改配置（编辑仓库里的模板）+ 自动 apply
chezmoi apply             # 改完铺下去
chezmoi data              # 看这台机器的 data（密钥值会打码）
chezmoi edit-config       # 改姓名/邮箱/代理/API key/公司域
chezmoi update            # = git pull + apply：别的机器同步最新配置
```

**加了个新工具，想把它的配置纳入管理：**

```sh
chezmoi add ~/.config/xxx/config.yml     # 无密钥的
chezmoi add ~/.claude/settings.json      # 含密钥的会警告
# 有密钥的：先 chezmoi add，再 chezmoi edit 把 sk-… 换成 {{ dig "dashscopeApiKey" "" . | toJson }}
```

**在这台机器上直接改了配置，想收回仓库：**

```powershell
.\scripts\sync.ps1        # Windows: re-add → 扫密钥 → commit → push
```
```sh
bash scripts/sync.sh      # macOS / Linux 同上；--check 只看不提交
```

`chezmoi re-add` 只同步**非模板**文件。模板管理的文件（settings.json / config.toml / profile）
被工具或你本机改过，得手动合并：

```sh
chezmoi merge ~/.codex/config.toml       # 三方合并：仓库版 / 本机版 / 你编辑
```

---

## 密钥与提交安全

* 真值只在 `~/.config/chezmoi/chezmoi.toml`（不在 Git 里），仓库里全是模板。
* `scripts/sync.*` 提交前扫 `sk-…`、`ghp_…`、`AKIA…`、PRIVATE KEY、`key=value` 等形式，命中就**拒绝提交**。
* 已经泄漏过的 key 建议直接换掉；顺手 `git log -p | grep sk-` 自查一遍。
* 公司机专属的 `[credential "http://账号@代理域:8080"]` 段：bootstrap 会从现有 `~/.gitconfig`
  自动搬进 chezmoi.toml，所以也不会进 Git。要手工加域就 `chezmoi edit-config` 照抄
  `[[data.gitCredentials]]` 那段格式。

## 已知取舍

`~/.codex/config.toml`、`~/.claude/settings.json`、`~/.pi/agent/settings.json` 这几个文件，
工具自己也会往里写机器相关的东西（codex 的目录信任 / hook 哈希、pi 的 `lastChangelogVersion`、
Orca 和 herdr 注入的 `hooks` 与 `statusLine`）。仓库里**故意只放我自己的设置**，所以：

* `chezmoi apply` 会把那几段抹掉，工具下次启动自己再写回去 —— 会有一次“改动”的抖动，属于预期。
* 不想丢就用 `chezmoi merge`。
* 想彻底不抖：升级成 chezmoi 的 `modify_` 脚本（只替换“托管块”，其余原样保留）。Windows 上
  `modify_*.ps1` / `run_*.ps1` 都能跑（已验证），需要时按 OS 各写一份即可。

## 换行符

`.gitattributes` 强制仓库内 LF（`*.cmd/*.bat` 才 CRLF），别用 `core.autocrlf` 去猜：
否则 `chezmoi diff` 每次都会报“全文件变更”。
