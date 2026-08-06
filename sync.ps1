<#
.SYNOPSIS
    从上游 msitarzewski/agency-agents 同步角色数据，重建本目录 roles-index.json。

.DESCRIPTION
    1. 浅克隆/更新上游仓库到临时目录
    2. 读取 divisions.json 得到权威部门列表
    3. 解析各部门角色文件的 frontmatter（name/description），slug 用 slugify(name) 生成
    4. 合并 zh-overrides.json 的中文覆盖（slug -> 中文 name/brief）
    5. 重建 roles-index.json，写入 last_updated 与 upstream_sha
    6. 校验 tool-mappings.json 引用的 slug 是否全部存在，缺失则报警

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\sync.ps1
#>
param(
    [string]$RepoUrl  = "https://github.com/msitarzewski/agency-agents",
    [string]$WorkDir  = $(if ($env:TEMP)   { "$env:TEMP\agency-agents-sync" }
                           elseif ($env:TMPDIR) { "$env:TMPDIR/agency-agents-sync" }
                           else { "/tmp/agency-agents-sync" }),
    [string]$OutputPath = "$PSScriptRoot\roles-index.json"
)

# 注意：PowerShell 5 中 $ErrorActionPreference="Stop" 会把 native 命令（git）的 stderr
# 提升为终止错误。这里用 Continue + $LASTEXITCODE 显式检查失败。
$ErrorActionPreference = "Continue"

function Get-Field {
    # 从角色文件 frontmatter 提取字段值（name/description 等）
    param([string]$Field, [string]$File)
    $line = Select-String -Path $File -Pattern ("^{0}: " -f $Field) | Select-Object -First 1
    if ($line) { return $line.Line.Substring($Field.Length + 2).Trim() }
    return $null
}

function Get-Slug {
    # 与上游 scripts/lib.sh 的 slugify 一致："Backend Architect" -> "backend-architect"
    param([string]$Name)
    $slug = $Name.ToLowerInvariant() -replace '[^a-z0-9]', '-'
    $slug = $slug -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
    return $slug
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

# ---------- 1. 获取上游仓库 ----------
Write-Host "[1/6] 获取上游仓库 $RepoUrl ..." -ForegroundColor Cyan
if (-not (Test-Path $WorkDir)) {
    git clone --depth 1 $RepoUrl $WorkDir 2>$null | Out-Null
} else {
    git -C $WorkDir fetch --depth 1 origin 2>$null | Out-Null
    git -C $WorkDir reset --hard origin/main 2>$null | Out-Null
}
if ($LASTEXITCODE -ne 0) { throw "git 操作失败 (exit=$LASTEXITCODE)，请检查网络与仓库地址" }
$upstreamSha = (git -C $WorkDir rev-parse HEAD 2>$null).Trim()
Write-Host "      上游 commit: $upstreamSha" -ForegroundColor DarkGray

# ---------- 2. 读取 divisions.json ----------
Write-Host "[2/6] 读取权威部门列表 divisions.json ..." -ForegroundColor Cyan
$divisionsRaw = Get-Content -Raw "$WorkDir\divisions.json" | ConvertFrom-Json
$divisionKeys = @($divisionsRaw.divisions.PSObject.Properties.Name)

# ---------- 3. 解析角色 frontmatter ----------
Write-Host "[3/6] 解析角色文件 frontmatter ..." -ForegroundColor Cyan
$roles = @{}
foreach ($div in $divisionKeys) {
    $dir = Join-Path $WorkDir $div
    if (-not (Test-Path $dir)) { continue }
    $files = Get-ChildItem -Path $dir -Filter "*.md" -File
    foreach ($file in $files) {
        $firstLine = Get-Content -Path $file.FullName -TotalCount 1
        if ($firstLine -ne "---") { continue }   # 跳过无 frontmatter 的非角色文档
        $name = Get-Field "name" $file.FullName
        if (-not $name) { continue }
        $slug = Get-Slug $name
        $desc = Get-Field "description" $file.FullName
        if ($desc.Length -gt 100) { $desc = $desc.Substring(0, 100) }
        $roles[$slug] = @{ division = $div; name = $name; brief = $desc }
    }
}
Write-Host "      解析到 $($roles.Count) 个角色（$($divisionKeys.Count) 个部门）" -ForegroundColor DarkGray

# ---------- 4. 合并中文覆盖 ----------
Write-Host "[4/6] 合并 zh-overrides.json 中文覆盖 ..." -ForegroundColor Cyan
$overridesPath = Join-Path $PSScriptRoot "zh-overrides.json"
$overrides = @{}
if (Test-Path $overridesPath) {
    $overrides = (Get-Content -Raw $overridesPath | ConvertFrom-Json).roles
}
foreach ($prop in $overrides.PSObject.Properties) {
    $slug = $prop.Name
    if ($roles.ContainsKey($slug)) {
        if ($prop.Value.name)  { $roles[$slug].name  = $prop.Value.name }
        if ($prop.Value.brief) { $roles[$slug].brief = $prop.Value.brief }
    }
}

# ---------- 5. 重建 roles-index.json ----------
Write-Host "[5/6] 重建 $OutputPath ..." -ForegroundColor Cyan
$index = [ordered]@{
    _note        = "自动生成：由 sync.ps1 从上游 msitarzewski/agency-agents 重建，勿手改。中文名/简介由 zh-overrides.json 覆盖提供。"
    source       = $RepoUrl
    last_updated = (Get-Date -Format "yyyy-MM-dd")
    upstream_sha = $upstreamSha
    divisions    = [ordered]@{}
}
foreach ($div in $divisionKeys) {
    $meta = $divisionsRaw.divisions.$div
    $divRoles = @($roles.GetEnumerator() | Where-Object { $_.Value.division -eq $div } | ForEach-Object {
        [ordered]@{ slug = $_.Key; name = $_.Value.name; brief = $_.Value.brief }
    } | Sort-Object { $_.slug })
    if ($divRoles.Count -eq 0) { continue }
    $index.divisions[$div] = [ordered]@{
        label = $meta.label
        icon  = $meta.icon
        color = $meta.color
        roles = $divRoles
    }
}
$json = $index | ConvertTo-Json -Depth 6
Write-Utf8NoBom $OutputPath $json
Write-Host "      部门数: $($index.divisions.Count), 角色数: $($roles.Count)" -ForegroundColor DarkGray

# ---------- 6. 校验 tool-mappings.json 引用 ----------
Write-Host "[6/6] 校验 tool-mappings.json 引用的 slug ..." -ForegroundColor Cyan
$mappingsPath = Join-Path $PSScriptRoot "tool-mappings.json"
$referenced = @()
if (Test-Path $mappingsPath) {
    $mappings = Get-Content -Raw $mappingsPath | ConvertFrom-Json
    foreach ($m in $mappings.mappings) {
        foreach ($r in $m.roles) { if ($r -notin $referenced) { $referenced += $r } }
    }
}
$missing = @($referenced | Where-Object { -not $roles.ContainsKey($_) })
if ($missing.Count -gt 0) {
    Write-Host "      [WARN] 以下映射引用的 slug 在索引中不存在: $($missing -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "      引用 $($referenced.Count) 个 slug 全部存在，校验通过" -ForegroundColor Green
}

Write-Host "同步完成。可用 SKILL.md 的运行时拉取逻辑继续自动刷新缓存。" -ForegroundColor Green
