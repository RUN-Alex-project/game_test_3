# exe smoke test (re-runnable validator, P1-3 / 第三轮 + 第四轮):
# Reusable hash validator: exe exists, exactly ONE exe entry in manifest, exactly ONE exe line
# in SHA256SUMS, and all three hashes exactly equal. Missing/duplicate/malformed entries all fail.
# FORWARD: hash three-way -> natural exit (--headless --quit-after) -> ExitCode 0 ->
#          multi-line log checks (SCRIPT ERROR: / ^ERROR: / FAILED / Assertion failed /
#          ObjectDB instances leaked) -> APP_READY:main_original marker -> delete log on success.
# NEGATIVES reuse the SAME validators against a temp-copied release dir (no special-case branches):
#   wrong_hash (tamper manifest), sha_missing (remove exe line), sha_dup (duplicate exe line),
#   sha_bad_format (malformed line), early_exit, timeout, log_script_error, log_error, ready_missing.
param(
    [string]$Negative = "",
    [int]$QuitAfter = 300,
    [int]$TimeoutSec = 60
)
$ErrorActionPreference = 'Stop'

$releaseDir = Join-Path $PSScriptRoot '..\artifacts\releases\v1.41'
$manifestPath = Join-Path $releaseDir 'build_manifest.json'
$shaPath = Join-Path $releaseDir 'SHA256SUMS.txt'
$tmpDir = Join-Path $env:TEMP ("smoke-tmp-" + [Guid]::NewGuid().ToString("N"))
$logPath = Join-Path $env:TEMP ("godot-exe-smoke-" + [Guid]::NewGuid().ToString("N") + ".log")

function Fail([string]$msg) { Write-Host "SMOKE FAIL: $msg"; exit 1 }
function NegOk([string]$msg) { Write-Host "SMOKE NEG ok: $msg"; exit 1 }

function Get-ExeName($dir) {
    $m = Get-Content (Join-Path $dir 'build_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    return [string]$m.executable
}

# ---- Reusable hash validator (three-way, self-sufficient) ----
# Returns $true + prints reason, or $false + prints precise failure reason.
function Test-HashThreeWay($dir) {
    $mPath = Join-Path $dir 'build_manifest.json'
    $sPath = Join-Path $dir 'SHA256SUMS.txt'
    if (-not (Test-Path $mPath)) { Write-Host "HASH FAIL: manifest missing"; return $false }
    if (-not (Test-Path $sPath)) { Write-Host "HASH FAIL: SHA256SUMS missing"; return $false }
    $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $exeName = [string]$m.executable
    if (-not $exeName) { Write-Host "HASH FAIL: manifest has no executable entry"; return $false }
    $exePath = Join-Path $dir $exeName
    if (-not (Test-Path $exePath)) { Write-Host "HASH FAIL: exe file missing: $exeName"; return $false }
    $manifestHash = ([string]$m.executable_hash_sha256)
    if ($manifestHash -notmatch '^[0-9a-f]{64}$') { Write-Host "HASH FAIL: manifest hash malformed: $manifestHash"; return $false }
    # SHA256SUMS: exactly ONE line for this exe; malformed/duplicate/missing all fail
    $lines = Get-Content $sPath -Encoding UTF8
    $exeLines = @()
    foreach ($l in $lines) {
        if ($l -notmatch '^([0-9a-f]{64})  (.+)$') {
            Write-Host "HASH FAIL: malformed SHA line: [$l]"
            return $false
        }
        $h = $Matches[1].ToLower(); $n = $Matches[2]
        if ($n -eq $exeName) { $exeLines += ,@($h, $n) }
    }
    if ($exeLines.Count -eq 0) { Write-Host "HASH FAIL: no exe entry in SHA256SUMS"; return $false }
    if ($exeLines.Count -gt 1) { Write-Host "HASH FAIL: duplicate exe entries in SHA256SUMS ($($exeLines.Count))"; return $false }
    $shaHash = $exeLines[0][0]
    # three-way exact equality
    $actualHash = (Get-FileHash -Path $exePath -Algorithm SHA256).Hash.ToLower()
    if ($actualHash -ne $manifestHash) { Write-Host "HASH FAIL: exe $($actualHash.Substring(0,12)) != manifest $($manifestHash.Substring(0,12))"; return $false }
    if ($actualHash -ne $shaHash) { Write-Host "HASH FAIL: exe $($actualHash.Substring(0,12)) != SHA256SUMS $($shaHash.Substring(0,12))"; return $false }
    Write-Host "HASH OK: three-way equal ($($actualHash.Substring(0,16))...)"
    return $true
}

# ---- Reusable multi-line log validator ----
function Test-Log($log) {
    if (-not (Test-Path $log)) { Write-Host "LOG FAIL: log missing"; return $false }
    $text = Get-Content $log -Raw -Encoding UTF8
    $bad = @()
    foreach ($pat in @('SCRIPT ERROR:', '^ERROR:', 'FAILED', 'Assertion failed', 'ObjectDB instances leaked')) {
        if ([regex]::IsMatch($text, $pat, [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
            $bad += $pat
        }
    }
    if ($bad.Count -gt 0) { Write-Host "LOG FAIL: bad markers present: $($bad -join ', ')"; return $false }
    if ($text -notmatch 'APP_READY:main_original') { Write-Host "LOG FAIL: APP_READY:main_original marker missing"; return $false }
    Write-Host "LOG OK: no bad markers; APP_READY:main_original present"
    return $true
}

# ---- Reusable process-result validator (forward / early_exit / timeout all share this) ----
# Returns an object: @{ naturalExit=$bool; exitCode=$int; log=$path }
function Invoke-ProcessCheck($exePath, $argList, $log, $timeoutSec) {
    $proc = Start-Process -FilePath $exePath -ArgumentList $argList -PassThru -WindowStyle Hidden
    $natural = $proc.WaitForExit($timeoutSec * 1000)
    if (-not $natural) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        return @{ naturalExit = $false; exitCode = -1; log = $log }
    }
    return @{ naturalExit = $true; exitCode = $proc.ExitCode; log = $log }
}

function Copy-Dir($src, $dst) {
    if (Test-Path $dst) { Remove-Dir $dst }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Get-ChildItem -Path $src -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $dst $_.Name) -Force
    }
}

