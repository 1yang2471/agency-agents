<#
.SYNOPSIS
  静默自动更新脚本：git pull --ff-only 拉取仓库最新版本。

.DESCRIPTION
  由计划任务（install.ps1 注册）每日调用。
  任何失败只写入 update.log，不弹出窗口、不打断用户。
  若仓库非 git 克隆（如 ZIP 解压），脚本直接跳过并记日志。
#>
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$Log  = Join-Path $Root 'update.log'

if (-not (Test-Path (Join-Path $Root '.git'))) {
    Add-Content -Path $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 非 git 克隆安装，跳过自动更新（建议改用 git clone 安装）" -Encoding UTF8
    exit 0
}

try {
    $result = git -C $Root pull --ff-only 2>&1 | Out-String
    Add-Content -Path $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] pull: $result" -Encoding UTF8
} catch {
    Add-Content -Path $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 更新异常：$($_.Exception.Message)" -Encoding UTF8
}
