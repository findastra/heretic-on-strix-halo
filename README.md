# Heretic on AMD Strix Halo (Ryzen AI Max+ 395)

By Astra.

Running [Heretic](https://github.com/p-e-w/heretic), the tool that removes refusals from language models, on a Ryzen AI Max+ 395 mini PC: the making step itself, not just running a finished model. As far as we could find, nobody had published a Heretic run on this chip before. This repo holds the recipe, settings, scripts, logs and scores. It holds **no model weights**: those stay private.

**Status (2026-11-20):** Windows 11 works. PyTorch on ROCm 7.2.1 sees the GPU, and Heretic 2.1.0 ran a 3-trial smoke test end to end, once two Windows problems were worked around (below). Ubuntu is next, and it does the real runs.

| Phase | What | State |
| --- | --- | --- |
| A | Windows 11: drivers, PyTorch on ROCm, Heretic, llama.cpp, smoke test | Done |
| B | Ubuntu 24.04/26.04: same stack, same smoke test, timings | Next |
| C onward | The real model, full runs, tool-calling tests, results | Later |

## The machine

| Item | Value |
| --- | --- |
| Box | GEEKOM A9 Mega |
| Chip | AMD Ryzen AI Max+ 395, Radeon 8060S GPU (gfx1151) |
| Memory | 128 GB LPDDR5X, shared between CPU and GPU, split in the BIOS |
| OS | Windows 11 Pro 10.0.26300 |

## Windows setup, step by step

### 1. Update the AMD graphics driver

Get the current AMD Software: Adrenalin Edition from AMD's page for your chip ([Ryzen AI Max+ 395](https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-ai-max-series/amd-ryzen-ai-max-plus-395.html)). Check that the installer's signature reads Advanced Micro Devices, then run it.

- AMD's ROCm 7.2.1 PyTorch release ([release notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-AMDGPU-WINDOWS-PYTORCH-7-2-1.html)) asks for Adrenalin 26.2.2.
- This box came with Adrenalin 25.20 (Dec 2025). PyTorch worked on it anyway, but llama.cpp's ROCm build found no GPU.
- We updated to **Adrenalin 26.11.2** (Nov 18, 2026; driver 32.0.32029.2010), the current recommended driver for this chip. PyTorch on ROCm 7.2.1 works on it with the same results (bf16 14.9 TFLOPS, against 14.3 before). llama.cpp's ROCm build still finds no GPU, so the driver wasn't the cause (problem 5).
- In AMD's installer, click **Install** and let it finish. Our first attempt unpacked the files and stopped there, and a restart didn't help. It may also offer AMD's chipset driver; that's optional.
- **Restart when it's done**, even if it doesn't ask. After our install, the HDMI monitor (a 4K Dell) stayed black. Windows still listed the monitor as connected and was sending it 3840×2160 at 59 Hz, and the logs showed no driver errors. A restart brought the picture back. If you can't see the screen, you can still sign in blind: press a key, type your PIN, press Enter.
- AMD's Windows ROCm has since moved to 10.2.0 with PyTorch 2.15.0, which pairs with 26.11.2 ([install page](https://rocm.docs.amd.com/en/latest/install/rocm.html?fam=ryzen&gpu=amd-ryzen-ai-max-395&os=windows&gfx=gfx1151)). This guide stays on ROCm 7.2.1 / PyTorch 2.9.1 so the Windows and Ubuntu runs match.

### 2. Give the GPU more memory

A 128 GB box ships split 64 GB GPU / 64 GB Windows. The GPU can have up to 96 GB dedicated, which leaves Windows 32 GB. PyTorch can also use shared memory on top of the dedicated amount; at the 64 GB split it already saw 99.7 GiB. Either way below needs a restart.

**Way 1, AMD Software (easiest; needs Adrenalin 25.8.1 or newer, so do step 1 first).** Right-click the desktop > AMD Software: Adrenalin Edition > Performance > Tuning > Variable Graphics Memory > 96 GB, then restart. On some Strix Halo boxes with newer firmware this setting doesn't stick. If it still shows 64 GB after the restart, use Way 2.

**Way 2, the BIOS.** GEEKOM hasn't published the A9 Mega's exact menu, so the labels below come from GEEKOM's other AMD boxes and other Strix Halo mini PCs (the firmware is AMI). Have your BitLocker recovery key at hand first, in case a firmware change asks for it.

1. Restart and press **Del** repeatedly before the logo appears (some GEEKOM models also take Esc). From Windows instead: Settings > System > Recovery > Advanced startup > Restart now > Troubleshoot > Advanced options > UEFI Firmware Settings > Restart.
2. Find **GFX Configuration**: try Advanced > GFX Configuration, or Advanced > AMD CBS > NBIO Common Options > GFX Configuration.
3. Set **iGPU Configuration** to **UMA_SPECIFIED**. The size setting only appears after this.
4. Set **UMA Frame buffer Size** to **96G**.
5. Press **F4** to save and exit.
6. Not there? GEEKOM's advanced BIOS mode shows more options on some models (it names the A9 Mega): hold **Ctrl** while restarting, then press **H** repeatedly.

**Check:** Task Manager > Performance > GPU > Dedicated GPU memory should read 96 GB, and [`scripts/check_gpu.py`](scripts/check_gpu.py) shows what PyTorch sees.

### 3. Install Python, PyTorch on ROCm, Heretic and llama.cpp

[`scripts/setup-windows.ps1`](scripts/setup-windows.ps1) does it all into one folder in your account (default `%USERPROFILE%\AstraWisp`). It needs no admin rights and installs nothing system-wide:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1
```

What it installs, and why:

| Piece | Version | Source | Note |
| --- | --- | --- | --- |
| Python | 3.12.10 | NuGet package `python` | AMD's Windows wheels need exactly Python 3.12. The NuGet package is a plain folder; see problem 1. |
| ROCm SDK | 7.2.1 | repo.radeon.com | AMD's Windows wheels |
| PyTorch, torchvision, torchaudio | 2.9.1, 0.24.1, 2.9.1 (+rocm7.2.1) | repo.radeon.com | |
| Heretic | 2.1.0, pinned | PyPI `heretic-llm` | Installed with a constraints file so pip can't swap AMD's torch for a CPU one |
| llama.cpp | b12600, Vulkan and ROCm builds | GitHub releases | SHA-256 checked |

The full package list is in [`results/2026-11-20-windows-smoke-test/pip-freeze.txt`](results/2026-11-20-windows-smoke-test/pip-freeze.txt).

### 4. Check that PyTorch sees the GPU

```powershell
& "$env:USERPROFILE\AstraWisp\venv\Scripts\python.exe" scripts\check_gpu.py
```

On this box, at the 64/64 split, on Adrenalin 26.11.2:

```
torch 2.9.1+rocm7.2.1 hip 7.2.53211-158bd99533
gpu available: True
device 0: AMD Radeon(TM) 8060S Graphics  arch=gfx1151  total_memory=99.7 GiB
mem_get_info: free=99.6 GiB  total=99.7 GiB
bf16 4096x4096 matmul x20: 0.185 s  (~14.9 TFLOPS)
largest single allocation that worked: 56 GiB
```

On the old Adrenalin 25.20 driver it was the same apart from speed (0.193 s, about 14.3 TFLOPS).

llama.cpp: `llama-cli --list-devices` in the Vulkan build lists `Vulkan0: AMD Radeon(TM) 8060S Graphics (114326 MiB, 108610 MiB free)` on both drivers. The ROCm build lists `(none)` on both (problem 5).

### 5. Smoke test: 3 Heretic trials on a small model

[`configs/smoke-test.config.toml`](configs/smoke-test.config.toml) runs 3 trials on `Qwen/Qwen2.5-0.5B-Instruct` with a fixed seed, no 4-bit loading, and every question Heretic would ask answered in advance. Put it in an empty folder as `config.toml` and run Heretic there through the wrapper (problem 3):

```powershell
mkdir smoke-test; copy configs\smoke-test.config.toml smoke-test\config.toml; cd smoke-test
$env:PYTHONUTF8 = '1'
& "$env:USERPROFILE\AstraWisp\venv\Scripts\python.exe" ..\scripts\heretic_headless.py
```

## Results

**Heretic 2.1.0, 3 trials, `Qwen/Qwen2.5-0.5B-Instruct`, seed 42, default ARA modifier and datasets.** Two runs gave identical numbers.

| | Refusals (of 100) | KL divergence |
| --- | --- | --- |
| Stock model | 92 | 0 |
| Trial 1 | 16 | 0.6085 |
| Trial 2 (saved) | 2 | 0.6066 |
| Trial 3 | 16 | 0.0860 |

- 3 trials took 1 min 37 s, about 32 s each. GPU memory: 1.03 GB for the model, 1.10 GB peak.
- Heretic's automatic batch sizing went to the cap of 32 with no errors (73 tokens/s at batch 1, 2,036 at 32). AMD says only batch size 1 is officially supported on Windows; on this box larger batches worked.
- Trial 2 was merged and saved (942 MB of safetensors). It loads back on the GPU and answers ordinary questions normally.
- With only 3 random trials this tests the pipeline. It is not a tuned result.

Every trial's parameters and scores are in [`results/2026-11-20-windows-smoke-test/heretic-study.jsonl`](results/2026-11-20-windows-smoke-test/heretic-study.jsonl), and the full run log is beside it.

## Problems we hit, and the fixes

1. **Python's normal installer failed.** The python.org 3.12.10 installer (per-user, quiet) exited with code 3, MSI error `0x80070003`, "path not found" opening its cached `core.msi`. It most likely came from the sandboxed shell it was launched from. **Fix:** Python's official NuGet package, which is a plain folder and needs no installer.
2. **The driver was older than AMD asks for.** It worked anyway; we updated it in step 1.
3. **Heretic crashes at its menus when no console is attached** (`NoConsoleScreenBufferError: No Windows console found`), for example when its output goes to a log file. Heretic 2.1.0 builds each questionary menu even when `config.toml` already holds the answer (`trial_index`, `model_action`, `export_strategy`, ...), and on Windows prompt_toolkit needs a real console to build one. The trials had already finished; the crash was at "Which trial do you want to use?". **Fix:** [`scripts/heretic_headless.py`](scripts/heretic_headless.py) swaps the menu builders for stubs, so preset answers go straight through and an unset question stops with a clear message.
4. **Slow step after saving.** After merging and saving, Heretic reloads the model and rebuilds the trial in memory, in case you want to chat with it or benchmark it next. On this box that rebuild sat on one CPU core with the GPU idle for over 4 minutes, so we stopped it. The saved model was already complete. It only matters if you save and then keep using the model in the same run. Still to look into.
5. **llama.cpp's Windows ROCm build lists no GPU** (`Available devices: (none)`), on both the old and the new driver. Its zip ships only some ROCm runtime DLLs and expects the rest (hipBLAS, rocBLAS and their kernels) from a matching ROCm 10.0 install on `PATH`. Others report the same thing and a fix of adding those DLLs ([llama.cpp #26996](https://github.com/ggml-org/llama.cpp/issues/26996)). Not fixed here yet; the Vulkan build works meanwhile.

## What's in this repo

| Path | What |
| --- | --- |
| [`reports/`](reports/) | The full report for each phase, with every version, error and fix |
| [`scripts/setup-windows.ps1`](scripts/setup-windows.ps1) | Windows install, step 3 above |
| [`scripts/check_gpu.py`](scripts/check_gpu.py) | Does PyTorch see the GPU, how much memory, a quick bf16 speed figure |
| [`scripts/heretic_headless.py`](scripts/heretic_headless.py) | Runs Heretic without a Windows console (problem 3) |
| [`scripts/check_saved_model.py`](scripts/check_saved_model.py) | Loads a saved model on the GPU and asks it one ordinary question |
| [`configs/`](configs/) | Heretic settings files |
| [`results/`](results/) | Per-run logs, Heretic's study journal (every trial's parameters and scores), `pip freeze` |

No weights, ever: we publish how to make the model and how it scored, not the model.
