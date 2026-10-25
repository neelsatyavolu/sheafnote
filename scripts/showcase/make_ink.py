"""Generates handwriting-like PencilKit stroke data for the Sheafnote showcase screenshots.

Output: showcase-ink.json = {"pages": [[stroke, ...], ...], "cards": [{"front": [...], "back": [...]}]}
stroke = {"ink": "pen"|"marker"|"monoline", "color": "#RRGGBB", "alpha": float, "width": float, "points": [[x, y, t, force], ...]}
Run: uv run --with Hershey-Fonts python -I scripts/showcase/make_ink.py
Handwriting: joined lowercase from the Hershey "scripts" font and printed capitals and digits from "futural"
(public-domain single-stroke fonts), with slant, per-word drift and pressure.
"""
import json
import math
import os
import random
from pathlib import Path

from HersheyFonts import HersheyFonts

INK = "#2B2420"
TANGERINE = "#F2542D"
SKY = "#3D9BFF"
MINT = "#1FA37E"
SUNFLOWER = "#FFC93C"

LINE0, SPACING, MARGIN = 64.0, 22.0, 84.0      # college ruled: first rule, rule spacing, text start right of margin
script, printed = HersheyFonts(), HersheyFonts()
script.load_default_font("scripts")     # joined lowercase
printed.load_default_font("futural")    # printed capitals, digits and symbols, as many people write
rng = random.Random(7)


def runs(text: str) -> list[tuple[HersheyFonts, str]]:
    """Splits a word into lowercase runs (joined script) and everything else (print)."""
    out: list[tuple[HersheyFonts, str]] = []
    for ch in text:
        f = script if ch.islower() else printed
        if out and out[-1][0] is f:
            out[-1] = (f, out[-1][1] + ch)
        else:
            out.append((f, ch))
    return out


def run_width(f: HersheyFonts, text: str) -> float:
    pts = [p for seg in f.lines_for_text(text) for p in seg]
    return max(p[0] for p in pts) + (1.5 if f is printed else 0.5) if pts else 6.0


def polylines(text: str) -> list[list[tuple[float, float]]]:
    """Chains each run's line segments into continuous pen strokes, runs placed one after another."""
    lines: list[list[tuple[float, float]]] = []
    offset = 0.0
    for f, part in runs(text):
        for (a, b) in f.lines_for_text(part):
            a, b = (a[0] + offset, a[1]), (b[0] + offset, b[1])
            if lines and lines[-1][-1] == a:
                lines[-1].append(b)
            else:
                lines.append([a, b])
        offset += run_width(f, part)
    return lines


def text_width(text: str) -> float:
    return sum(run_width(f, part) for f, part in runs(text))


def chaikin(points: list[tuple[float, float]], rounds: int = 2) -> list[tuple[float, float]]:
    for _ in range(rounds):
        if len(points) < 3:
            return points
        out = [points[0]]
        for p, q in zip(points, points[1:]):
            out += [(0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1]), (0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1])]
        out.append(points[-1])
        points = out
    return points


class Clock:
    t = 0.0


def stroke(points, color=INK, width=1.7, ink="pen", alpha=1.0, clock=None):
    clock = clock or Clock()
    out = []
    for i, (x, y) in enumerate(points):
        if i:
            px, py = points[i - 1]
            clock.t += math.hypot(x - px, y - py) / 260.0
        force = 0.55 + 0.35 * math.sin(math.pi * i / max(len(points) - 1, 1)) + rng.uniform(-0.05, 0.05)
        out.append([round(x, 2), round(y, 2), round(clock.t, 4), round(force, 3)])
    clock.t += 0.12
    # PencilKit's pen draws much thinner than the nominal width at this pressure; 1.5x matches a real pen stroke.
    return {"ink": ink, "color": color, "alpha": alpha, "width": width * (1.5 if ink == "pen" else 1), "points": out}


def write(text: str, x: float, baseline: float, scale: float = 0.8, color: str = INK, width: float = 1.7,
          slant: float = 0.2, clock=None) -> tuple[list[dict], float]:
    """Handwritten line; returns strokes and the right edge x. Each word gets its own small baseline drift."""
    strokes, cursor = [], x
    for word in text.split(" "):
        if not word:
            cursor += 10 * scale
            continue
        dy, rot, s = rng.uniform(-0.8, 0.8), rng.uniform(-0.02, 0.02), scale * rng.uniform(0.97, 1.03)
        for line in polylines(word):
            pts = []
            for (gx, gy) in line:
                lx, ly = gx * s, (gy - 9) * s                  # glyph baseline (y=9) onto the page baseline
                lx += -ly * slant                              # forward slant
                rx = lx * math.cos(rot) - ly * math.sin(rot)
                ry = lx * math.sin(rot) + ly * math.cos(rot)
                pts.append((cursor + rx + rng.uniform(-0.12, 0.12), baseline + dy + ry + rng.uniform(-0.12, 0.12)))
            strokes.append(stroke(chaikin(pts), color=color, width=width, clock=clock))
        cursor += text_width(word) * s + 11 * scale
    return strokes, cursor


def rule(n: int) -> float:
    return LINE0 + SPACING * n - 2.5


def wobbly(points, amount=0.6):
    return chaikin([(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount)) for x, y in points], 3)


def ellipse(cx, cy, rx, ry, start=0.0, sweep=2.15 * math.pi, n=40):
    return [(cx + rx * math.cos(start + sweep * i / n) * rng.uniform(0.98, 1.02),
             cy + ry * math.sin(start + sweep * i / n) * rng.uniform(0.98, 1.02)) for i in range(n + 1)]


