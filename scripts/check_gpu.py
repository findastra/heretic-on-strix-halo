"""Phase A smoke test, part 1: does PyTorch (ROCm on Windows) see the GPU and its memory?"""
import platform
import sys
import time

import torch

print("python", sys.version.split()[0], platform.platform())
print("torch", torch.__version__, "hip", getattr(torch.version, "hip", None))
ok = torch.cuda.is_available()
print("gpu available:", ok)
if not ok:
    sys.exit(1)

n = torch.cuda.device_count()
for i in range(n):
    p = torch.cuda.get_device_properties(i)
    print(f"device {i}: {p.name}  arch={getattr(p, 'gcnArchName', '?')}  total_memory={p.total_memory / 2**30:.1f} GiB")
free, total = torch.cuda.mem_get_info()
print(f"mem_get_info: free={free / 2**30:.1f} GiB  total={total / 2**30:.1f} GiB")

# A small bf16 matmul to prove kernels actually run, and a rough speed figure.
a = torch.randn(4096, 4096, device="cuda", dtype=torch.bfloat16)
b = torch.randn(4096, 4096, device="cuda", dtype=torch.bfloat16)
torch.cuda.synchronize()
t = time.perf_counter()
for _ in range(20):
    c = a @ b
torch.cuda.synchronize()
dt = time.perf_counter() - t
print(f"bf16 4096x4096 matmul x20: {dt:.3f} s  (~{20 * 2 * 4096**3 / dt / 1e12:.1f} TFLOPS)")

# How large a single allocation succeeds (in 8 GiB steps), to see usable GPU memory.
biggest = 0
for gib in range(8, 129, 8):
    try:
        x = torch.empty(gib * 2**30, dtype=torch.uint8, device="cuda")
        del x
        torch.cuda.empty_cache()
        biggest = gib
    except Exception:
        break
print(f"largest single allocation that worked: {biggest} GiB")
