#!/usr/bin/env python3
"""
KIT v10 bundler
把 src/ 下按数字前缀排序的分片拼接成可单文件执行的 dist/*.lua。

用法:
    python3 build.py              # 构建全部 bundle
    python3 build.py --check      # 构建 + 语法校验（需要 luau-compile）
    python3 build.py --check --luau /path/to/luau-compile
    python3 build.py --smoke      # 构建 + 逻辑冒烟（需要 luau CLI 解释器）
    python3 build.py kit sibs     # 只构建指定 bundle

约定:
    每个 bundle 是一个目录, 内含一个或多个 *.lua 分片;
    分片按文件名字典序拼接（用 NN- 前缀控制顺序）,
    拼接结果是单一 Luau chunk —— 分片之间共享顶层 local,
    因此后分片可以引用前分片声明的 local。
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
DIST = ROOT / "dist"

# bundle 名 -> 源目录
BUNDLES: dict[str, str] = {
    "kit": "src/kit",
    "moc": "src/modules/moc",
    "sibs": "src/modules/sibs",
    "plane": "src/modules/plane",
    "drift": "src/modules/drift",
    "log": "src/modules/log",
    "brick": "src/modules/brick",
}


def sources_of(rel_path: str) -> list[Path]:
    p = ROOT / rel_path
    if not p.exists() and p.suffix == "":
        p = p.with_suffix(".lua")
    if p.is_file() and p.suffix == ".lua":
        return [p]
    if not p.is_dir():
        raise SystemExit(f"错误: 源不存在: {rel_path}")
    parts = sorted(q for q in p.glob("*.lua") if q.is_file())
    if not parts:
        raise SystemExit(f"错误: {rel_path} 下没有 .lua 分片")
    return parts


def bundle(name: str, rel_dir: str) -> Path:
    parts = sources_of(rel_dir)
    rel_names = [p.relative_to(ROOT).as_posix() for p in parts]
    lines: list[str] = []
    lines.append(f"-- {name}.lua — KIT v10 单文件 bundle（由 build.py 生成，勿直接编辑）")
    lines.append("-- 源: " + ", ".join(rel_names))
    lines.append("-- 构建: python3 build.py")
    lines.append("")
    in_lines = 0
    for p, rel in zip(parts, rel_names):
        text = p.read_text(encoding="utf-8")
        in_lines += text.count("\n") + (0 if text.endswith("\n") else 1)
        lines.append(f"-- ==== {rel} ====")
        lines.append(text.rstrip("\n"))
        lines.append("")
    out = "\n".join(lines) + "\n"
    DIST.mkdir(exist_ok=True)
    target = DIST / f"{name}.lua"
    target.write_text(out, encoding="utf-8")
    out_lines = out.count("\n")
    print(f"  {name:<6} {len(parts):>2} 分片  {in_lines:>5} -> {out_lines:>5} 行  {target}")
    return target


def find_luau(explicit: str | None) -> str | None:
    if explicit:
        return explicit
    env = shutil.which("luau-compile")
    if env:
        return env
    guess = ROOT.parent / "tools" / "luau-compile"
    if guess.exists():
        return str(guess)
    return None


def check(target: Path, luau: str) -> bool:
    proc = subprocess.run(
        [luau, "--text", str(target)],
        capture_output=True, text=True, errors="replace",
    )
    if proc.returncode == 0:
        return True
    sys.stderr.write(proc.stderr or proc.stdout)
    return False


# 冒烟加载顺序：kit 必须最先（提供 _G.KIT），brick 最后
SMOKE_ORDER = ["kit", "moc", "sibs", "plane", "drift", "log", "brick"]
SMOKE_HARNESS = ROOT / "tools" / "smoke.luau"
SMOKE_RUN = ROOT / "tools" / ".smoke_run.lua"
MARKER = "--@SOURCES@"


def find_luau_cli(explicit: str | None) -> str | None:
    """带解释器能力的 luau CLI（不是 luau-compile）。"""
    if explicit:
        return explicit if Path(explicit).exists() else None
    env = os.environ.get("LUAU_CLI")
    if env and Path(env).exists():
        return env
    for guess in (
        ROOT.parent / "tools" / "luau",
        ROOT.parent / "tools" / "luau-src" / "luau",
        ROOT / "luau",
    ):
        if guess.exists():
            return str(guess)
    which = shutil.which("luau")
    if which:
        return which
    return None


def strip_frozen_g(text: str) -> str:
    """CLI 的 _G 是冻结表；把 `_G.` 前缀剥离，改走裸全局（语义等价）。"""
    return re.sub(r"(?<![A-Za-z0-9_])_G\.", "", text)


def long_bracket(s: str) -> tuple[str, str]:
    lvl = 0
    while f"[{'=' * lvl}[" in s or f"]{'=' * lvl}]" in s:
        lvl += 1
    eq = "=" * lvl
    return f"[{eq}[", f"]{eq}]"


def build_smoke_script() -> Path:
    if not SMOKE_HARNESS.exists():
        raise SystemExit(f"缺少冒烟 harness: {SMOKE_HARNESS}")
    harness = SMOKE_HARNESS.read_text(encoding="utf-8")
    if harness.count(MARKER) != 1:
        raise SystemExit(f"harness 必须恰好包含一个占位符 {MARKER}: {SMOKE_HARNESS}")
    if len(SMOKE_ORDER) != len(BUNDLES):
        raise SystemExit("SMOKE_ORDER 与 BUNDLES 数量不一致")
    chunks = []
    for name in SMOKE_ORDER:
        dist_text = (DIST / f"{name}.lua").read_text(encoding="utf-8")
        dist_text = strip_frozen_g(dist_text)
        open_b, close_b = long_bracket(dist_text)
        chunks.append(f"\t{name} = {open_b}\n{dist_text}\n{close_b},")
    block = "local SOURCES = {\n" + "\n".join(chunks) + "\n}\n"
    SMOKE_RUN.write_text(harness.replace(MARKER, block, 1), encoding="utf-8")
    return SMOKE_RUN


def run_smoke(cli: str | None) -> int:
    luau = find_luau_cli(cli)
    if not luau:
        raise SystemExit("--smoke 需要 luau CLI（用 --luau-cli 或 LUAU_CLI 指定路径）")
    print("冒烟测试:")
    run = build_smoke_script()
    print(f"  生成 {run}（{run.stat().st_size // 1024} KB）")
    print(f"  执行 {luau} {run}")
    proc = subprocess.run([luau, str(run)])
    if proc.returncode == 0:
        print("  冒烟通过")
        return 0
    print(f"  冒烟失败 (exit={proc.returncode})")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="KIT v10 bundler")
    ap.add_argument("names", nargs="*", help="要构建的 bundle（默认全部）")
    ap.add_argument("--check", action="store_true", help="构建后用 luau-compile 校验语法")
    ap.add_argument("--luau", help="luau-compile 路径")
    ap.add_argument("--smoke", action="store_true", help="构建后跑逻辑冒烟（luau CLI）")
    ap.add_argument("--luau-cli", help="luau CLI 解释器路径")
    args = ap.parse_args()

    unknown = [n for n in args.names if n not in BUNDLES]
    if unknown:
        raise SystemExit(f"未知 bundle: {', '.join(unknown)}（可选: {', '.join(BUNDLES)}）")
    names = args.names or list(BUNDLES)

    luau = find_luau(args.luau) if args.check else None
    if args.check and not luau:
        raise SystemExit("--check 需要 luau-compile（用 --luau 指定路径）")

    print("构建:")
    targets = [bundle(n, BUNDLES[n]) for n in names]

    if args.check:
        print("语法校验:")
        failed = []
        for t in targets:
            if check(t, luau):
                print(f"  ok    {t.name}")
            else:
                print(f"  FAIL  {t.name}")
                failed.append(t.name)
        if failed:
            print(f"校验失败: {', '.join(failed)}")
            return 1
        print("全部通过")

    if args.smoke:
        if names != list(BUNDLES):
            raise SystemExit("--smoke 需要构建全部 bundle（不要指定子集）")
        return run_smoke(args.luau_cli)
    return 0


if __name__ == "__main__":
    sys.exit(main())
