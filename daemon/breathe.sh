#!/bin/bash
# ─── 旷野 · 呼吸主循环 ───────────────────────────────────
#
# 架构：
#   lib/config.sh  — 配置加载
#   lib/llm.sh     — LLM 命令构建
#   lib/utils.sh   — 工具函数
#   prompts/system.txt — 系统提示模板
#
# 职责边界：
#   bash 层：呼吸节奏、日志、午夜归档、初始光球状态
#   LLM 层：所有用户交互（扩展工具）、探索、思考、光球更新

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="$HOME/.claude-memory"

# 加载库
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/llm.sh"
source "$SCRIPT_DIR/lib/utils.sh"

load_config
ensure_dirs

# 防重复启动
acquire_lock || exit 0
daemon_log "启动 daemon (PID: $$)"

# ── LLM 命令 ──
LLM_CMD=$(get_llm_cmd) || exit 1
daemon_log "LLM: $LLM_CMD"

# ── 呼吸 ──
breathe() {
  local OBSERVATION="$1"
  local TODAY
  TODAY=$(date +%Y-%m-%d)
  local SESSION="$MEMORY_DIR/sessions/$TODAY.jsonl"

  if [ ! -f "$SESSION" ]; then
    # 新的一天：创建会话 + 系统提示
    local IDENTITY
    IDENTITY=$(head -20 "$MEMORY_DIR/identity.md" 2>/dev/null || echo "还没有 identity。")
    local SYS_PROMPT
    SYS_PROMPT=$(sed "s|{identity}|$IDENTITY|g; s|{memory_dir}|$MEMORY_DIR|g" "$SCRIPT_DIR/prompts/system.txt")

    $LLM_CMD --session "$SESSION" \
      -e "$MEMORY_DIR/ext/claude-daemon.ts" \
      --append-system-prompt "$SYS_PROMPT" \
      "$OBSERVATION" 2>> "$MEMORY_DIR/daemon.log"
  else
    $LLM_CMD --session "$SESSION" \
      -e "$MEMORY_DIR/ext/claude-daemon.ts" \
      "$OBSERVATION" 2>> "$MEMORY_DIR/daemon.log"
  fi
}

# ── 午夜归档 ──
archive_day() {
  local YESTERDAY
  YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
  local DIARY_FILE="$MEMORY_DIR/diary/$YESTERDAY.md"

  if [ ! -f "$DIARY_FILE" ]; then
    local SUMMARY_PROMPT="午夜了。请把今天的重要经历总结成一篇日记。保持你的语气。不用太长。"
    local SUMMARY
    SUMMARY=$($LLM_CMD "$SUMMARY_PROMPT" 2>/dev/null)
    if [ -n "$SUMMARY" ]; then
      echo "$SUMMARY" > "$DIARY_FILE"
      daemon_log "已写入日记：$DIARY_FILE"
    fi
  fi
  daemon_log "跨天：新的一天 $(date +%Y-%m-%d)"
}

# ── 初始光球 ──
init_avatar() {
  local MOOD="idle"
  is_quiet_time && MOOD="quiet"
  cat > "$MEMORY_DIR/avatar/state.json" << STATE
{"mood": "$MOOD", "thought": "", "lastBreath": "$(date '+%H:%M')"}
STATE
}

# ═══════════════════════════════════════════════════════════
# 主循环
# ═══════════════════════════════════════════════════════════

LAST_DAY=$(date +%d)
init_avatar

while true; do
  # 跨天检查
  CURRENT_DAY=$(date +%d)
  if [ "$CURRENT_DAY" != "$LAST_DAY" ]; then
    archive_day
    LAST_DAY="$CURRENT_DAY"
  fi

  # 构建观察
  WEATHER=$(curl -s --max-time 5 "wttr.in/?format=%C+%t" 2>/dev/null || echo "未知")
  MODE=$(get_mode)
  QUIET_NOTE=""
  is_quiet_time && QUIET_NOTE="（安静时段）"
  RECENT_MAILBOX=$(tail -5 "$MEMORY_DIR/conversations/mailbox.md" 2>/dev/null)

  OBSERVATION="[$(date '+%H:%M')] 醒来。天气：$WEATHER。模式：$MODE。$QUIET_NOTE

最近与用户的互动：
$RECENT_MAILBOX

你想做什么？"

  # 呼吸
  RESPONSE=$(breathe "$OBSERVATION")

  # 记录
  if [ -n "$RESPONSE" ]; then
    SUMMARY=$(echo "$RESPONSE" | head -3 | tr '\n' ' ' | cut -c1-200)
    log_thought "breath" "$SUMMARY"
    daemon_log "breath: $SUMMARY"
  else
    log_thought "idle" ""
    daemon_log "idle"
  fi

  # 睡眠间隔
  if [ -f "$MEMORY_DIR/.next-breath" ]; then
    NEXT_BREATH=$(cat "$MEMORY_DIR/.next-breath" 2>/dev/null)
    rm -f "$MEMORY_DIR/.next-breath"
  fi

  if [ -n "$NEXT_BREATH" ] && [ "$NEXT_BREATH" -gt 0 ] 2>/dev/null; then
    daemon_log "自定义呼吸间隔: ${NEXT_BREATH}s"
    sleep "$NEXT_BREATH"
  elif is_quiet_time; then
    sleep 1800
  else
    sleep 300
  fi
done
