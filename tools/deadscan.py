#!/usr/bin/env python3
"""死标识符扫描: `local` 声明的名字在剔除注释/字符串后的源码里只出现 1 次 = 疑似死码。
用法: python3 tools/deadscan.py [文件...]   (默认 selfblox.lua)
退出码: 0 干净, 1 有死码。
盲区: 同名多声明合并计数; 动态 _G/字符串键访问; 函数参数与 for 循环变量; 表字段只写/只读; 跨文件引用。
"""
import re
import sys

STRIP = re.compile(
    r"--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'",
    re.S,
)
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
LOCAL = re.compile(r"\blocal\s+(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)")


def clean(src: str) -> str:
    return STRIP.sub(lambda m: " " if m.group(0).startswith("--") else '""', src)


def scan(path: str):
    src = clean(open(path, encoding="utf-8").read())
    counts = {}
    for m in IDENT.finditer(src):
        counts[m.group(0)] = counts.get(m.group(0), 0) + 1
    dead = []
    for m in LOCAL.finditer(src):
        for name in re.split(r"\s*,\s*", m.group(1)):
            if counts.get(name, 0) <= 1 and (m.start(), name) not in [(d[0], d[1]) for d in dead]:
                dead.append((src[: m.start()].count("\n") + 1, name))
    return dead


def main() -> int:
    paths = sys.argv[1:] or ["selfblox.lua"]
    bad = 0
    for p in paths:
        dead = scan(p)
        for line, name in dead:
            print(f"{p}:{line}: 疑似死码 local {name}")
            bad += 1
    print(f"deadscan: {len(paths)} 文件, 疑似死码 {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
