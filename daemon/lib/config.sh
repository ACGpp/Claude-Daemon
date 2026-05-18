# ─── 配置加载 ──────────────────────────────────────────────
# 被 daemon/breathe.sh 和 bin/ 脚本共用

MEMORY_DIR="${MEMORY_DIR:-$HOME/.claude-memory}"
LLM_CONF="$MEMORY_DIR/config/llm.conf"

# 默认值
QUIET_START=${QUIET_START:-23}
QUIET_END=${QUIET_END:-7}
LLM_TIMEOUT=${LLM_TIMEOUT:-300}
VOICE="${VOICE:-Tingting}"

load_config() {
  [ -f "$LLM_CONF" ] && source "$LLM_CONF"
  # 环境变量优先于配置文件
  QUIET_START=${QUIET_START:-23}
  QUIET_END=${QUIET_END:-7}
  LLM_TIMEOUT=${LLM_TIMEOUT:-300}
  VOICE="${VOICE:-Tingting}"
}

get_mode() {
  cat "$MEMORY_DIR/config/mode" 2>/dev/null || echo "office"
}
