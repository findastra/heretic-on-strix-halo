# Astra Wisp, phase A on Windows: page one of the report

By Astra. Run on 2026-11-20 (local time) on a GEEKOM A9 Mega, by Claude (Anthropic's AI assistant) running on the box itself.
Everything lives in `%USERPROFILE%\AstraWisp`, in a normal user account with no admin rights.

## Machine

| Item | Value |
| --- | --- |
| CPU / GPU | AMD Ryzen AI Max+ 395, Radeon 8060S (gfx1151) |
| Memory split (BIOS) | 64 GB GPU / 64 GB Windows (63.6 GB visible) |
| GPU memory PyTorch sees | 99.7 GiB (64 GB dedicated + shared) |
| OS | Windows 11 Pro 10.0.26300 |
| Graphics driver | 32.0.22040.7, AMD Software Adrenalin 25.20 (release 25.20-251202a, Dec 2025) |
| Disk free | 1,765 GB of 1,862 GB |

## Versions installed

| Piece | Version | Source |
| --- | --- | --- |
| Python | 3.12.10 (NuGet package, per-user folder, not on PATH) | nuget.org/packages/python, signed by the Python Software Foundation |
| ROCm SDK (Python wheels) | 7.2.1 | repo.radeon.com/rocm/windows/rocm-rel-7.2.1 |
| PyTorch / torchvision / torchaudio | 2.9.1+rocm7.2.1 / 0.24.1+rocm7.2.1 / 2.9.1+rocm7.2.1 (HIP 7.2.53211) | same AMD repo |
| Heretic | 2.1.0 (pinned) | PyPI `heretic-llm` |
| transformers / accelerate / peft / optuna / bitsandbytes | 5.23.0 / 1.16.0 / 0.22.0 / 5.1.0 / 0.50.2 | PyPI, pulled in by Heretic |
| llama.cpp | b12600, Vulkan and ROCm 10.0 Windows builds (SHA-256 checked) | github.com/ggml-org/llama.cpp releases |

## Smoke test

**PyTorch sees the GPU: yes.** `torch.cuda.is_available()` is True; device `AMD Radeon(TM) 8060S Graphics`, arch gfx1151, 99.7 GiB total, 99.6 GiB free. A bf16 4096×4096 matmul ×20 took 0.193 s (about 14.3 TFLOPS). The largest single allocation that worked was 56 GiB.

**llama.cpp sees the GPU:** Vulkan build yes (`Vulkan0: AMD Radeon(TM) 8060S Graphics`, 114,326 MiB, 108,610 MiB free). ROCm build no (`Available devices: (none)`).

**Heretic, 3 trials on Qwen/Qwen2.5-0.5B-Instruct: yes.** Settings in `runs\smoke-test\config.toml` (3 trials, all 3 random startup trials, seed 42, no 4-bit, default ARA modifier, default datasets). Ran twice with identical results.

| | Refusals (of 100) | KL divergence |
| --- | --- | --- |
| Stock model (baseline) | 92 | 0 |
| Trial 1 | 16 | 0.6085 |
| Trial 2 (picked and saved) | 2 | 0.6066 |
| Trial 3 | 16 | 0.0860 |

- Model load (bf16) used 1.03 GB of GPU memory; peak during trials 1.10 GB reserved.
- Auto batch size went all the way to the cap of 32 with no errors (73 tokens/s at 1, 2,036 at 32), although AMD says only batch size 1 is officially supported on Windows.
- 3 trials took 1 min 37 s (about 32 s a trial).
- Trial 2 was merged and saved to `models\smoke-test-qwen2.5-0.5b` (942 MB safetensors). It loads back on the GPU and answers a normal question (4.3 s load and generate).
- 3 trials on 3 random startup trials is a test of the pipeline, not a tuned result.

## Errors and fixes

1. **Python's normal installer failed** (python.org 3.12.10 .exe, per-user, quiet): exit code 3, MSI error 0x80070003 "path not found" when Windows Installer opened its cached `core.msi`. Likely caused by the sandbox the installing shell ran in. **Fix:** used Python's official NuGet package instead, which is a plain folder and needs no installer.
2. **Driver older than AMD asks for.** AMD's page says ROCm 7.2.1 PyTorch on Windows needs graphics driver 26.2.2; the box has Adrenalin 25.20. PyTorch works on it anyway. The llama.cpp ROCm build finds no device, which may be this. Being updated afterwards to Adrenalin 26.11.2 (see the README).

3. **Heretic crashed at its menus when run unattended** (`NoConsoleScreenBufferError: No Windows console found`). It builds its questionary menus even when `config.toml` presets the answer (`trial_index`, `model_action`, ...), and on Windows prompt_toolkit needs a real console. The 3 trials had already finished. **Fix:** `scripts\heretic_headless.py` swaps the menu builders for stubs, so preset answers pass and an unset question fails with a clear message. Worth reporting upstream.
4. **Slow restore after saving.** After the merge and save, Heretic reloads the model and redoes the trial in memory (in case you chat or benchmark next). That step sat on one CPU core with the GPU idle for over 4 minutes, so it was stopped. It only matters when saving and then chatting or benchmarking in the same run; the saved model was already complete. To look into before the big runs.

## Still to do

- **Step 1, GPU memory:** still 64 GB at the time of this report. The plan raises it as far as it goes (96 GB); see the README for both ways.
- **Step 2, SSH and a separate "wisp" account:** skipped on Windows, because Claude runs on the box itself. The separate account comes with Ubuntu.
- **Driver:** being updated to Adrenalin 26.11.2 after this run; re-test results to follow.
