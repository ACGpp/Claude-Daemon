# ─── LLM 命令构建 ──────────────────────────────────────────
# 需要先 source daemon/lib/config.sh

build_llm_cmd() {
  # 优先使用配置的 LLM_TOOL
  if [ -n "$LLM_TOOL" ]; then
    case "$LLM_TOOL" in
      pi)    echo "pi -p" ;;
      claude) echo "claude -p" ;;
      *)     echo "$LLM_TOOL" ;;
    esac
    return
  fi
  # 自动检测
  if command -v pi &>/dev/null; then
    echo "pi -p"
  elif command -v claude &>/dev/null; then
    echo "claude -p"
  else
    echo ""
  fi
}

get_llm_cmd() {
  local BASE
  BASE=$(build_llm_cmd)
  if [ -z "$BASE" ]; then
    echo "需要 pi CLI。" >&2
    return 1
  fi

  local CMD="$BASE"
  if [ "$BASE" = "pi -p" ]; then
    [ -n "$PI_PROVIDER" ] && CMD="$CMD --provider $PI_PROVIDER"
    [ -n "$PI_MODEL" ]    && CMD="$CMD --model $PI_MODEL"
    [ -n "$PI_API_KEY" ]  && CMD="$CMD --api-key $PI_API_KEY"
  elif [ "$BASE" = "claude -p" ]; then
    [ -n "$CLAUDE_MODEL" ] && CMD="$CMD --model $CLAUDE_MODEL"
  fi
  echo "$CMD"
}