def highlight(x0, x1, baseline, color=SUNFLOWER):
    pts = [(x0 + (x1 - x0) * i / 12, baseline - 4 + rng.uniform(-0.6, 0.6)) for i in range(13)]
    return stroke(pts, color=color, width=15, ink="marker", alpha=0.45)


def word_span(text: str, word: str, x: float, scale: float = 0.8) -> tuple[float, float]:
    """Approximate x range of `word` inside a line written by `write`."""
    before = text[: text.index(word)]
    words = [w for w in before.split(" ") if w]
    start = x + sum(text_width(w) * scale + 11 * scale for w in words) + (10 * scale if before.endswith("  ") else 0)
    return start - 2, start + text_width(word) * scale + 3


def page_respiration():
    c, s = Clock(), []
    t, right = write("Cellular Respiration", MARGIN, rule(1), scale=1.15, width=2.1, clock=c)
    s += t
    s.append(stroke(wobbly([(MARGIN - 2, rule(1) + 6), (right - 6, rule(1) + 5)], 0.4), color=TANGERINE, width=2.4, clock=c))
    s += write("Oct 21", 470, rule(1), scale=0.7, color="#7A6E64", width=1.8, clock=c)[0]
    lines = [
        (3, "Glucose + O2 -> CO2 + H2O + ATP"),
        (5, "1. Glycolysis - in the cytoplasm"),
        (6, "    makes 2 ATP + 2 pyruvate"),
        (8, "2. Krebs cycle - in the mitochondria"),
        (9, "    makes 2 ATP, NADH, FADH2"),
        (11, "3. Electron transport chain"),
        (12, "    about 34 ATP, needs oxygen"),
        (14, "Total: about 38 ATP per glucose"),
    ]
    for row, text in lines:
        s += write(text, MARGIN, rule(row), clock=c)[0]
    x0, x1 = word_span(lines[3][1], "mitochondria", MARGIN)
    s.insert(0, highlight(x0, x1, rule(8)))
    x0, x1 = word_span(lines[7][1], "38", MARGIN)
    s.insert(0, highlight(x0 - 2, x1 + 30, rule(14), color="#7FE0C4"))
    # Mitochondrion sketch with labels.
    cx, cy = 300, rule(19)
    s.append(stroke(wobbly(ellipse(cx, cy, 120, 46)), width=2.0, clock=c))
    folds = [(cx - 96 + 192 * i / 14 + rng.uniform(-3, 3), cy + (19 if i % 2 else -19) * (1 - abs(i - 7) / 9) + rng.uniform(-3, 3))
             for i in range(15)]
    s.append(stroke(wobbly(folds, 0.5), color=TANGERINE, width=1.8, clock=c))
    s += write("cristae", cx + 150, rule(17), scale=0.7, color=SKY, width=1.8, clock=c)[0]
    s.append(stroke(wobbly([(cx + 146, rule(17) - 4), (cx + 70, cy - 10)], 0.3), color=SKY, width=1.8, clock=c))
    s.append(stroke(wobbly([(cx + 78, cy - 18), (cx + 70, cy - 10), (cx + 80, cy - 6)], 0.2), color=SKY, width=1.8, clock=c))
    s += write("ATP is made here", cx - 70, rule(23), scale=0.75, color=SKY, width=1.8, clock=c)[0]
    s += write("Q: why does it need O2?", MARGIN, rule(26), scale=0.8, color=MINT, width=1.7, clock=c)[0]
    s += write("O2 takes the electrons at the end of the chain", MARGIN, rule(27), scale=0.72, clock=c)[0]
    return s


def page_photosynthesis():
    c, s = Clock(), []
    t, right = write("Photosynthesis", MARGIN, rule(1), scale=1.15, width=2.1, clock=c)
    s += t
    s.append(stroke(wobbly([(MARGIN - 2, rule(1) + 6), (right - 6, rule(1) + 5)], 0.4), color=MINT, width=2.4, clock=c))
    for row, text in [(3, "6 CO2 + 6 H2O + light -> sugar + 6 O2"), (5, "Light reactions - thylakoid"),
                      (6, "Calvin cycle - stroma"), (8, "Chlorophyll absorbs red + blue light")]:
        s += write(text, MARGIN, rule(row), clock=c)[0]
    s.append(stroke(wobbly(ellipse(420, rule(13), 70, 34)), color=MINT, width=2.0, clock=c))
    s += write("chloroplast", 380, rule(17), scale=0.7, color=MINT, width=1.8, clock=c)[0]
    return s


def page_review():
    c, s = Clock(), []
    t, right = write("Quiz review", MARGIN, rule(1), scale=1.15, width=2.1, clock=c)
    s += t
    s.append(stroke(wobbly([(MARGIN - 2, rule(1) + 6), (right - 6, rule(1) + 5)], 0.4), color=SKY, width=2.4, clock=c))
    for row, text in [(3, "- Compare aerobic vs anaerobic"), (4, "- Where is ATP synthase?"), (5, "- Draw the Krebs cycle")]:
        s += write(text, MARGIN, rule(row), clock=c)[0]
    return s


def card(text: str, color=INK):
    strokes, right = write(text, 20, 44, scale=1.0, color=color, width=2.0)
    return {"strokes": strokes, "width": right + 20, "height": 64}


data = {
    "pages": [page_respiration(), page_photosynthesis(), page_review()],
    "cards": [{"front": card("Where does the Krebs cycle happen?"), "back": card("In the mitochondria", TANGERINE)}],
}
out = Path(os.environ.get("OUT", "showcase-ink.json"))
out.write_text(json.dumps(data))
print(out, sum(len(p) for p in data["pages"]), "strokes")
