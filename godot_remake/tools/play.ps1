# 一键启动本机发布包，启动前做哈希三方校验。
#
# 为什么需要它：v1.41 是非内嵌导出（embed_pck=false），exe 必须与同名 .pck 放在一起；
# 单独移动 exe 会启动失败。本脚本先确认两个文件都在、哈希与 build_manifest.json 和
# SHA256SUMS.txt 三方一致，再启动，避免"能不能玩"变成一次盲试。
#
# 用法：
#   .\tools\play.ps1                 校验后启动
#   .\tools\play.ps1 -VerifyOnly     只校验不启动
param(
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'

$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $project 'artifacts\releases\v1.41'
$manifestPath = Join-Path $releaseDir 'build_manifest.json'
$shaPath = Join-Path $releaseDir 'SHA256SUMS.txt'

function Fail([string]$msg) {
    Write-Host "PLAY FAIL: $msg"
    exit 1
}

if (-not (Test-Path $releaseDir)) {
    Write-Host "PLAY FAIL: 发布目录不存在: $releaseDir"
    Write-Host "  发布产物不入库。先重建："
    Write-Host "    python work\v155\rebuild_release.py"
    Write-Host "  重建前请确认已设 GODOT_EXE 指向真实的 Godot 4.6.3 可执行文件。"
    exit 1
}
if (-not (Test-Path $manifestPath)) { Fail "build_manifest.json 不存在；先跑 python work\v155\rebuild_release.py" }
if (-not (Test-Path $shaPath)) { Fail "SHA256SUMS.txt 不存在；先跑 python work\v155\rebuild_release.py" }

$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$exeName = [string]$manifest.executable
$pckName = [string]$manifest.pck.file
$exePath = Join-Path $releaseDir $exeName
$pckPath = Join-Path $releaseDir $pckName

if (-not (Test-Path $exePath)) { Fail "exe 不存在: $exeName；先跑 python work\v155\rebuild_release.py" }
if (-not (Test-Path $pckPath)) { Fail "pck 不存在: $pckName；非内嵌导出必须与 exe 同目录同名" }

# 非内嵌导出靠"exe 与 pck 同基名"定位资源包，基名不一致会静默启动失败。
$exeBase = [System.IO.Path]::GetFileNameWithoutExtension($exeName)
$pckBase = [System.IO.Path]::GetFileNameWithoutExtension($pckName)
if ($exeBase -ne $pckBase) { Fail "exe 与 pck 基名不一致（$exeBase / $pckBase），非内嵌导出无法定位资源包" }

# SHA256SUMS 解析（与 work/smoke_release_exe.ps1 同格式：64 位小写十六进制 + 两个空格 + 文件名）
$shaMap = @{}
foreach ($line in (Get-Content $shaPath -Encoding UTF8)) {
    if (-not $line.Trim()) { continue }
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { Fail "SHA256SUMS 行格式非法: [$line]" }
    $name = $Matches[2]
    if ($shaMap.ContainsKey($name)) { Fail "SHA256SUMS 同文件名重复: $name" }
    $shaMap[$name] = $Matches[1].ToLower()
}

function Verify-ThreeWay([string]$name, [string]$path, [string]$manifestHash) {
    $actual = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
    if (-not $shaMap.ContainsKey($name)) { Fail "SHA256SUMS 缺少记录: $name" }
    if ($actual -ne $shaMap[$name]) { Fail "$name 实际哈希 $($actual.Substring(0,12)) != SHA256SUMS $($shaMap[$name].Substring(0,12))" }
    if ($manifestHash -and $actual -ne $manifestHash.ToLower()) {
        Fail "$name 实际哈希 $($actual.Substring(0,12)) != build_manifest $($manifestHash.Substring(0,12))"
    }
    Write-Host "  HASH OK  $name  $($actual.Substring(0,16))..."
}

Write-Host "PLAY 校验 $releaseDir"
Verify-ThreeWay $exeName $exePath ([string]$manifest.executable_hash_sha256)
Verify-ThreeWay $pckName $pckPath ([string]$manifest.pck.sha256)

if ([bool]$manifest.executable_stale) { Fail "build_manifest 标记 exe 为 stale，先重建" }

Write-Host "PLAY VERIFY OK: exe 与 pck 哈希三方一致，基名匹配，非内嵌导出可启动"
if ($VerifyOnly) { exit 0 }

Write-Host "PLAY 启动 $exeName"
Start-Process -FilePath $exePath -WorkingDirectory $releaseDir
Write-Host "PLAY 已启动（窗口独立于本终端）。存档写在 Godot 的 user:// 目录，不在发布目录内。"
exit 0