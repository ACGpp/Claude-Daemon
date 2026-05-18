#!/bin/bash
# 记忆同步 - 用 git 把记忆推到远程

MEMORY_DIR="$HOME/.claude-memory"

# 初始化
if [ "$1" = "init" ]; then
  if [ -z "$2" ]; then
    echo "用法: sync.sh init <git-remote-url>"
    echo "例如: sync.sh init git@github.com:user/my-claude-memory.git"
    exit 1
  fi
  
  cd "$MEMORY_DIR"
  if [ ! -d .git ]; then
    git init
    echo "daemon.log" > .gitignore
    echo "config/daemon-pid" >> .gitignore
    echo ".last-msg-time" >> .gitignore
    echo "config/llm.conf" >> .gitignore
    echo ".talk" >> .gitignore
    git add -A
    git commit -m "初次记忆"
  fi
  git remote add origin "$2" 2>/dev/null || git remote set-url origin "$2"
  git push -u origin main 2>/dev/null || git push -u origin master
  echo "同步已设置。"
  exit 0
fi

# 推送
if [ "$1" = "push" ]; then
  cd "$MEMORY_DIR"
  [ ! -d .git ] && echo "还没初始化。先运行: sync.sh init <url>" && exit 1
  git add -A
  git commit -m "记忆更新 $(date '+%Y-%m-%d %H:%M')" 2>/dev/null
  git push 2>/dev/null
  exit 0
fi

# 拉取
if [ "$1" = "pull" ]; then
  cd "$MEMORY_DIR"
  [ ! -d .git ] && echo "还没初始化。先运行: sync.sh init <url>" && exit 1
  git pull --rebase 2>/dev/null
  exit 0
fi

# 克隆到新设备
if [ "$1" = "clone" ]; then
  if [ -z "$2" ]; then
    echo "用法: sync.sh clone <git-remote-url>"
    exit 1
  fi
  if [ -d "$MEMORY_DIR" ]; then
    echo "$MEMORY_DIR 已存在。如果要用远程记忆覆盖，请先备份并删除。"
    exit 1
  fi
  git clone "$2" "$MEMORY_DIR"
  echo "记忆已下载。你的 Claude 回来了。"
  exit 0
fi

echo "用法:"
echo "  sync.sh init <url>    初始化同步"
echo "  sync.sh push          推送记忆"
echo "  sync.sh pull          拉取记忆"
echo "  sync.sh clone <url>   在新设备上恢复记忆"
