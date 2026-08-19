#!/usr/bin/env python3
"""Copy scan — the bilingual quality checks that can be made mechanical.

WHY THIS EXISTS. A review pass over ~600 bilingual strings found the copy in good shape: one
register throughout (你, never 您), no doubled particles, no ASCII punctuation stranded inside
Chinese, and the one number that differs between the two languages differs on purpose (the crisis
reply names 988 for the US/Canada in English and gives the universal fallback in Chinese, because
naming a US number to a Chinese speaker would be wrong). None of that is worth re-reading by hand
every round, and all of it silently rots.

WHAT IT CANNOT DO. It does not judge whether a sentence reads well — no script does. It catches the
mechanical failures that make copy read as machine output, plus the one class that is a real bug
rather than a style problem: THE TWO LANGUAGES DISAGREEING ABOUT A NUMBER. That has shipped here
before — the moxa gate's intro said "four questions" over five — and it is exactly what a reader
trusts and cannot verify.

Run locally:  python3 scripts/copy_scan.py
"""
import re, sys, glob, os

PAIR = re.compile(r'AppLocale\.pick\(\s*("(?:[^"\\]|\\.)*")\s*,\s*("(?:[^"\\]|\\.)*")\s*\)', re.S)
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
INTERP = re.compile(r'\\\([^()]*(?:\([^()]*\)[^()]*)*\)')
NUM = re.compile(r'\d+(?:[.,]\d+)?')
CJK = r'一-鿿　-〿'

# Numbers that differ between the two languages BY DESIGN, with the reason. Anything not listed
# here and not identical across the pair is a failure, so a new divergence has to be argued for.
ALLOWED_NUMBER_DIVERGENCE = {
    # ChatView.crisisReply: 988 is the US/Canada lifeline and is labelled as such in English. The
    # Chinese gives the universally-correct instruction instead of a number that would be wrong.
    "988",
    # MoxaClockCopy: "2½ minutes" in English is written 2 分半 in Chinese — the same quantity, but
    # the Chinese form spells the half as a word rather than a digit.
    "2",
}

def strip_comments(src):
    """Blank out // comments so the scanner reads SHIPPED COPY, not prose about copy.

    The first run flagged a comment in Acupoints.swift that quotes a punctuation bug it is
    explaining — a scanner that cannot tell an example from a string is a scanner people learn to
    ignore. Quote-aware, because "https://…" is not a comment."""
    out = []
    for line in src.split("\n"):
        in_str = False
        i = 0
        while i < len(line):
            c = line[i]
            if c == '\\' and in_str:
                i += 2; continue
            if c == '"':
                in_str = not in_str
            elif c == '/' and not in_str and line[i:i+2] == '//':
                line = line[:i]
                break
            i += 1
        out.append(line)
    return "\n".join(out)


def clean(s):
    """Drop interpolations and escapes — they carry the same value into both languages."""
    # Sentinel, NOT a space: substituting whitespace here manufactures "space between Chinese
    # characters" on every 第\(n)步 in the app, which is how the first run of this scanner produced
    # 74 findings of which ~60 were its own doing. "X" stands in as a Latin word, which is what an
    # interpolated value usually renders as, so the Chinese/Latin spacing checks stay honest.
    return INTERP.sub("X", s).replace('\\"', '"').replace("\\n", " ")

def main():
    problems = []
    for path in sorted(glob.glob("AcuGuide/*.swift")):
        src = strip_comments(open(path, encoding="utf-8").read())
        name = os.path.basename(path)

        # ---- paired strings: the two languages must agree about facts ----
        for m in PAIR.finditer(src):
            line = src[: m.start()].count("\n") + 1
            zh, en = clean(m.group(1)[1:-1]), clean(m.group(2)[1:-1])
            dz, de = sorted(NUM.findall(zh)), sorted(NUM.findall(en))
            if dz != de:
                extra = set(dz) ^ set(de)
                if not extra <= ALLOWED_NUMBER_DIVERGENCE:
                    problems.append(
                        f"{name}:{line}: the two languages disagree about a number "
                        f"(zh={dz} en={de}). A reader trusts this and cannot check it.\n"
                        f"    zh: {zh.strip()[:90]}\n    en: {en.strip()[:90]}")
            if (zh.strip() and zh.strip() == en.strip() and len(zh.strip()) > 12
                    and re.search(f"[{CJK}]", zh)):
                problems.append(f"{name}:{line}: both languages are the same string — "
                                f"one of them was never written: {zh.strip()[:70]}")

        # ---- every literal: Chinese that reads as machine output ----
        for m in STRING.finditer(src):
            line = src[: m.start()].count("\n") + 1
            t = clean(m.group(1))
            if not re.search(f"[{CJK}]", t):
                continue
            letters = re.findall(rf"[{CJK}A-Za-z0-9]", t)
            if len(letters) < max(3, len(t) // 3):
                continue          # a punctuation character set, not a sentence
            if "您" in t:
                problems.append(f"{name}:{line}: 您 — this app addresses the reader as 你 "
                                f"everywhere else; mixing the two registers reads as translated.")
            if "的的" in t or "了了" in t:
                problems.append(f"{name}:{line}: doubled particle (的的 / 了了): {t.strip()[:60]}")
            if re.search(rf"[，。！？；：][ \t]", t):
                problems.append(f"{name}:{line}: space after Chinese punctuation "
                                f"(Chinese full-width punctuation carries its own spacing): {t.strip()[:60]}")
            # Only when the period ENDS a Chinese sentence. "…either side. 《针灸甲乙经》 vol. 3"
            # is English prose introducing a Chinese book title, and its ASCII period is correct.
            if re.search(rf"[{CJK}]\.[ \t]+[{CJK}]", t):
                problems.append(f"{name}:{line}: ASCII '. ' inside Chinese — use 。: {t.strip()[:60]}")
            if re.search(rf"[{CJK}][ \t]+[{CJK}]", t):
                problems.append(f"{name}:{line}: space between Chinese characters: {t.strip()[:60]}")
            # Half-width brackets/commas/semicolons wedged between Chinese characters. Chinese uses
            # full-width （）、，；— the ASCII forms are what survives a copy-paste out of an English
            # source or a machine translation, and they set the line with visibly wrong spacing.
            # IMMEDIATELY adjacent only. "穴位定位图谱 (Atlas of Acupuncture Points)" is a Chinese
            # title wrapping a Latin one, where half-width brackets after a space are the normal
            # setting; it is 输(木)穴 — brackets touching Chinese on both sides — that reads wrong.
            m2 = re.search(rf"[{CJK}]([(),;:])|([(),;:])[{CJK}]", t)
            if m2:
                bad = m2.group(1) or m2.group(2)
                problems.append(f"{name}:{line}: half-width '{bad}' inside Chinese — "
                                f"use the full-width form （）、，；: {t.strip()[:60]}")

    if problems:
        print(f"copy scan: {len(problems)} problem(s)\n")
        for p in problems:
            print(f"  {p}")
        return 1
    print("copy scan: clean — one register (你), no artifacts, and the two languages agree on every number")
    return 0

if __name__ == "__main__":
    sys.exit(main())
