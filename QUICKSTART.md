# NotebookLM2API 快速参考

## 一键命令

### 本地提取认证
```bash
./scripts/extract_auth.sh
```

### Docker 部署
```bash
# 拉取镜像
docker pull ghcr.io/samuncleorange/notebooklm2api:latest

# 运行 (替换 <...> 中的内容)
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  -e NOTEBOOKLM_AUTH_JSON='<从 extract_auth.sh 获取>' \
  -e NOTEBOOKLM_NOTEBOOK_ID='<你的 notebook ID>' \
  -e API_KEY='<你的 API 密钥>' \
  --restart unless-stopped \
  ghcr.io/samuncleorange/notebooklm2api:latest
```

### Docker Compose 部署
```bash
# 创建 .env 文件
cat > .env << EOF
NOTEBOOKLM_AUTH_JSON=<从 extract_auth.sh 获取>
NOTEBOOKLM_NOTEBOOK_ID=<你的 notebook ID>
API_KEY=<你的 API 密钥>
EOF

# 启动
docker-compose up -d

# 查看日志
docker-compose logs -f
```

## 常用命令

### Docker 管理
```bash
# 查看日志
docker logs notebooklm-api

# 实时日志
docker logs -f notebooklm-api

# 重启容器
docker restart notebooklm-api

# 停止容器
docker stop notebooklm-api

# 删除容器
docker rm notebooklm-api

# 更新镜像
docker pull ghcr.io/samuncleorange/notebooklm2api:latest
docker stop notebooklm-api
docker rm notebooklm-api
# 然后重新运行 docker run 命令
```

### API 测试
```bash
# 健康检查
curl http://localhost:8000/health

# 列出模型
curl http://localhost:8000/v1/models \
  -H "Authorization: Bearer your-api-key"

# 聊天完成
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{
    "model": "notebooklm",
    "messages": [{"role": "user", "content": "What are the key themes?"}]
  }'

# 运行测试脚本
python test_api.py --api-key your-api-key --notebook-id your-notebook-id
```

## Python 使用示例

### 基本用法
```python
from openai import OpenAI

client = OpenAI(
    api_key="your-api-key",
    base_url="http://your-vps-ip:8000/v1"
)

response = client.chat.completions.create(
    model="notebooklm",
    messages=[{"role": "user", "content": "What are the key themes?"}]
)

print(response.choices[0].message.content)
```

### 流式响应
```python
response = client.chat.completions.create(
    model="notebooklm",
    messages=[{"role": "user", "content": "What are the key themes?"}],
    stream=True
)

for chunk in response:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

### 指定 Notebook
```python
response = client.chat.completions.create(
    model="notebooklm",
    messages=[{"role": "user", "content": "What are the key themes?"}],
    extra_body={"notebook_id": "another-notebook-id"}
)
```

## 故障排除速查

| 问题 | 解决方案 |
|------|----------|
| 认证失败 | 重新运行 `./scripts/extract_auth.sh` 并更新 `NOTEBOOKLM_AUTH_JSON` |
| 端口被占用 | 修改 `-p 8000:8000` 为 `-p 8001:8000` |
| Notebook ID 无效 | 设置 `NOTEBOOKLM_NOTEBOOK_ID` 或在请求中提供 `notebook_id` |
| 容器无法启动 | 运行 `docker logs notebooklm-api` 查看错误 |
| API 返回 401 | 检查 `API_KEY` 是否正确 |

## 环境变量

| 变量 | 必需 | 说明 |
|------|------|------|
| `NOTEBOOKLM_AUTH_JSON` | 是* | 认证信息 |
| `NOTEBOOKLM_NOTEBOOK_ID` | 否** | 默认 Notebook ID |
| `API_KEY` | 否 | API 密钥 |
| `PORT` | 否 | 端口 (默认 8000) |
| `HOST` | 否 | 主机 (默认 0.0.0.0) |

\* 如果挂载了认证文件则不需要  
\*\* 如果不设置，每个请求必须提供 notebook_id

## 获取信息

### Notebook ID
```bash
# 方法 1: CLI
notebooklm list

# 方法 2: 从 URL
# https://notebooklm.google.com/notebook/abc123xyz
#                                          ^^^^^^^^^ 这是 ID
```

### 认证信息
```bash
# 运行提取脚本
./scripts/extract_auth.sh

# 或手动
cat ~/.notebooklm/storage_state.json | jq -c '.'
```

## 安全配置

### 使用 Nginx 反向代理
```nginx
server {
    listen 443 ssl;
    server_name api.yourdomain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 防火墙规则
```bash
# 只允许特定 IP 访问
sudo ufw allow from YOUR_IP to any port 8000

# 或使用 Nginx 限制
# 在 nginx 配置中添加:
# allow YOUR_IP;
# deny all;
```

## 更多信息

- 详细部署指南: [VPS_DEPLOYMENT.md](VPS_DEPLOYMENT.md)
- 完整文档: [README_CN.md](README_CN.md)
- 原项目: https://github.com/teng-lin/notebooklm-py
