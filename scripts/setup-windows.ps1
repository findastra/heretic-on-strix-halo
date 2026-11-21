<#
Sets up Heretic on Windows 11 for an AMD Ryzen AI Max (Strix Halo, gfx1151), the way it was done
for this guide. Everything goes in one folder in your own account; no admin rights, no installers,
no changes to PATH or system settings.

  - Python 3.12.10 from Python's official NuGet package (AMD's Windows wheels need exactly 3.12)
  - AMD ROCm 7.2.1 SDK wheels + PyTorch 2.9.1 / torchvision 0.24.1 / torchaudio 2.9.1 from repo.radeon.com
  - Heretic 2.1.0 (pinned), with torch held at AMD's build so pip can't replace it
  - llama.cpp Windows builds (Vulkan and ROCm), SHA-256 checked against GitHub

Before running: update the AMD graphics driver (AMD says 26.2.2 or newer for ROCm 7.2.1 PyTorch)
and set the GPU memory split in the BIOS. See the README.

Usage (Windows PowerShell 5.1 or PowerShell 7):
  powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
  powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Root D:\heretic -LlamaBuild b12600
#>
param(
    [string]$Root = (Join-Path $env:USERPROFILE 'AstraWisp'),
    [string]$LlamaBuild = 'b12600'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }

New-Item -ItemType Directory -Force -Path $Root, "$Root\downloads", "$Root\logs" | Out-Null

# 1. Python 3.12.10, NuGet package (a plain folder; the normal .exe installer is not needed)
Step 'Python 3.12.10'
$py312 = Join-Path $Root 'python312'
if (-not (Test-Path "$py312\python.exe")) {
    $dl = Join-Path $Root 'downloads\python-nuget'
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    $zip = Join-Path $dl 'python.3.12.10.zip'
    Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/python/3.12.10' -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath "$dl\extracted" -Force
    Copy-Item "$dl\extracted\tools" $py312 -Recurse
}
$sig = Get-AuthenticodeSignature "$py312\python.exe"
if ($sig.Status -ne 'Valid') { throw "python.exe signature is $($sig.Status)" }
& "$py312\python.exe" --version

# 2. Virtual environment
Step 'Virtual environment'
$venv = Join-Path $Root 'venv'
if (-not (Test-Path "$venv\Scripts\python.exe")) { & "$py312\python.exe" -m venv $venv }
$py = "$venv\Scripts\python.exe"
& $py -m pip install --upgrade pip | Out-File "$Root\logs\01-pip-upgrade.log" -Encoding utf8

# 3. AMD ROCm 7.2.1 SDK and PyTorch 2.9.1 (commands from AMD's "Install PyTorch on Windows" page)
Step 'ROCm 7.2.1 SDK and PyTorch 2.9.1 (several GB)'
$r = 'https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1'
& $py -m pip install --no-cache-dir `
    "$r/rocm_sdk_core-7.2.1-py3-none-win_amd64.whl" `
    "$r/rocm_sdk_devel-7.2.1-py3-none-win_amd64.whl" `
    "$r/rocm_sdk_libraries_custom-7.2.1-py3-none-win_amd64.whl" `
    "$r/rocm-7.2.1.tar.gz" | Out-File "$Root\logs\02-rocm-sdk.log" -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'ROCm SDK install failed; see logs\02-rocm-sdk.log' }
& $py -m pip install --no-cache-dir `
    "$r/torch-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl" `
    "$r/torchaudio-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl" `
    "$r/torchvision-0.24.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl" | Out-File "$Root\logs\03-torch.log" -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'PyTorch install failed; see logs\03-torch.log' }

# 4. Heretic 2.1.0, with torch held at AMD's build
Step 'Heretic 2.1.0'
$constraints = Join-Path $Root 'constraints.txt'
Set-Content -Path $constraints -Encoding ascii -Value @(
    'torch==2.9.1+rocm7.2.1',
    'torchvision==0.24.1+rocm7.2.1',
    'torchaudio==2.9.1+rocm7.2.1'
)
& $py -m pip install 'heretic-llm==2.1.0' -c $constraints | Out-File "$Root\logs\05-heretic.log" -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'Heretic install failed; see logs\05-heretic.log' }
& $py -c "import torch, importlib.metadata as m; print('torch', torch.__version__, 'GPU:', torch.cuda.is_available()); print('heretic', m.version('heretic-llm'))"

# 5. llama.cpp, Vulkan and ROCm Windows builds, checked against GitHub's SHA-256
Step "llama.cpp $LlamaBuild"
$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$LlamaBuild" -Headers @{ 'User-Agent' = 'setup-windows.ps1' }
$dl = Join-Path $Root 'downloads\llama.cpp'
New-Item -ItemType Directory -Force -Path $dl | Out-Null
foreach ($kind in 'vulkan', 'rocm') {
    $asset = $rel.assets | Where-Object { $_.name -match "^llama-$LlamaBuild-bin-win-$kind(-[\d.]+)?-x64\.zip$" } | Select-Object -First 1
    if (-not $asset) { Write-Warning "No Windows $kind build in $LlamaBuild"; continue }
    $out = Join-Path $dl $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $out -UseBasicParsing
    $hash = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
    if ($asset.digest -and $hash -ne ($asset.digest -replace '^sha256:', '')) { throw "SHA-256 mismatch for $($asset.name)" }
    Expand-Archive -Path $out -DestinationPath (Join-Path $Root "llama.cpp\$LlamaBuild-$kind") -Force
    Write-Host "$kind devices:"
    & (Join-Path $Root "llama.cpp\$LlamaBuild-$kind\llama-cli.exe") --list-devices
}

Step 'Done'
Write-Host "Next: python scripts\check_gpu.py, then the Heretic smoke test (see README)."
