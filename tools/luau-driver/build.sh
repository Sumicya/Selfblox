#!/bin/bash
# 编一个本地 Luau 0.741 用来跑离线自检 (官方 release 的资源域名在沙箱里下不动, codeload 通)
# 约 40 秒, 只需跑一次; 之后改完代码跑 run_smoke.sh 就行 (0.3 秒)
set -e
V=0.741
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -d /tmp/luausrc ] || { curl -sSL -o /tmp/luau-src.tar.gz https://codeload.github.com/luau-lang/luau/tar.gz/refs/tags/$V; mkdir -p /tmp/luausrc; tar xzf /tmp/luau-src.tar.gz -C /tmp/luausrc --strip-components=1; }
cd /tmp/luausrc
g++ -O1 -std=c++17 -w -ICommon/include -IVM/include -ICompiler/include -IAst/include -IBytecode/include \
    "$HERE/run.cpp" $(ls Ast/src/*.cpp Common/src/*.cpp VM/src/*.cpp Compiler/src/*.cpp Bytecode/src/*.cpp) -o "$HERE/luau"
echo "编好了: $HERE/luau"
