#!/bin/bash
# VPS 部署脚本
# 使用 .env 文件管理配置，安全且易于维护

set -e

echo "========================================"
echo "NotebookLM API 部署脚本"
echo "========================================"
echo ""

# 检查 .env 文件是否存在
if [ ! -f ".env" ]; then
    echo "❌ 错误: .env 文件不存在"
    echo ""
    echo "请创建 .env 文件并填入以下内容:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat << 'EOF'
NOTEBOOKLM_AUTH_JSON={"cookies":[...]}
NOTEBOOKLM_NOTEBOOK_ID=your-notebook-id
API_KEY=your-secret-key
PORT=8000
EOF
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "提示: 运行 ./scripts/extract_auth.sh 可以生成认证信息"
    exit 1
fi

echo "✅ 找到 .env 文件"
echo ""

# 加载 .env 文件
source .env

# 验证必需的环境变量
if [ -z "$NOTEBOOKLM_AUTH_JSON" ]; then
    echo "❌ 错误: NOTEBOOKLM_AUTH_JSON 未设置"
    exit 1
fi

echo "📋 配置信息:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "认证 JSON: ${NOTEBOOKLM_AUTH_JSON:0:50}... (已设置)"
echo "Notebook ID: ${NOTEBOOKLM_NOTEBOOK_ID:-未设置（将在请求中提供）}"
echo "API Key: ${API_KEY:-未设置（无认证保护）}"
echo "端口: ${PORT:-8000}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 询问部署方式
echo "请选择部署方式:"
echo "1) Docker Compose (推荐)"
echo "2) Docker Run"
echo ""
read -p "请选择 [1/2]: " choice

case $choice in
    1)
        echo ""
        echo "🐳 使用 Docker Compose 部署..."
        
        # 检查 docker-compose 是否安装
        if ! command -v docker-compose &> /dev/null; then
            echo "❌ 错误: docker-compose 未安装"
            echo "请安装 docker-compose 或选择方式 2"
            exit 1
        fi
        
        # 停止旧容器
        if docker-compose ps | grep -q notebooklm-api; then
            echo "🛑 停止旧容器..."
            docker-compose down
        fi
        
        # 拉取最新镜像
        echo "📥 拉取最新镜像..."
        docker-compose pull
        
        # 启动容器
        echo "🚀 启动容器..."
        docker-compose up -d
        
        echo ""
        echo "✅ 部署成功！"
        echo ""
        echo "查看日志: docker-compose logs -f"
        echo "停止服务: docker-compose down"
        echo "重启服务: docker-compose restart"
        ;;
        
    2)
        echo ""
        echo "🐳 使用 Docker Run 部署..."
        
        # 停止并删除旧容器
        if docker ps -a | grep -q notebooklm-api; then
            echo "🛑 停止并删除旧容器..."
            docker stop notebooklm-api 2>/dev/null || true
            docker rm notebooklm-api 2>/dev/null || true
        fi
        
        # 拉取最新镜像
        echo "📥 拉取最新镜像..."
        docker pull ghcr.io/samuncleorange/notebooklm2api:latest
        
        # 启动容器
        echo "🚀 启动容器..."
        docker run -d \
          --name notebooklm-api \
          -p ${PORT:-8000}:8000 \
          -e NOTEBOOKLM_AUTH_JSON="$NOTEBOOKLM_AUTH_JSON" \
          -e NOTEBOOKLM_NOTEBOOK_ID="$NOTEBOOKLM_NOTEBOOK_ID" \
          -e API_KEY="$API_KEY" \
          --restart unless-stopped \
          ghcr.io/samuncleorange/notebooklm2api:latest
        
        echo ""
        echo "✅ 部署成功！"
        echo ""
        echo "查看日志: docker logs -f notebooklm-api"
        echo "停止服务: docker stop notebooklm-api"
        echo "重启服务: docker restart notebooklm-api"
        ;;
        
    *)
        echo "❌ 无效的选择"
        exit 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 测试 API"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 等待服务启动
echo "⏳ 等待服务启动..."
sleep 5

# 健康检查
echo "🏥 健康检查..."
if curl -s http://localhost:${PORT:-8000}/health | grep -q "healthy"; then
    echo "✅ 服务运行正常！"
else
    echo "⚠️  服务可能未正常启动，请检查日志"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 访问信息"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "健康检查: http://localhost:${PORT:-8000}/health"
echo "API 端点: http://localhost:${PORT:-8000}/v1/chat/completions"
echo ""
echo "测试命令:"
echo "curl http://localhost:${PORT:-8000}/v1/chat/completions \\"
echo "  -H 'Content-Type: application/json' \\"
if [ -n "$API_KEY" ]; then
    echo "  -H 'Authorization: Bearer $API_KEY' \\"
fi
echo "  -d '{\"model\":\"notebooklm\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✨ 部署完成！详细文档请参阅 VPS_DEPLOYMENT.md"
