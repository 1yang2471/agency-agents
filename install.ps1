<#
.SYNOPSIS
  agency-agents 一键安装器（Windows）：把本仓库安装到本机所有 agent 平台。

.DESCRIPTION
  唯一真身 = 本脚本所在目录（即克隆/解压的仓库位置，请勿移动或删除）。
  其余平台通过 junction（目录联接）指向真身，实现"下载一次、全平台同步、自动更新"。
  自动探测并安装到：Trae CN / CodeBuddy CN / Codex / opencode / Claude Code / .agents 通用目录。
  可选注册每日自动更新计划任务（git pull，静默失败不打扰）。
  支持 -Uninstall 安全卸载（只删 junction 与计划任务，绝不删除真身）。

.PARAMETER Uninstall
  卸载：删除所有平台的 junction 与计划任务。真身目录保留。

.PARAMETER SkipScheduledTask
  跳过计划任务注册（仅安装 junction）。

.PARAMETER Quiet
  减少输出。

.EXAMPLE
  .\install.ps1               # 安装到所有已安装的 agent 平台 + 注册每日更新
  .\install.ps1 -Uninstall    # 卸载（保留真身）
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$SkipScheduledTask,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$TrueRoot  = $PSScriptRoot
$TaskName  = 'AgencyAgentsUpdate'
$Script:Installed = @()
$Script:Skipped   = @()

function Write-Info { if (-not $Quiet) { Write-Host "  $args" -ForegroundColor Cyan } }
function Write-OK   { if (-not $Quiet) { Write-Host "  [OK] $args" -ForegroundColor Green } }
function Write-Warn { if (-not $Quiet) { Write-Host "  [!!] $args" -ForegroundColor Yellow } }

# 已知 agent 平台的 skills 根目录（只处理实际存在的）
$Platforms = @(
    @{ Name = 'Trae CN';      Path = Join-Path $HOME '.trae-cn\skills' },
    @{ Name = 'CodeBuddy';    Path = Join-Path $HOME '.codebuddy\skills' },
    @{ Name = 'Codex';        Path = Join-Path $HOME '.codex\skills' },
    @{ Name = 'opencode';     Path = Join-Path $HOME '.config\opencode\skills' },
    @{ Name = 'Claude Code';  Path = Join-Path $HOME '.claude\skills' },
    @{ Name = '.agents通用';  Path = Join-Path $HOME '.agents\skills' }
)

function Get-LinkItem([string]$Path) {
    # 返回项：LinkType 非空 = junction/符号链接；否则为真实目录；不存在返回 $null
    if (-not (Test-Path $Path)) { return $null }
    return Get-Item $Path -Force -ErrorAction SilentlyContinue
}

function Remove-Link([string]$Path) {
    # 安全删除链接：只用 .NET 删除目录项本身，绝不递归进入目标（防误删真身）
    if (-not (Test-Path $Path)) { return }
    [System.IO.Directory]::Delete($Path)
}

function Install-Platform($Platform) {
    $root = $Platform.Path
    if (-not (Test-Path $root)) { return }              # 该平台未安装，跳过
    $link = Join-Path $root 'agency-agents'

    # 关键防护：平台入口路径 == 真身路径（真身恰好位于某平台扫描目录）→ 真身即入口，无需 junction
    if ([System.IO.Path]::GetFullPath($link) -ieq [System.IO.Path]::GetFullPath($TrueRoot)) {
        $Script:Skipped += "$($Platform.Name)(真身即入口)"
        Write-Info "$($Platform.Name)：真身即扫描目录，直接可用"
        return
    }

    $item = Get-LinkItem $link
    if ($null -eq $item) {
        # 全新安装
        New-Item -ItemType Junction -Path $link -Target $TrueRoot -ErrorAction Stop | Out-Null
        $Script:Installed += $Platform.Name
        Write-OK "$($Platform.Name)：已建立链接 -> $TrueRoot"
        return
    }
    if ($item.LinkType -and $item.Target -eq $TrueRoot) {
        # 已是正确的 junction：幂等跳过
        $Script:Skipped += $Platform.Name
        Write-Info "$($Platform.Name)：已就绪，跳过"
        return
    }
    # 存在旧链接（指向别处）或旧真实拷贝
    if ($item.LinkType) {
        Write-Info "$($Platform.Name)：存在旧链接（-> $($item.Target)），替换"
        Remove-Link $link
    } else {
        # 旧真实目录：备份而非直接删除（安全优先）；备份失败则跳过该平台，不中断
        $bak = "$link.bak-$((Get-Date).ToString('yyyyMMddHHmmss'))"
        try {
            Move-Item $link $bak -ErrorAction Stop
            Write-Warn "$($Platform.Name)：检测到旧拷贝目录，已备份为 $bak"
        } catch {
            Write-Warn "$($Platform.Name)：旧拷贝备份失败（$($_.Exception.Message)），跳过该平台"
            return
        }
    }
    New-Item -ItemType Junction -Path $link -Target $TrueRoot -ErrorAction Stop | Out-Null
    $Script:Installed += $Platform.Name
    Write-OK "$($Platform.Name)：已重建链接 -> $TrueRoot"
}

