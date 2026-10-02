#!/usr/bin/env python3
"""Apply the special-token detokenizer fix to the mlx-lm venv.

Root cause: mlx-lm's BPEStreamingDetokenizer decodes every generated token
straight to text, including special tokens such as <|im_end|>. The model
correctly emits the im_end token id to end its turn, but the detokenizer
renders its literal string, so every response ends with "<|im_end|>".

Fix: skip special-token ids when rendering text. The token list stays
complete (stopping and logging are unaffected); only text rendering skips
them, which is what standard serving stacks do.

Idempotent: safe to run repeatedly. Re-run after any `uv pip install -U
mlx-lm`, which restores the original file.
"""
import pathlib
import sys

VENV = pathlib.Path.home() / ".local/share/mlx-server/.venv"
TARGET = VENV / "lib/python3.12/site-packages/mlx_lm/tokenizer_utils.py"
MARKER = "_special_ids_fix_v1"

if not TARGET.exists():
    sys.exit(f"target not found: {TARGET}")
t = TARGET.read_text()
if MARKER in t:
    print("already applied, nothing to do")
    sys.exit(0)

INIT_OLD = """    def __init__(self, tokenizer):
        self.clean_spaces = tokenizer.clean_up_tokenization_spaces

        # Extract the tokens in a list from id to text"""
INIT_NEW = f"""    def __init__(self, tokenizer):
        self.clean_spaces = tokenizer.clean_up_tokenization_spaces

        # {MARKER}: skip special tokens (eos, chat markers) so they never
        # render as text. Stopping logic works on token ids, unaffected.
        self._special_ids = set(getattr(tokenizer, "all_special_ids", None) or [])

        # Extract the tokens in a list from id to text"""

ADD_OLD = """    def add_token(self, token):
        self.tokens.append(token)
        v = self.tokenmap[token] if token < len(self.tokenmap) else "!\""""
ADD_NEW = """    def add_token(self, token):
        self.tokens.append(token)
        if token in self._special_ids:
            return
        v = self.tokenmap[token] if token < len(self.tokenmap) else "!\""""

edits = [(INIT_OLD, INIT_NEW), (ADD_OLD, ADD_NEW)]
for old, new in edits:
    if old not in t:
        sys.exit(f"expected block not found, mlx-lm may have changed:\n{old}")
    t = t.replace(old, new, 1)

TARGET.write_text(t)
print(f"applied {len(edits)} edits to {TARGET}")
print("restart the server: launchctl unload/load com.local.mlx-server")
