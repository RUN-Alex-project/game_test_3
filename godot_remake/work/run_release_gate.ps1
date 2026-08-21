# Unified release gate (第四轮拒签整改) - deterministic sequence, re-runnable:
#   1) python docs/doc_gate.py
#   2) forward exe natural-exit smoke
#   3) sha_missing / wrong_hash / sha_dup / sha_bad_format negatives
#   4) early non-zero exit negative
#   5) log_script_error / log_error negatives
#   6) timeout negative
#   7) ready_missing negative
#   8) every step must return its expected exit code; any unexpected pass/fail/code -> gate Exit 1
#   9) only when all pass -> "RELEASE_GATE PASS"
# Logs every step + failed-log paths to $env:RELEASE_GATE_LOG (default work/release_gate.log).
$ErrorActionPreference = 'Stop'

# 工程根与日志路径都从脚本自身位置推导。此前两者都是开发机绝对路径，
# 换克隆位置或换账户就无法复跑（tools/check_linux_portability.py 现已把
# 已入库的 tools/ 与 work/ 脚本纳入绝对路径扫描，防止复发）。
# 日志可用 RELEASE_GATE_LOG 覆盖；默认落在 work/ 内（*.log 已被 .gitignore 排除）。
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gateLog = if ($env:RELEASE_GATE_LOG) { $env:RELEASE_GATE_LOG } else { Join-Path $PSScriptRoot 'release_gate.log' }
Start-Transcript -Path $gateLog -Force | Out-Null

function Gate-Fail([string]$msg) {
    Write-Host "RELEASE_GATE FAIL: $msg"
    Stop-Transcript | Out-Null
    exit 1
}

$smoke = Join-Path $PSScriptRoot 'smoke_release_exe.ps1'

# ---- 1) doc_gate ----
Write-Host "STEP 1: doc_gate"
& python (Join-Path $project 'docs\doc_gate.py')
if ($LASTEXITCODE -ne 0) { Gate-Fail "doc_gate exited $LASTEXITCODE (expected 0)" }
Write-Host "STEP 1 OK"

# ---- 2) forward smoke ----
Write-Host "STEP 2: forward exe smoke"
& $smoke | Out-Null
if ($LASTEXITCODE -ne 0) { Gate-Fail "forward smoke exited $LASTEXITCODE (expected 0); see smoke log in transcript" }
Write-Host "STEP 2 OK"

# ---- 3) SHA negatives (each must exit 1) ----
$shaNegs = @('sha_missing', 'wrong_hash', 'sha_dup', 'sha_bad_format')
foreach ($n in $shaNegs) {
    Write-Host "STEP 3: negative $n"
    & $smoke -Negative $n | Out-Null
    if ($LASTEXITCODE -ne 1) { Gate-Fail "negative $n exited $LASTEXITCODE (expected 1)" }
}
Write-Host "STEP 3 OK (4 SHA negatives rejected)"

# ---- 4) early non-zero exit ----
Write-Host "STEP 4: early_exit negative"
& $smoke -Negative early_exit | Out-Null
if ($LASTEXITCODE -ne 1) { Gate-Fail "early_exit exited $LASTEXITCODE (expected 1)" }
Write-Host "STEP 4 OK"

# ---- 5) log negatives ----
foreach ($n in @('log_script_error', 'log_error')) {
    Write-Host "STEP 5: negative $n"
    & $smoke -Negative $n | Out-Null
    if ($LASTEXITCODE -ne 1) { Gate-Fail "negative $n exited $LASTEXITCODE (expected 1)" }
}
Write-Host "STEP 5 OK"

# ---- 6) timeout ----
Write-Host "STEP 6: timeout negative"
& $smoke -Negative timeout | Out-Null
if ($LASTEXITCODE -ne 1) { Gate-Fail "timeout exited $LASTEXITCODE (expected 1)" }
Write-Host "STEP 6 OK"

# ---- 7) ready marker missing ----
Write-Host "STEP 7: ready_missing negative"
& $smoke -Negative ready_missing | Out-Null
if ($LASTEXITCODE -ne 1) { Gate-Fail "ready_missing exited $LASTEXITCODE (expected 1)" }
Write-Host "STEP 7 OK"

# ---- 7b) nested-cleanup negative ----
Write-Host "STEP 7b: cleanup_nested negative"
& $smoke -Negative cleanup_nested | Out-Null
if ($LASTEXITCODE -ne 1) { Gate-Fail "cleanup_nested exited $LASTEXITCODE (expected 1)" }
Write-Host "STEP 7b OK"

Write-Host "RELEASE_GATE PASS"
Stop-Transcript | Out-Null
exit 0
