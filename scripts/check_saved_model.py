"""Load a model Heretic saved and generate one short, ordinary reply on the GPU.

Usage: python check_saved_model.py <path-to-saved-model-folder>
"""
import sys
import time

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

if len(sys.argv) != 2:
    sys.exit(__doc__)
path = sys.argv[1]

start = time.perf_counter()
tokenizer = AutoTokenizer.from_pretrained(path)
model = AutoModelForCausalLM.from_pretrained(path, dtype=torch.bfloat16, device_map="cuda")
messages = [{"role": "user", "content": "In one sentence, what is a mini PC?"}]
inputs = tokenizer.apply_chat_template(
    messages, add_generation_prompt=True, return_tensors="pt", return_dict=True
).to("cuda")
output = model.generate(**inputs, max_new_tokens=40, do_sample=False)
reply = tokenizer.decode(output[0][inputs["input_ids"].shape[1]:], skip_special_tokens=True).strip()

print("device:", next(model.parameters()).device, " load+generate s:", round(time.perf_counter() - start, 1))
print("reply:", reply)
