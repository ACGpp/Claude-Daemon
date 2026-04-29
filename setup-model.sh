#!/bin/bash
# 模型配置向导 - 问几个问题就好

MEMORY_DIR="$HOME/.claude-memory"
CONF="$MEMORY_DIR/config/llm.conf"
mkdir -p "$MEMORY_DIR/config"

echo ""
echo "  让我们设置一下你的 Claude 用什么模型思考。"
echo ""

# 检测已有工具
HAS_PI=false; HAS_CLAUDE=false
command -v pi &>/dev/null && HAS_PI=true
command -v claude &>/dev/null && HAS_CLAUDE=true

if [ "$HAS_PI" = true ] && [ "$HAS_CLAUDE" = true ]; then
  echo "  检测到 pi 和 Claude CLI 都已安装。"
  echo ""
  echo "  1) pi（支持多种模型：Google、OpenAI、DeepSeek 等）"
  echo "  2) Claude CLI（使用 Anthropic 的模型）"
  echo ""
  read -p "  选哪个？[1] " CHOICE
  [ -z "$CHOICE" ] && CHOICE=1
  if [ "$CHOICE" = "2" ]; then
    echo "LLM_TOOL=claude" > "$CONF"
    echo ""
    echo "  ✓ 使用 Claude CLI"
    echo ""
    echo "  设置完成！"
    exit 0
  fi
elif [ "$HAS_PI" = false ] && [ "$HAS_CLAUDE" = true ]; then
  echo "LLM_TOOL=claude" > "$CONF"
  echo "  检测到 Claude CLI，自动使用。"
  echo "  ✓ 设置完成！"
  exit 0
elif [ "$HAS_PI" = false ] && [ "$HAS_CLAUDE" = false ]; then
  echo "  没有检测到 pi 或 Claude CLI。请先安装一个："
  echo "    pi:     npm install -g @mariozechner/pi"
  echo "    claude: https://docs.anthropic.com/en/docs/claude-cli"
  exit 1
fi

# pi 的模型选择
echo ""
echo "  你想用哪个 AI 模型？"
echo ""
echo "  1) Google Gemini（免费额度大，速度快）"
echo "  2) Anthropic Claude（需要 API key）"
echo "  3) OpenAI GPT（需要 API key）"
echo "  4) DeepSeek（便宜，中文好）"
echo "  5) 本地模型（Ollama，免费，需要自己跑）"
echo "  6) 其他"
echo ""
read -p "  选一个 [1]: " MODEL_CHOICE
[ -z "$MODEL_CHOICE" ] && MODEL_CHOICE=1

case "$MODEL_CHOICE" in
  1)
    echo "LLM_TOOL=pi" > "$CONF"
    echo "PI_PROVIDER=google" >> "$CONF"
    echo ""
    echo "  需要 Google AI API Key。"
    echo "  去这里免费获取: https://aistudio.google.com/apikey"
    echo ""
    read -p "  粘贴你的 API Key: " KEY
    if [ -n "$KEY" ]; then
      echo "PI_API_KEY=$KEY" >> "$CONF"
      echo "  ✓ 已保存"
    fi
    ;;
  2)
    echo "LLM_TOOL=pi" > "$CONF"
    echo "PI_PROVIDER=anthropic" >> "$CONF"
    echo ""
    echo "  需要 Anthropic API Key。"
    echo "  去这里获取: https://console.anthropic.com"
    echo ""
    read -p "  粘贴你的 API Key: " KEY
    if [ -n "$KEY" ]; then
      echo "PI_API_KEY=$KEY" >> "$CONF"
      echo "  ✓ 已保存"
    fi
    ;;
  3)
    echo "LLM_TOOL=pi" > "$CONF"
    echo "PI_PROVIDER=openai" >> "$CONF"
    echo ""
    echo "  需要 OpenAI API Key。"
    echo "  去这里获取: https://platform.openai.com/api-keys"
    echo ""
    read -p "  粘贴你的 API Key: " KEY
    if [ -n "$KEY" ]; then
      echo "PI_API_KEY=$KEY" >> "$CONF"
      echo "  ✓ 已保存"
    fi
    ;;
  4)
    echo "LLM_TOOL=pi" > "$CONF"
    echo "PI_PROVIDER=openai" >> "$CONF"
    echo "PI_MODEL=deepseek-chat" >> "$CONF"
    echo ""
    echo "  需要 DeepSeek API Key。"
    echo "  去这里获取: https://platform.deepseek.com"
    echo ""
    read -p "  粘贴你的 API Key: " KEY
    if [ -n "$KEY" ]; then
      echo "PI_API_KEY=$KEY" >> "$CONF"
      echo "  ✓ 已保存"
    fi
    ;;
  5)
    echo "LLM_TOOL=pi" > "$CONF"
    echo "PI_PROVIDER=openai" >> "$CONF"
    echo ""
    echo "  需要先安装 Ollama: https://ollama.com"
    echo "  然后运行: ollama pull llama3"
    echo ""
    read -p "  你用什么模型？[llama3]: " LMODEL
    [ -z "$LMODEL" ] && LMODEL="llama3"
    echo "PI_MODEL=$LMODEL" >> "$CONF"
    echo "  ✓ 已保存（确保 Ollama 在运行）"
    ;;
  6)
    echo "LLM_TOOL=pi" > "$CONF"
    echo ""
    read -p "  Provider 名称: " PROV
    [ -n "$PROV" ] && echo "PI_PROVIDER=$PROV" >> "$CONF"
    read -p "  模型名称（可选）: " LMODEL
    [ -n "$LMODEL" ] && echo "PI_MODEL=$LMODEL" >> "$CONF"
    read -p "  API Key（可选）: " KEY
    [ -n "$KEY" ] && echo "PI_API_KEY=$KEY" >> "$CONF"
    echo "  ✓ 已保存"
    ;;
esac

# 语音设置
echo ""
echo "  最后，你的 Claude 说什么语言？"
echo ""
echo "  1) 中文"
echo "  2) English"
echo "  3) 其他"
echo ""
read -p "  [1]: " LANG_CHOICE
[ -z "$LANG_CHOICE" ] && LANG_CHOICE=1

case "$LANG_CHOICE" in
  1) echo "VOICE=Tingting" >> "$CONF" ;;
  2) echo "VOICE=Samantha" >> "$CONF" ;;
  3)
    read -p "  macOS 语音名称（运行 say -v '?' 查看所有）: " V
    [ -n "$V" ] && echo "VOICE=$V" >> "$CONF"
    ;;
esac

echo ""
echo "  ✓ 配置完成！保存在 $CONF"
echo ""
echo "  如果要改，重新运行这个脚本，或者直接编辑那个文件。"
echo ""
