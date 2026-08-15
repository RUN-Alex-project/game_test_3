$ErrorActionPreference = "Stop"

# Thin Windows wrapper: all test logic lives in tools/run_tests.py.
# The test registry is tests/test_manifest.json (platform-neutral, single source of truth).
# Godot resolution: --godot argument > GODOT_BIN > GODOT_EXE > godot4 > godot (handled in run_tests.py).
# Override the Python interpreter via PYTHON_EXE if needed.

$python = if ($env:PYTHON_EXE) { $env:PYTHON_EXE } else { "python" }

& $python "$PSScriptRoot/tools/run_tests.py" @args
exit $LASTEXITCODE
