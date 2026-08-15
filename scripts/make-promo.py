#!/usr/bin/env python3
"""録画から PV を組み立てる。

素材は scripts/record-promo.sh が撮る生の画面録画 1 本だけ。
そこから使う区間を選び、間延びするところは早送りし、字幕を重ねる。

手作業で切らずにスクリプトにしてあるのは、撮り直すたびに同じ編集を
やり直せるようにするため。区間の秒数だけ直せば作り直せる。

    scripts/.venv/bin/python scripts/make-promo.py <raw.mov> <out.mp4>
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
CANVAS = (1206, 2622)
BACKGROUND = (12, 22, 38)      # 画面が明るいので、背景は濃紺で締める
ACCENT = (90, 170, 255)

# 生の録画から使う区間。(開始秒, 終了秒, 再生速度)
# 経路の計算待ちは絵にならないので丸ごと落とす。
CUTS = [
    (6.5, 9.6, 1.0),    # 現在地（東京ディズニーランド）
    (9.6, 16.4, 1.8),   # 目的地を打つ
    (30.5, 36.8, 1.0),  # 区間に分かれた経路が出るところ
    (36.8, 43.0, 1.5),  # Safari へ渡す（読み込み中の白画面は早送りで抜ける）
    (43.0, 52.0, 1.0),  # Google マップ側の結果
]

# (開始秒, 終了秒, 主文, 副文) — 尺は CUTS から計算した後の時間軸。
CAPTIONS = [
    (0.0, 3.1, "東京ディズニーランドから", "大阪・道頓堀へ帰る"),
    (3.1, 6.9, "目的地を入れるだけ", None),
    (6.9, 13.2, "徒歩・電車・徒歩に自動で分かれる", "到着時刻まで分かる"),
    (13.2, 17.3, "運賃と乗換は Google マップへ", None),
    (17.3, 26.4, "比較は Useful Map", "詳細は Google マップ"),
]


def run(args: list[str]) -> None:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"失敗: {' '.join(args[:6])}...\n{result.stderr[-1500:]}")


def caption_image(path: Path, headline: str, sub: str | None) -> None:
    """上の帯に置く字幕を描く。動画へ重ねるので背景は透過。"""
    image = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    head_font = ImageFont.truetype(FONT, 62)
    sub_font = ImageFont.truetype(FONT, 44)

    y = 150
    width = draw.textlength(headline, font=head_font)
    draw.text(((CANVAS[0] - width) / 2, y), headline, font=head_font, fill=(255, 255, 255, 255))
    if sub:
        y += 88
        width = draw.textlength(sub, font=sub_font)
        draw.text(((CANVAS[0] - width) / 2, y), sub, font=sub_font, fill=(*ACCENT, 255))
    image.save(path)


def end_card(path: Path, icon: Path) -> None:
    image = Image.new("RGB", CANVAS, BACKGROUND)
    draw = ImageDraw.Draw(image)
    badge = Image.open(icon).convert("RGBA").resize((360, 360))
    # 角を丸める。アイコンは正方形で書き出されているため。
    mask = Image.new("L", (360, 360), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 359, 359), radius=80, fill=255)
    image.paste(badge, ((CANVAS[0] - 360) // 2, 900), mask)

    name_font = ImageFont.truetype(FONT, 76)
    tag_font = ImageFont.truetype(FONT, 44)
    name = "Useful Map 経路比較"
    tagline = "電車・徒歩・車の所要時間を、ひと目で"
    width = draw.textlength(name, font=name_font)
    draw.text(((CANVAS[0] - width) / 2, 1360), name, font=name_font, fill=(255, 255, 255))
    width = draw.textlength(tagline, font=tag_font)
    draw.text(((CANVAS[0] - width) / 2, 1480), tagline, font=tag_font, fill=ACCENT)
    image.save(path)


def main() -> None:
    raw, out = Path(sys.argv[1]), Path(sys.argv[2])
    work = out.parent / "work"
    work.mkdir(parents=True, exist_ok=True)

    # 1. 区間を切り出して速度を掛ける。
    parts = []
    for index, (start, end, speed) in enumerate(CUTS):
        part = work / f"cut{index}.mp4"
        run(["ffmpeg", "-v", "error", "-ss", str(start), "-to", str(end), "-i", str(raw),
             "-filter:v", f"setpts=PTS/{speed}", "-an", "-r", "30",
             "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", str(part), "-y"])
        parts.append(part)

    listing = work / "parts.txt"
    listing.write_text("".join(f"file '{p.name}'\n" for p in parts))
    joined = work / "joined.mp4"
    run(["ffmpeg", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
         "-c", "copy", str(joined), "-y"])

    # 2. 画面を少し縮めて濃紺の上に置き、空いた上の帯へ字幕を入れる。
    overlays = []
    for index, (start, end, headline, sub) in enumerate(CAPTIONS):
        path = work / f"cap{index}.png"
        caption_image(path, headline, sub)
        overlays.append((path, start, end))

    inputs = ["-i", str(joined)]
    for path, _, _ in overlays:
        inputs += ["-i", str(path)]

    chain = [f"color=c=0x{BACKGROUND[0]:02x}{BACKGROUND[1]:02x}{BACKGROUND[2]:02x}:"
             f"s={CANVAS[0]}x{CANVAS[1]}:r=30[bg]",
             "[0:v]scale=964:-2[phone]",
             "[bg][phone]overlay=(W-w)/2:H-h-60:shortest=1[base0]"]
    for index, (_, start, end) in enumerate(overlays):
        chain.append(f"[base{index}][{index + 1}:v]overlay=0:0:"
                     f"enable='between(t,{start},{end})'[base{index + 1}]")
    filtergraph = ";".join(chain)
    body = work / "body.mp4"
    run(["ffmpeg", "-v", "error", *inputs, "-filter_complex", filtergraph,
         "-map", f"[base{len(overlays)}]", "-c:v", "libx264", "-crf", "18",
         "-pix_fmt", "yuv420p", str(body), "-y"])

    # 3. 最後にアプリ名のカードを付ける。
    card = work / "end.png"
    end_card(card, Path("App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"))
    tail = work / "end.mp4"
    run(["ffmpeg", "-v", "error", "-loop", "1", "-t", "2.6", "-i", str(card),
         "-vf", "scale=1206:2622", "-r", "30", "-c:v", "libx264", "-crf", "18",
         "-pix_fmt", "yuv420p", str(tail), "-y"])

    final_list = work / "final.txt"
    final_list.write_text(f"file '{body.name}'\nfile '{tail.name}'\n")
    run(["ffmpeg", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(final_list),
         "-c", "copy", str(out), "-y"])
    print(f"書き出し: {out}")


if __name__ == "__main__":
    main()
