#!/usr/bin/env python3
"""xcresult から書き出した添付を、App Store へ出せる名前で並べ直す。

xcresulttool は添付をランダムな UUID 名で吐き、対応表を manifest.json に置く。
撮影時に付けた名前（01-map-home など）へ戻すのがこのスクリプトの役目。

    collect-screenshots.py <raw-dir> <out-dir>
"""
import json
import shutil
import sys
from pathlib import Path

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

manifest = json.loads((raw / "manifest.json").read_text())

count = 0
for entry in manifest:
    for attachment in entry.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName") or ""
        exported = attachment.get("exportedFileName")
        if not exported or not name.endswith(".png"):
            continue
        # 撮影名は「01-map-home_1_<UUID>.png」の形で返ってくる。
        stem = name.split("_")[0]
        if not stem[:2].isdigit():
            continue
        shutil.copyfile(raw / exported, out / f"{stem}.png")
        count += 1

if count == 0:
    sys.exit(f"スクリーンショットが 1 枚も見つかりません: {raw}")
print(f"{count} 枚を {out} へ書き出しました")
