#!/bin/bash
# 打开旷野的家（单进程原生窗口，无需 Python 服务器）
cd "$(dirname "$0")"
swift App.swift &
echo "旷野的家已开启"
