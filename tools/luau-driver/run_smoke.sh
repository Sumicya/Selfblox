#!/bin/bash
# 离线自检: selfblox.lua 用 [====[ ... ]====] 注入成 SB_SRC_INJECTED, 再接 smoke.lua
# 最后一行是「全部通过 ✓」才算过; 有断言没过时 smoke.lua 会 error 退出, 退出码非零
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 2
[ -x /tmp/luau ] || { echo "还没编 Luau, 先跑: bash tools/luau-driver/build.sh"; exit 2; }
{ printf 'local SB_SRC_INJECTED = [====[\n'; cat selfblox.lua; printf '\n]====]\n\n'; cat smoke.lua; } > /tmp/sb_smoke.lua
/tmp/luau /tmp/sb_smoke.lua 2>&1
