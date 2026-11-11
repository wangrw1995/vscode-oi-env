<#
.SYNOPSIS
    一键部署 VS Code OI 环境（扩展 + 用户配置 + 项目模板）。

.DESCRIPTION
    1. 检查 VS Code / g++ / python 是否存在
    2. 安装 config/extensions.txt 里列出的扩展
    3. 把 config/settings.patch.json 合并进用户 settings.json（保留已有配置）
    4. 把 config/keybindings.json 里的 F5 绑定合并进用户 keybindings.json
    5. 把 template/ 复制到目标题目目录（默认 ~\Documents\OI）

.PARAMETER Target
    模板复制到哪个文件夹，默认 $env:USERPROFILE\Documents\OI

.PARAMETER SkipExtensions
    跳过扩展安装

.PARAMETER SkipConfig
    跳过用户 settings.json / keybindings.json 的写入

.EXAMPLE
    .\scripts\install.ps1
    .\scripts\install.ps1 -Target D:\OI -SkipExtensions

.NOTES
    在 Windows PowerShell 5.1 与 PowerShell 7 下均可运行。
    本文件必须保存为 UTF-8 **带 BOM**，否则 PowerShell 5.1 会按 ANSI 解析中文而报语法错误。
#>
[CmdletBinding()]
param(
    [string]$Target = (Join-Path $env:USERPROFILE 'Documents\OI'),
    [switch]$SkipExtensions,
    [switch]$SkipConfig
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path $repoRoot 'config'
$templateDir = Join-Path $repoRoot 'template'
$userDir = Join-Path $env:APPDATA 'Code\User'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# PowerShell 5.1 的 Get-Content 默认按 ANSI 解码，会把 UTF-8 中文读成乱码。
# 所有文本读取都走 .NET 的显式 UTF-8。
function Read-Utf8 { param([string]$Path) [System.IO.File]::ReadAllText($Path, $utf8) }
function Write-Utf8 { param([string]$Path, [string]$Text) [System.IO.File]::WriteAllText($Path, $Text, $utf8) }

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "    [!!] $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 1. 探测
Write-Step '探测环境'

$code = $null
foreach ($p in @(
        'C:\Program Files\Microsoft VS Code\bin\code.cmd',
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'))) {
    if (Test-Path $p) { $code = $p; break }
}
if (-not $code) {
    $cmd = Get-Command code -ErrorAction SilentlyContinue
    if ($cmd) { $code = $cmd.Source }
}
if ($code) { Write-Ok "VS Code: $code" }
else { Write-Warn2 'VS Code 未找到，扩展安装会跳过；请先安装 VS Code' }

$gxx = $null
foreach ($p in @('C:\w64devkit\bin\g++.exe', 'C:\mingw64\bin\g++.exe')) {
    if (Test-Path $p) { $gxx = $p; break }
}
if (-not $gxx) {
    $cmd = Get-Command g++ -ErrorAction SilentlyContinue
    if ($cmd) { $gxx = $cmd.Source }
}
if ($gxx) { Write-Ok "g++: $gxx" }
else { throw 'g++ 未找到。请安装 MinGW-w64（推荐 w64devkit）后重试。' }

$gccDir = Split-Path $gxx -Parent
$gcc = Join-Path $gccDir 'gcc.exe'
$objcopy = Join-Path $gccDir 'objcopy.exe'
if (-not (Test-Path $gcc)) { $gcc = $gxx }

$python = $null
$cmd = Get-Command python -ErrorAction SilentlyContinue
if ($cmd) { $python = $cmd.Source }
if ($python) { Write-Ok "python: $python" }
else { Write-Warn2 'python 未找到，python.defaultInterpreterPath 会留空' }

# ------------------------------------------------------------ 2. 扩展
if (-not $SkipExtensions) {
    Write-Step '安装 VS Code 扩展'
    if ($code) {
        $list = [System.IO.File]::ReadAllLines((Join-Path $configDir 'extensions.txt'), $utf8) |
                Where-Object { $_ -and $_.Trim() -and $_.Trim() -notmatch '^#' }
        foreach ($ext in $list) {
            $id = $ext.Trim()
            Write-Host "    -> $id"
            & $code --install-extension $id --force 2>&1 | Out-Null
        }
        Write-Ok "扩展安装完成（$($list.Count) 个）"
    } else {
        Write-Warn2 '跳过：找不到 code 命令'
    }
}

# ------------------------------------------------------- 3. 用户配置
if (-not $SkipConfig) {
    Write-Step '写入用户配置'
    if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Force -Path $userDir | Out-Null }

    # --- settings.json（保留已有键，同键以本仓库为准）
    $settingsPath = Join-Path $userDir 'settings.json'
    $patch = Read-Utf8 (Join-Path $configDir 'settings.patch.json') | ConvertFrom-Json
    $merged = [ordered]@{}
    if (Test-Path $settingsPath) {
        $raw = Read-Utf8 $settingsPath
        if ($raw -and $raw.Trim()) {
            try {
                (ConvertFrom-Json $raw).PSObject.Properties | ForEach-Object { $merged[$_.Name] = $_.Value }
            } catch {
                Copy-Item $settingsPath "$settingsPath.bak" -Force
                Write-Warn2 '原 settings.json 无法解析，已备份为 settings.json.bak'
            }
        }
    }
    foreach ($prop in $patch.PSObject.Properties) {
        if ($prop.Name -like '__*') { continue }
        $val = $prop.Value
        if ($val -is [string]) {
            $val = $val.Replace('__GXX__', $gxx).Replace('__GCC__', $gcc).
                       Replace('__OBJCOPY__', $objcopy).Replace('__PYTHON__', [string]$python)
        }
        $merged[$prop.Name] = $val
    }
    Write-Utf8 $settingsPath (ConvertTo-Json -InputObject $merged -Depth 12)
    Write-Ok "settings.json 已更新: $settingsPath"

    # --- keybindings.json（保留已有绑定，只补 F5）
    $kbPath = Join-Path $userDir 'keybindings.json'
    $entry = Read-Utf8 (Join-Path $configDir 'keybindings.json') | ConvertFrom-Json
    $entryJson = ($entry | ConvertTo-Json -Depth 6) -replace '^\s*\[\s*', '' -replace '\s*\]\s*$', ''
    $existingKb = if (Test-Path $kbPath) { Read-Utf8 $kbPath } else { '' }
    if ($existingKb -match 'workbench\.action\.tasks\.runTask') {
        Write-Warn2 'keybindings.json 里已有 runTask 绑定，跳过（避免重复）'
    } elseif ($existingKb.Trim()) {
        $idx = $existingKb.IndexOf('[')
        if ($idx -ge 0) {
            $new = $existingKb.Substring(0, $idx + 1) + "`r`n" + $entryJson + ',' + $existingKb.Substring($idx + 1)
            Write-Utf8 $kbPath $new
            Write-Ok "keybindings.json 已追加 F5 绑定（原内容保留）: $kbPath"
        } else {
            Write-Warn2 'keybindings.json 格式意外，未修改'
        }
    } else {
        Write-Utf8 $kbPath ($entry | ConvertTo-Json -Depth 6)
        Write-Ok "keybindings.json 已创建: $kbPath"
    }
}

# ------------------------------------------------------------- 4. 模板
Write-Step "复制项目模板到 $Target"
if (-not (Test-Path $Target)) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }
$copied = 0
Get-ChildItem $templateDir -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($templateDir.Length).TrimStart('\')
    $dest = Join-Path $Target $rel
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest; $copied++ }
}
Write-Ok "复制 $copied 个文件（已存在的不覆盖）"

# 把模板里的绝对路径换成探测到的路径（JSON 里是双反斜杠转义）
$gdb = Join-Path $gccDir 'gdb.exe'
$gxxJson = $gxx.Replace('\', '\\')
$gdbJson = $gdb.Replace('\', '\\')
foreach ($f in @(
        (Join-Path $Target '.vscode\c_cpp_properties.json'),
        (Join-Path $Target '.vscode\launch.json'))) {
    if (Test-Path $f) {
        $txt = Read-Utf8 $f
        $txt = $txt.Replace('C:\\w64devkit\\bin\\g++.exe', $gxxJson).
                   Replace('C:/w64devkit/bin/g++.exe', ($gxx -replace '\\', '/'))
        $txt = $txt.Replace('C:\\w64devkit\\bin\\gdb.exe', $gdbJson)
        Write-Utf8 $f $txt
    }
}

Write-Host "`n全部完成。" -ForegroundColor Green
Write-Host "下一步：用 VS Code 打开 $Target ，打开 aplusb.cpp 按 F5；" -ForegroundColor Gray
Write-Host "        或者在 CPH-NG 侧边栏 From folder 导入 tests/ 目录后按 Ctrl+Alt+B。" -ForegroundColor Gray
