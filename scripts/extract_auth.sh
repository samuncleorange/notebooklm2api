#!/bin/bash
# 认证信息提取脚本
# 用于从本地提取 NotebookLM 认证信息并准备用于 VPS 部署

set -e

echo "========================================"
echo "NotebookLM 认证信息提取工具"
echo "========================================"
echo ""

# 检查 storage_state.json 是否存在
STORAGE_FILE="$HOME/.notebooklm/storage_state.json"

if [ ! -f "$STORAGE_FILE" ]; then
    echo "❌ 错误: 认证文件不存在: $STORAGE_FILE"
    echo ""
    echo "请先运行以下命令进行认证:"
    echo "  pip install 'notebooklm-py[browser]'"
    echo "  playwright install chromium"
    echo "  notebooklm login"
    exit 1
fi

echo "✅ 找到认证文件: $STORAGE_FILE"
echo ""

# 检查是否安装了 jq
if ! command -v jq &> /dev/null; then
    echo "⚠️  警告: 未安装 jq，将输出原始 JSON"
    echo "建议安装 jq 以获得更好的格式化输出:"
    echo "  macOS: brew install jq"
    echo "  Ubuntu: sudo apt-get install jq"
    echo ""
    AUTH_JSON=$(cat "$STORAGE_FILE")
else
    # 使用 jq 压缩为单行
    AUTH_JSON=$(cat "$STORAGE_FILE" | jq -c '.')
fi

# 显示认证 JSON（截断显示）
echo "📋 认证 JSON (NOTEBOOKLM_AUTH_JSON):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ ${#AUTH_JSON} -gt 200 ]; then
    echo "${AUTH_JSON:0:200}..."
    echo "... (总长度: ${#AUTH_JSON} 字符)"
else
    echo "$AUTH_JSON"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 保存到临时文件
TEMP_FILE="/tmp/notebooklm_auth.txt"
echo "$AUTH_JSON" > "$TEMP_FILE"
echo "✅ 完整的认证 JSON 已保存到: $TEMP_FILE"
echo ""

# 获取 Notebook 列表
echo "📚 获取 Notebook 列表..."
echo ""

if command -v notebooklm &> /dev/null; then
    echo "可用的 Notebooks:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    notebooklm list 2>/dev/null || echo "⚠️  无法获取 Notebook 列表，请手动从网页获取"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
else
    echo "⚠️  notebooklm 命令未找到，跳过 Notebook 列表"
    echo ""
fi

# 生成 Docker 运行命令
echo "🐳 Docker 运行命令:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat << 'EOF'
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  -e NOTEBOOKLM_AUTH_JSON='<AUTH_JSON>' \
  -e NOTEBOOKLM_NOTEBOOK_ID='<NOTEBOOK_ID>' \
  -e API_KEY='<YOUR_API_KEY>' \
  --restart unless-stopped \
  ghcr.io/samuncleorange/notebooklm2api:latest
EOF
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 生成环境变量导出命令
echo "📝 环境变量设置命令:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "export NOTEBOOKLM_AUTH_JSON='$AUTH_JSON'"
echo "export NOTEBOOKLM_NOTEBOOK_ID='<NOTEBOOK_ID>'"
echo "export API_KEY='<YOUR_API_KEY>'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 生成 .env 文件内容
ENV_FILE="/tmp/notebooklm.env"
cat > "$ENV_FILE" << EOF
NOTEBOOKLM_AUTH_JSON=$AUTH_JSON
NOTEBOOKLM_NOTEBOOK_ID=<NOTEBOOK_ID>
API_KEY=<YOUR_API_KEY>
EOF

echo "✅ .env 文件模板已保存到: $ENV_FILE"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 下一步操作:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. 复制认证 JSON:"
echo "   cat $TEMP_FILE | pbcopy  # macOS"
echo "   cat $TEMP_FILE | xclip -selection clipboard  # Linux"
echo ""
echo "2. 获取 Notebook ID:"
echo "   - 访问 https://notebooklm.google.com/"
echo "   - 打开你的 notebook"
echo "   - 从 URL 中复制 ID"
echo ""
echo "3. 在 VPS 上部署:"
echo "   - 将认证 JSON 和 Notebook ID 替换到上面的命令中"
echo "   - 运行 Docker 命令"
echo ""
echo "4. 测试 API:"
echo "   curl http://your-vps-ip:8000/health"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✨ 完成！详细文档请参阅 VPS_DEPLOYMENT.md"