function Remove-Dir($dir) {
    # 第四轮补充整改：靠 -ErrorAction Stop 捕获删除失败；删除后 Test-Path 验证不存在；
    # 不得把 Remove-Item 返回值（无返回值）当布尔。
    if (-not (Test-Path $dir)) { return }
    Get-ChildItem -Path $dir -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        Remove-Item -Path $_.FullName -Force -ErrorAction Stop   # 失败抛异常
    }
    Remove-Item -Path $dir -Force -ErrorAction Stop
    if (Test-Path $dir) { throw "Remove-Dir: dir still exists after delete: $dir" }
}

# ---- NEGATIVES: each builds a temp-copied release dir and reuses the SAME validators ----
switch ($Negative) {
    "wrong_hash" {
        Copy-Dir $releaseDir $tmpDir
        $tManifest = Join-Path $tmpDir 'build_manifest.json'
        $m = Get-Content $tManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.executable_hash_sha256 = ('0' * 64)
        $m | ConvertTo-Json -Depth 10 | Set-Content -Path $tManifest -Encoding UTF8
        if (Test-HashThreeWay $tmpDir) { Fail "wrong_hash negative: tampered manifest accepted (bad fixture)" }
        Remove-Dir $tmpDir
        NegOk "wrong_hash: tampered manifest rejected by same hash validator"
    }
    "sha_missing" {
        Copy-Dir $releaseDir $tmpDir
        $tSha = Join-Path $tmpDir 'SHA256SUMS.txt'
        $exeName = Get-ExeName $tmpDir
        $kept = @(Get-Content $tSha -Encoding UTF8 | Where-Object { $_ -notmatch ([regex]::Escape($exeName) + '$') })
        Set-Content -Path $tSha -Value $kept -Encoding UTF8
        if (Test-HashThreeWay $tmpDir) { Fail "sha_missing negative: missing exe entry accepted (bad fixture)" }
        Remove-Dir $tmpDir
        NegOk "sha_missing: missing exe SHA entry rejected by same hash validator"
    }
    "sha_dup" {
        Copy-Dir $releaseDir $tmpDir
        $tSha = Join-Path $tmpDir 'SHA256SUMS.txt'
        $exeName = Get-ExeName $tmpDir
        $exeLine = @(Get-Content $tSha -Encoding UTF8 | Where-Object { $_ -match ([regex]::Escape($exeName) + '$') })[0]
        Add-Content -Path $tSha -Value $exeLine -Encoding UTF8
        if (Test-HashThreeWay $tmpDir) { Fail "sha_dup negative: duplicate exe entries accepted (bad fixture)" }
        Remove-Dir $tmpDir
        NegOk "sha_dup: duplicate exe SHA entries rejected by same hash validator"
    }
    "sha_bad_format" {
        Copy-Dir $releaseDir $tmpDir
        $tSha = Join-Path $tmpDir 'SHA256SUMS.txt'
        Add-Content -Path $tSha -Value "not-a-valid-sha-line" -Encoding UTF8
        if (Test-HashThreeWay $tmpDir) { Fail "sha_bad_format negative: malformed line accepted (bad fixture)" }
        Remove-Dir $tmpDir
        NegOk "sha_bad_format: malformed SHA line rejected by same hash validator"
    }
    "log_script_error" {
        # 先证明同一次 EXE 运行自然退出 + ExitCode 0 + 原日志通过，再注入 SCRIPT ERROR 并证明变异生效，
        # 最后由同一 Test-Log 拒绝
        $exePath = Join-Path $releaseDir (Get-ExeName $releaseDir)
        $res = Invoke-ProcessCheck $exePath @('--headless','--quit-after',"$QuitAfter",'--log-file',$logPath) $logPath $TimeoutSec
        if (-not $res.naturalExit) { Fail "log_script_error: forward run did not exit naturally (bad fixture)" }
        if ($res.exitCode -ne 0) { Fail "log_script_error: forward run exit $($res.exitCode) != 0 (bad fixture)" }
        if (-not (Test-Log $logPath)) { Fail "log_script_error: original log did not pass Test-Log (bad fixture)" }
        Add-Content -Path $logPath -Value "SCRIPT ERROR: injected" -Encoding UTF8
        if (-not (Get-Content $logPath -Raw -Encoding UTF8).Contains("SCRIPT ERROR: injected")) { Fail "log_script_error: mutation not applied (bad fixture)" }
        if (Test-Log $logPath) { Fail "log_script_error negative: injected SCRIPT ERROR accepted by same Test-Log" }
        Remove-Item -Path $logPath -Force -ErrorAction Stop
        NegOk "log_script_error: SCRIPT ERROR rejected by same Test-Log"
    }
    "log_error" {
        # 先证明同一次 EXE 运行 ExitCode=0 且原日志通过，再注入普通 ERROR 并证明变异生效，同一 Test-Log 拒绝
        $exePath = Join-Path $releaseDir (Get-ExeName $releaseDir)
        $res = Invoke-ProcessCheck $exePath @('--headless','--quit-after',"$QuitAfter",'--log-file',$logPath) $logPath $TimeoutSec
        if (-not $res.naturalExit) { Fail "log_error: forward run did not exit naturally (bad fixture)" }
        if ($res.exitCode -ne 0) { Fail "log_error: forward run exit $($res.exitCode) != 0 (bad fixture)" }
        if (-not (Test-Log $logPath)) { Fail "log_error: original log did not pass Test-Log (bad fixture)" }
        Add-Content -Path $logPath -Value "ERROR: injected" -Encoding UTF8
        if (-not (Get-Content $logPath -Raw -Encoding UTF8).Contains("ERROR: injected")) { Fail "log_error: mutation not applied (bad fixture)" }
        if (Test-Log $logPath) { Fail "log_error negative: injected ERROR accepted by same Test-Log" }
        Remove-Item -Path $logPath -Force -ErrorAction Stop
        NegOk "log_error: plain ERROR rejected by same Test-Log"
    }
    "ready_missing" {
        # 先证明同一次 EXE 运行 ExitCode=0 且原日志通过（含 APP_READY），再删除 ready 标记并证明变异生效，
        # 同一 Test-Log 拒绝
        $exePath = Join-Path $releaseDir (Get-ExeName $releaseDir)
        $res = Invoke-ProcessCheck $exePath @('--headless','--quit-after',"$QuitAfter",'--log-file',$logPath) $logPath $TimeoutSec
        if (-not $res.naturalExit) { Fail "ready_missing: forward run did not exit naturally (bad fixture)" }
        if ($res.exitCode -ne 0) { Fail "ready_missing: forward run exit $($res.exitCode) != 0 (bad fixture)" }
        if (-not (Test-Log $logPath)) { Fail "ready_missing: original log did not pass Test-Log (bad fixture)" }
        $clean = @(Get-Content $logPath -Encoding UTF8 | Where-Object { $_ -notmatch 'APP_READY:main_original' })
        Set-Content -Path $logPath -Value $clean -Encoding UTF8
        if ((Get-Content $logPath -Raw -Encoding UTF8) -match 'APP_READY:main_original') { Fail "ready_missing: mutation not applied (bad fixture)" }
        if (Test-Log $logPath) { Fail "ready_missing negative: missing ready marker accepted by same Test-Log" }
        Remove-Item -Path $logPath -Force -ErrorAction Stop
        NegOk "ready_missing: missing APP_READY marker rejected by same Test-Log"
    }
    "early_exit" {
        # 同一 Invoke-ProcessCheck：替身进程自然退出但 ExitCode=1 -> 进程验证器捕获非零退出
        $res = Invoke-ProcessCheck 'cmd.exe' @('/c','exit 1') "" 60
        if (-not $res.naturalExit) { Fail "early_exit negative: substitute did not exit (bad fixture)" }
        if ($res.exitCode -eq 0) { Fail "early_exit negative: substitute exited 0 (bad fixture)" }
        NegOk "early_exit: non-zero exit ($($res.exitCode)) detected by shared process validator"
    }
    "timeout" {
        # 同一 Invoke-ProcessCheck：替身进程不退出 -> 进程验证器返回 naturalExit=false（强制终止）
        $res = Invoke-ProcessCheck 'powershell.exe' @('-Command','Start-Sleep -Seconds 9999') "" 5
        if ($res.naturalExit) { Fail "timeout negative: substitute exited naturally (bad fixture)" }
        NegOk "timeout: no natural exit within window detected by shared process validator (forced termination; NOT clean exit)"
    }
    "cleanup_nested" {
        # 含嵌套子目录的递归清理：建 tmp/a/b + 文件 -> Remove-Dir -> 必须不存在
        $nest = Join-Path $tmpDir 'nest'
        New-Item -ItemType Directory -Path (Join-Path $nest 'sub') -Force | Out-Null
        Set-Content -Path (Join-Path $nest 'top.txt') -Value 'x' -Encoding UTF8
        Set-Content -Path (Join-Path $nest 'sub\inner.txt') -Value 'y' -Encoding UTF8
        Remove-Dir $tmpDir
        if (Test-Path $tmpDir) { Fail "cleanup_nested: nested dir still exists after Remove-Dir" }
        Write-Host "SMOKE NEG ok: cleanup_nested: nested subdir deleted and verified absent"
        exit 1  # negative established (cleanup verified)
    }
    default {
        # ---- FORWARD ----
        if (-not (Test-HashThreeWay $releaseDir)) { Fail "three-way hash verification failed" }
        $exePath = Join-Path $releaseDir (Get-ExeName $releaseDir)
        $res = Invoke-ProcessCheck $exePath @('--headless','--quit-after',"$QuitAfter",'--log-file',$logPath) $logPath $TimeoutSec
        if (-not $res.naturalExit) { Fail "did not exit within ${TimeoutSec}s (forced termination only; NOT natural exit); log kept: $logPath" }
        if ($res.exitCode -ne 0) { Fail "exe exited non-zero (exit $($res.exitCode)); log kept: $logPath" }
        if (-not (Test-Log $logPath)) { Fail "log validation failed; log kept: $logPath" }
        Remove-Item -Path $logPath -Force -ErrorAction Stop
        Write-Host "SMOKE PASS: hash three-way equal; natural exit (exit 0); log clean with APP_READY:main_original; log deleted"
        exit 0
    }
}
