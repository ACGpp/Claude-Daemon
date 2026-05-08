#!/bin/bash
cd /Users/tree/.claude-memory/avatar
nohup python3 avatar.py &>/dev/null &
echo "Avatar PID: $!"
