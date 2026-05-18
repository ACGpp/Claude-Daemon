#!/bin/bash
# 打开旷野的家 — 桌面窗口
cd "$(dirname "$0")"
python3 server.py &
echo "旷野的家已开启 → http://localhost:15180"
