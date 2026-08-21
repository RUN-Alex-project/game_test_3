# 导出"单文件可玩包"：embed_pck=true，一个 exe 就能双击运行，不依赖同目录的 .pck。
#
# 与 artifacts/releases/v1.41/ 的关系：那一份是已签署的发布候选（非内嵌，exe+pck 成对，
# 哈希被签署文档记录），本脚本不碰它。单文件包输出到 artifacts/playable/，不入库。
#
# 用法：
#   .\tools\build_playable.ps1
# 前置：GODOT_EXE 指向真实 Godot 4.6.3；已安装对应版本导出模板。
$ErrorActionPreference = 'Stop'

$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outDir = Join-Path $project 'artifacts\playable'
$exeName = '魔域1.03_v1.41_单文件.exe'
$outExe = Join-Path $outDir $exeName
$presetName = 'Playable Single File'

function Fail([string]$msg) {
    Write-Host "BUILD_PLAYABLE FAIL: $msg"
    exit 1
}

# Godot 解析与 tools/godot_env.py 同口径，避免两套顺序
$godot = $env:GODOT_BIN
if (-not $godot) { $godot = $env:GODOT_EXE }
if (-not $godot) { $cmd = Get-Command godot4 -ErrorAction SilentlyContinue; if ($cmd) { $godot = $cmd.Source } }
if (-not $godot) { $cmd = Get-Command godot -ErrorAction SilentlyContinue; if ($cmd) { $godot = $cmd.Source } }
if (-not $godot -or -not (Test-Path $godot)) {
    Fail "找不到 Godot。解析顺序：GODOT_BIN > GODOT_EXE > godot4 > godot"
}
$version = (& $godot --version 2>$null | Out-String).Trim()
if (-not $version) { Fail "$godot 跑不出版本，可能是 0 字节符号链接；请指向真实可执行文件" }
Write-Host "BUILD_PLAYABLE godot=$godot version=$version"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# Godot 是 GUI 子系统程序，用 & 调用不会阻塞（$LASTEXITCODE 会是上一条命令的），
# 必须 Start-Process -PassThru + WaitForExit，与 work/smoke_release_exe.ps1 同做法。
$exportLog = Join-Path $outDir 'export.log'
Write-Host "BUILD_PLAYABLE 导出预设 [$presetName] -> $outExe"
# Start-Process -ArgumentList 用空格拼接数组元素且不代加引号，
# 预设名与路径含空格时必须自己加引号，否则 "Playable Single File" 会被拆成三个参数。
$argList = @(
    '--headless',
    '--path', ('"' + $project + '"'),
    '--export-release', ('"' + $presetName + '"'), ('"' + $outExe + '"'),
    '--log-file', ('"' + $exportLog + '"')
)
$proc = Start-Process -FilePath $godot -ArgumentList $argList -PassThru -WindowStyle Hidden
if (-not $proc.WaitForExit(1800 * 1000)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Fail "导出超时（30 分钟）未自然退出"
}
if ($proc.ExitCode -ne 0) { Fail "导出失败 exit $($proc.ExitCode)；见 $exportLog（检查是否已安装 $version 的导出模板）" }
if (-not (Test-Path $outExe)) { Fail "导出后未生成 $outExe；见 $exportLog" }

# 内嵌导出的自检：单文件包内必须含 GDPC 资源包签名，否则 embed_pck 没生效
$bytes = [System.IO.File]::ReadAllBytes($outExe)
$hasGdpc = $false
for ($i = 0; $i -lt $bytes.Length - 4; $i++) {
    if ($bytes[$i] -eq 0x47 -and $bytes[$i+1] -eq 0x44 -and $bytes[$i+2] -eq 0x50 -and $bytes[$i+3] -eq 0x43) { $hasGdpc = $true; break }
}
if (-not $hasGdpc) { Fail "单文件包内未找到 GDPC 签名，embed_pck 未生效" }

$hash = (Get-FileHash -Path $outExe -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $outExe).Length
"$hash  $exeName" | Set-Content -Path (Join-Path $outDir 'SHA256SUMS.txt') -Encoding UTF8

Write-Host "BUILD_PLAYABLE OK"
Write-Host "  文件: $outExe"
Write-Host "  大小: $size 字节"
Write-Host "  SHA256: $hash"
Write-Host "  单文件包可整体拷走双击运行；存档写在 Godot 的 user:// 目录。"
exit 0