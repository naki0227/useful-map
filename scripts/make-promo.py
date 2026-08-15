#!/usr/bin/env python3
"""録画から PV を組み立てる。

素材は scripts/record-promo.sh が撮る生の画面録画 1 本だけ。
そこから使う区間を選び、間延びするところは早送りし、字幕を重ねる。

手作業で切らずにスクリプトにしてあるのは、撮り直すたびに同じ編集を
やり直せるようにするため。区間の秒数だけ直せば作り直せる。

    scripts/.venv/bin/python scripts/make-promo.py <raw.mov> <out.mp4> [音楽.mp3] [--store] [--size WxH]

--store を付けると App Store の「Appプレビュー」向けに 30 秒以内へ詰める。
--size で出力の大きさを指定できる。画面は横 80% に縮めて置くので、
素材がそれより大きければ拡大は起きない（1206 の素材でも 1320 で出せる）。
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
# 画面の大きさは素材から取る。端末を変えて撮り直しても、そのまま通す。
CANVAS = (1320, 2868)
BACKGROUND = (12, 22, 38)      # 画面が明るいので、背景は濃紺で締める
ACCENT = (90, 170, 255)

# 使う区間。(始点マーカー, 終点マーカー, 再生速度, 始点をずらす秒)
#
# 秒数を直に書かない。撮り直すたびに端末の速さで position がずれるため、
# テストが出したマーカーの時刻から求める（markers.txt）。
# 経路の計算待ち（searching → route）は絵にならないので丸ごと落とす。
CUTS = [
    ("map", "typing", 1.0, 0.0),
    ("typing", "searching", 1.8, 0.0),
    # 計算の最後 1.5 秒だけ残し、区間に分かれる瞬間を見せる。
    ("route", "handoff", 1.0, -1.5),
    ("handoff", "google", 1.5, 0.0),
    ("google", "end", 1.0, 0.0),
]

# 区間ごとの字幕。(主文, 副文) — 表示する時間は区間の長さから決まる。
CAPTIONS = [
    ("東京ディズニーランドから", "大阪・道頓堀へ帰る"),
    ("目的地を入れるだけ", None),
    ("徒歩・電車・徒歩に自動で分かれる", "到着時刻まで分かる"),
    ("運賃と乗換は Google マップへ", None),
    ("比較は Useful Map", "詳細は Google マップ"),
]

# 冒頭に差す 1 枚と、最後のカードの背景。
HOOK = Path("promo/assets/hook.png")
END_BACKGROUND = Path("promo/assets/endcard.png")
HOOK_SECONDS = 1.1
END_SECONDS = 2.6

# App Store の Appプレビューは 15〜30 秒。最後の見せ場を詰めて収める。
STORE_TAIL_SECONDS = 5.5
STORE_END_SECONDS = 1.8


def probe(path: Path, entries: str) -> str:
    return subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", entries,
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True).stdout.strip()


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


def load_markers(path: Path, video: Path) -> dict[str, float]:
    """テストが出した時刻を、動画中の秒数へ直す。

    録画開始の時刻を直接測ると、simctl が実際に撮り始めるまでの分だけずれる。
    止めた時刻は正確に取れるので、そこから動画の長さを引いて始まりを求める。
    """
    values = {}
    for line in path.read_text().splitlines():
        name, epoch = line.split()
        values[name] = float(epoch)
    began = values.pop("stop") - float(probe(video, "format=duration"))
    return {name: epoch - began for name, epoch in values.items()}


def end_card(path: Path, icon: Path) -> None:
    if END_BACKGROUND.exists():
        image = Image.open(END_BACKGROUND).convert("RGB").resize(CANVAS)
    else:
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


def add_music(video: Path, music: Path, out: Path) -> None:
    """音楽を尺に合わせて敷く。

    長さは映像に合わせて切り、頭を少し立ち上げ、終わりは余韻を残して落とす。
    音量は loudnorm で -16 LUFS へ揃える。SNS の再生音量に近く、
    端末のスピーカーでも小さすぎない。
    """
    duration = float(probe(video, "format=duration"))
    fade_out_at = max(duration - 2.2, 0.0)
    run(["ffmpeg", "-v", "error", "-i", str(video), "-i", str(music),
         "-filter_complex",
         f"[1:a]atrim=0:{duration},asetpts=N/SR/TB,"
         f"afade=t=in:st=0:d=0.6,afade=t=out:st={fade_out_at:.2f}:d=2.2,"
         f"loudnorm=I=-16:TP=-1.5:LRA=11[a]",
         "-map", "0:v", "-map", "[a]",
         "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest",
         str(out), "-y"])


def main() -> None:
    raw, out = Path(sys.argv[1]), Path(sys.argv[2])
    arguments = sys.argv[3:]
    store = "--store" in arguments
    rest = [a for a in arguments if not a.startswith("--")]
    music = Path(rest[0]) if rest else None
    end_seconds = STORE_END_SECONDS if store else END_SECONDS
    work = out.parent / "work"
    work.mkdir(parents=True, exist_ok=True)
    marks = load_markers(raw.parent / "markers.txt", raw)

    global CANVAS
    override = next((a for a in arguments if a.startswith("--size=")), None)
    if override:
        width, height = override.split("=")[1].split("x")
    else:
        width, height = probe(raw, "stream=width,height").split()
    CANVAS = (int(width), int(height))

    # 1. マーカーの位置で切り出し、速度を掛ける。
    parts, lengths = [], []
    for index, (begin, finish, speed, offset) in enumerate(CUTS):
        start, end = marks[begin] + offset, marks[finish]
        # 尺を詰めるときは、いちばん動きの少ない最後の区間を短くする。
        if store and index == len(CUTS) - 1:
            end = min(end, start + STORE_TAIL_SECONDS)
        part = work / f"cut{index}.mp4"
        # -ss / -t は setpts と噛み合わず尺がずれる。フィルタの trim で正確に切る。
        run(["ffmpeg", "-v", "error", "-i", str(raw),
             # 画面が止まっている間はフレームが出ない録画なので、
             # まず 30fps へ均し、その上で切る。順序を逆にすると尺が合わない。
             "-filter:v", f"fps=30,trim=start={start}:end={end},"
                          f"setpts=(PTS-STARTPTS)/{speed}",
             "-an", "-r", "30",
             "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", str(part), "-y"])
        parts.append(part)
        # 字幕を合わせるため、狙いではなく実際に出来た長さを使う。
        lengths.append(float(probe(part, "format=duration")))

    listing = work / "parts.txt"
    listing.write_text("".join(f"file '{p.name}'\n" for p in parts))
    joined = work / "joined.mp4"
    run(["ffmpeg", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
         "-c", "copy", str(joined), "-y"])

    # 2. 画面を少し縮めて濃紺の上に置き、空いた上の帯へ字幕を入れる。
    #    字幕の出る時間は、切った区間の長さの積み上げで決まる。
    overlays = []
    elapsed = 0.0
    for index, (headline, sub) in enumerate(CAPTIONS):
        path = work / f"cap{index}.png"
        caption_image(path, headline, sub)
        overlays.append((path, elapsed, elapsed + lengths[index]))
        elapsed += lengths[index]

    inputs = ["-i", str(joined)]
    for path, _, _ in overlays:
        inputs += ["-i", str(path)]

    chain = [f"color=c=0x{BACKGROUND[0]:02x}{BACKGROUND[1]:02x}{BACKGROUND[2]:02x}:"
             f"s={CANVAS[0]}x{CANVAS[1]}:r=30[bg]",
             f"[0:v]scale={int(CANVAS[0] * 0.8)}:-2[phone]",
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
    run(["ffmpeg", "-v", "error", "-loop", "1", "-t", str(end_seconds), "-i", str(card),
         "-vf", f"scale={CANVAS[0]}:{CANVAS[1]}", "-r", "30", "-c:v", "libx264", "-crf", "18",
         "-pix_fmt", "yuv420p", str(tail), "-y"])

    # 4. 冒頭に 1 枚だけ静止画を差す。ゆっくり寄せて、動きを止めない。
    pieces = []
    if HOOK.exists():
        hook = work / "hook.mp4"
        frames = int(HOOK_SECONDS * 30)
        run(["ffmpeg", "-v", "error", "-loop", "1", "-t", str(HOOK_SECONDS), "-i", str(HOOK),
             "-vf", f"scale={CANVAS[0] * 2}:-2,"
                    f"zoompan=z='min(1.07,1+0.07*on/{frames})':d=1:"
                    f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
                    f"s={CANVAS[0]}x{CANVAS[1]}:fps=30,"
                    f"fade=t=out:st={HOOK_SECONDS - 0.35:.2f}:d=0.35",
             "-r", "30", "-c:v", "libx264", "-crf", "18",
             "-pix_fmt", "yuv420p", str(hook), "-y"])
        pieces.append(hook)
    pieces += [body, tail]

    final_list = work / "final.txt"
    final_list.write_text("".join(f"file '{p.name}'\n" for p in pieces))
    silent = work / "silent.mp4" if music else out
    run(["ffmpeg", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(final_list),
         "-c", "copy", str(silent), "-y"])

    if music:
        add_music(silent, music, out)
    print(f"書き出し: {out}")


if __name__ == "__main__":
    main()