function Register-UpdateTask {
    if (-not (Test-Path (Join-Path $TrueRoot 'update.ps1'))) {
        Write-Warn 'update.ps1 不存在，跳过计划任务注册'
        return
    }
    # 使用 PowerShell 原生 ScheduledTasks cmdlet：比 schtasks.exe 更可靠（无 stderr 兼容问题、无需存储密码）
    try {
        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrueRoot\update.ps1`""
        $trigger = New-ScheduledTaskTrigger -Daily -At 09:00
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Force -ErrorAction Stop | Out-Null
        Write-OK "计划任务 $TaskName：已注册（每天 09:00 自动 git pull）"
    } catch {
        Write-Warn "计划任务注册失败：$($_.Exception.Message)（不影响安装；可手动用 schtasks 注册）"
    }
}

function Uninstall-UpdateTask {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-OK "计划任务 $TaskName 已删除"
        } else {
            Write-Info "计划任务 $TaskName 不存在，跳过"
        }
    } catch {
        Write-Warn "删除计划任务失败：$($_.Exception.Message)（可手动执行：schtasks /delete /tn $TaskName /f）"
    }
}

# ---------- 主流程 ----------
if (-not (Test-Path (Join-Path $TrueRoot 'SKILL.md'))) {
    Write-Host "错误：未在 $TrueRoot 找到 SKILL.md，请在仓库根目录运行本脚本。" -ForegroundColor Red
    exit 1
}

if ($Uninstall) {
    Write-Host "== 卸载 agency-agents（保留真身 $TrueRoot）==" -ForegroundColor Cyan
    Uninstall-UpdateTask
    foreach ($p in $Platforms) {
        if (-not (Test-Path $p.Path)) { continue }
        $link = Join-Path $p.Path 'agency-agents'
        $item = Get-LinkItem $link
        if ($null -ne $item -and $item.LinkType) {
            Remove-Link $link
            Write-OK "$($p.Name)：已删除链接"
        }
    }
    Write-Host "完成。真身目录未删除：$TrueRoot" -ForegroundColor Green
    exit 0
}

Write-Host "== 安装 agency-agents（真身：$TrueRoot）==" -ForegroundColor Cyan
$found = @($Platforms | Where-Object { Test-Path $_.Path })
if ($found.Count -eq 0) {
    Write-Warn '未检测到任何已知 agent 平台（Trae/CodeBuddy/Codex/opencode/Claude Code/.agents）。'
    Write-Warn '请确认至少一个平台已安装并存在其 skills 目录，再重新运行本脚本。'
}
foreach ($p in $found) { Write-Info "  - $($p.Name): $($p.Path)" }
foreach ($p in $found) { Install-Platform $p }

if (-not $SkipScheduledTask) { Register-UpdateTask } else { Write-Info '已跳过计划任务（-SkipScheduledTask）' }

Write-Host ''
Write-Host '== 安装报告 ==' -ForegroundColor Cyan
if ($Script:Installed.Count -gt 0) { Write-OK "新安装/重建：$($Script:Installed -join '、')" }
if ($Script:Skipped.Count -gt 0)   { Write-Info "已就绪跳过：$($Script:Skipped -join '、')" }
Write-Host '请重启各 agent 后即可使用（手动触发：Use Skill: agency-agents）' -ForegroundColor Green
Write-Host "注意事项：真身目录 = $TrueRoot，请勿移动或删除；如需移动，移动后重新运行本脚本即可。" -ForegroundColor Yellow
