#!/usr/bin/env python3
"""Belt-and-braces scan for medical-claim language in SHIPPED USER-FACING COPY.

Only string literals count, and only ones the app can SAY. Deliberate exclusions, each earned:
  - ChatLLM.swift   : it IS the enforcement mechanism -- it holds the banned-word lists and the
                      model-facing instructions forbidding them. AcuGuideTests excludes it too.
  - keywords: [...] : FAQ match terms are things a USER types ("is it a cure", "能治病吗"). They are
                      inputs, not output. The matching answers are the disclaimers.
  - Diagnostics     : the MetricKit class and its "diagnostic-*.json" filenames are not copy.
  - health/healthy  : legitimate wellness words containing "heal".
"""
import re, sys, pathlib

EN = ["treat", "cure", "heal", "diagnos"]
ZH = ["治疗", "治愈", "根治", "诊断", "医治", "疗效"]
SKIP_FILES = {"ChatLLM.swift"}
ALLOW = re.compile(r"healthy|healthcare|health|diagnostics|diagnostic|Diagnostics")
LITERAL = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')


def strip_trailing_comment(line: str) -> str:
    """Cut a trailing // comment, respecting string literals.

    Comments are not shipped copy, and the banned-term tables (MoxaSafety.extendedBanned) document
    their entries with QUOTED English glosses -- `"疗程", // "course of treatment"` -- which the
    literal regex would otherwise flag. Those comments must be able to name the phrases they ban;
    the scanner is the thing that has to know the difference. Done by walking the line rather than
    a regex so that `//` INSIDE a string ("https://...") never truncates a real literal -- cutting
    there would hide any banned term after a URL, silently weakening the scan.
    """
    in_str = False
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == "/" and i + 1 < n and line[i + 1] == "/":
                return line[:i]
        i += 1
    return line

bad = []
for p in sorted(pathlib.Path("AcuGuide").rglob("*.swift")):
    if p.name in SKIP_FILES:
        continue
    in_keywords = False
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if "keywords:" in line:
            in_keywords = True
        if in_keywords:
            if "]" in line:
                in_keywords = False
            continue
        if s.startswith("//") or s.startswith("///") or s.startswith("*"):
            continue
        for lit in LITERAL.findall(strip_trailing_comment(line)):
            probe = ALLOW.sub("", lit)
            low = probe.lower()
            for t in EN:
                if t in low:
                    bad.append(f"{p}:{n}  [{t}]  {lit[:90]}")
            for t in ZH:
                if t in probe:
                    bad.append(f"{p}:{n}  [{t}]  {lit[:90]}")

# App Store metadata is user-facing copy the reviewer reads, but it lives outside the Swift sources
# and the runtime scan can never see it. Scan the whole text of each file (no literal extraction —
# these files ARE the copy). This is the one surface where a claim would reach a reviewer directly.
for p in sorted(pathlib.Path("store").rglob("*.txt")) if pathlib.Path("store").exists() else []:
    text = p.read_text(encoding="utf-8")
    for n, line in enumerate(text.splitlines(), 1):
        probe = ALLOW.sub("", line)
        low = probe.lower()
        for t in EN:
            if t in low:
                bad.append(f"{p}:{n}  [{t}]  {line.strip()[:90]}")
        for t in ZH:
            if t in probe:
                bad.append(f"{p}:{n}  [{t}]  {line.strip()[:90]}")

if bad:
    print(f"::error::{len(bad)} medical-claim string(s) in shipped copy:")
    for b in bad[:20]:
        print("  " + b)
    sys.exit(1)
print(f"clean: no treat/cure/heal/diagnose language in app copy or store metadata")
