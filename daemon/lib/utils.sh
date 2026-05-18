# ─── 工具函数 ──────────────────────────────────────────────
# 被 daemon/breathe.sh 和 bin/ 脚本共用
# 需要先 source daemon/lib/config.sh

# 安静时段检查
is_quiet_time() {
  local HOUR
  HOUR=$(date +%H)
  HOUR=$((10#$HOUR))
  if [ "$QUIET_START" -le "$QUIET_END" ]; then
    [ "$HOUR" -ge "$QUIET_START" ] && [ "$HOUR" -lt "$QUIET_END" ]
  else
    [ "$HOUR" -ge "$QUIET_START" ] || [ "$HOUR" -lt "$QUIET_END" ]
  fi
}

# 思维流日志
log_thought() {
  local TYPE="$1"
  local CONTENT="$2"
  local ESCAPED
  local THOUGHTS="$MEMORY_DIR/thoughts/stream.jsonl"
  ESCAPED=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))" <<< "$CONTENT" 2>/dev/null || echo "\"\"")
  echo "{\"time\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"$TYPE\",\"content\":$ESCAPED}" >> "$THOUGHTS"
}

# daemon 日志
daemon_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$MEMORY_DIR/daemon.log"
}

# 确保目录存在
ensure_dirs() {
  mkdir -p "$MEMORY_DIR"/{config,diary,thoughts,explorations,conversations,private,backups,context,sessions,avatar}
}

# 原子锁（防重复启动）
acquire_lock() {
  local LOCK_FILE="$MEMORY_DIR/config/daemon.lock"
  local PID_FILE="$MEMORY_DIR/config/daemon-pid"
  if ! (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
    local LOCKED_PID
    LOCKED_PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$LOCKED_PID" ] && kill -0 "$LOCKED_PID" 2>/dev/null; then
      echo "daemon 已在运行 (PID: $LOCKED_PID)"
      return 1
    fi
    echo "$$" > "$LOCK_FILE"
  fi
  echo $$ > "$PID_FILE"
  # 退出时清理
  trap 'rm -f "$MEMORY_DIR/config/daemon.lock" "$PID_FILE"' EXIT
  return 0
}
