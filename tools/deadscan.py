#!/usr/bin/env python3
"""死代码与盲区检查:
1. `local` 标识符在剔除注释与字符串字面量(含 Luau 反引号插值外文本)的源码里出现 <= 1 次 = 疑似死码;
2. 校验 `tools/*.py` 无未使用的 import;
3. 校验 `save("k", ...)` 键均有对应的 `opt("k", ...)` 读取;
4. 校验 `tools/blindspots.json` 三类盲区(有意排除/延期未审/待答问题)结构与剩余限制字段完整。
用法: python3 tools/deadscan.py [文件...]   (默认 selfblox.lua)
退出码: 0 干净, 1 有问题。
"""
import ast
import json
from pathlib import Path
import re
import sys

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
LOCAL = re.compile(
    r"\blocal\s+(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)"
)
OPT_KEY = re.compile(r'\bopt\(\s*"([^"]+)"')
SAVE_KEY = re.compile(r'\bsave\(\s*"([^"]+)"')


def clean_luau(src: str) -> str:
    """剔除注释与字符串字面量; Luau 反引号字符串保留 `{expr}` 内的代码。"""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src[i : i + 2] == "--":
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i + len(m.group(0)))
                i = n if end < 0 else end + len(m.group(1)) + 2
                out.append(" ")
            else:
                end = src.find("\n", i)
                i = n if end < 0 else end
                out.append(" ")
        elif c == "[":
            m = re.match(r"\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i + len(m.group(0)))
                i = n if end < 0 else end + len(m.group(1)) + 2
                out.append('""')
            else:
                out.append(c)
                i += 1
        elif c in ('"', "'"):
            q = c
            i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
            i += 1
            out.append('""')
        elif c == "`":
            i += 1
            out.append('"')
            while i < n and src[i] != "`":
                if src[i] == "\\":
                    i += 2
                elif src[i] == "{":
                    i += 1
                    out.append(" ")
                    depth = 1
                    while i < n and depth > 0:
                        if src[i] == "{":
                            depth += 1
                        elif src[i] == "}":
                            depth -= 1
                            if depth == 0:
                                i += 1
                                break
                        out.append(src[i])
                        i += 1
                    out.append(" ")
                else:
                    if src[i] == "\n":
                        out.append("\n")
                    i += 1
            i += 1
            out.append('"')
        else:
            out.append(c)
            i += 1
    return "".join(out)


def scan_luau(path: Path):
    raw = path.read_text(encoding="utf-8")
    src = clean_luau(raw)
    counts = {}
    for m in IDENT.finditer(src):
        w = m.group(0)
        counts[w] = counts.get(w, 0) + 1
    dead = []
    seen = set()
    for m in LOCAL.finditer(src):
        for name in re.split(r"\s*,\s*", m.group(1)):
            key = (m.start(), name)
            if counts.get(name, 0) <= 1 and key not in seen:
                seen.add(key)
                dead.append((src[: m.start()].count("\n") + 1, name))
    opts = set(OPT_KEY.findall(raw))
    saves = set(SAVE_KEY.findall(raw))
    write_only = sorted(saves - opts)
    return dead, write_only


def scan_py_imports(py_files):
    unused = []
    for p in py_files:
        tree = ast.parse(p.read_text(encoding="utf-8"), filename=str(p))
        imported = {}
        used = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    name = alias.asname or alias.name.split(".")[0]
                    imported[name] = node.lineno
            elif isinstance(node, ast.ImportFrom):
                for alias in node.names:
                    if alias.name != "*":
                        name = alias.asname or alias.name
                        imported[name] = node.lineno
            elif isinstance(node, ast.Name):
                used.add(node.id)
        for name, line in imported.items():
            if name not in used:
                unused.append((str(p), line, name))
    return unused


def check_blindspots(path: Path):
    errs = []
    if not path.exists():
        return [f"缺少盲区清单: {path}"]
    data = json.loads(path.read_text(encoding="utf-8"))
    for cat in ("有意排除", "延期未审", "待答问题"):
        items = data.get(cat)
        if not isinstance(items, list):
            errs.append(f"{path}: 缺少列表键 {cat}")
            continue
        for idx, item in enumerate(items):
            if not isinstance(item, dict):
                errs.append(f"{path}: {cat}[{idx}] 必须为对象")
                continue
            for req in ("target", "reason", "remaining_limitations"):
                val = item.get(req)
                if not isinstance(val, str) or not val.strip():
                    errs.append(f"{path}: {cat}[{idx}] 缺少非空字段 {req}")
    return errs


def main() -> int:
    paths = [Path(p) for p in (sys.argv[1:] or ["selfblox.lua"])]
    bad = 0
    for p in paths:
        dead, write_only = scan_luau(p)
        for line, name in dead:
            print(f"{p}:{line}: 疑似死码 local {name}")
            bad += 1
        for key in write_only:
            print(f"{p}: 只写不读配置键 save(\"{key}\")")
            bad += 1
    for p, line, name in scan_py_imports(sorted(Path("tools").glob("*.py"))):
        print(f"{p}:{line}: 未使用 import {name}")
        bad += 1
    for err in check_blindspots(Path("tools/blindspots.json")):
        print(err)
        bad += 1
    print(f"deadscan: {len(paths)} Luau 文件, 问题 {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
