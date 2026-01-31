# NotebookLM2API

这是一个基于 [notebooklm-py](https://github.com/teng-lin/notebooklm-py) 的 OpenAI 兼容 API 服务器，可以让你通过标准的 OpenAI API 格式调用 NotebookLM。

## 特性

- ✅ **OpenAI 兼容**: 使用标准的 OpenAI SDK 或 API 格式
- ✅ **Docker 部署**: 完整的容器化支持
- ✅ **GitHub Actions**: 自动构建 Docker 镜像
- ✅ **无浏览器认证**: 支持在 VPS 上无头部署
- ✅ **流式响应**: 支持流式和非流式响应
- ✅ **多 Notebook**: 可以在请求中指定不同的 notebook

## 快速开始

### 1. 本地认证

在你的本地机器上（有浏览器的环境）：

```bash
# 安装依赖
pip install "notebooklm-py[browser]"
playwright install chromium

# 登录 NotebookLM
notebooklm login

# 导出认证信息
cat ~/.notebooklm/storage_state.json | jq -c '.'
```

复制输出的 JSON，这就是你的认证信息。

### 2. 获取 Notebook ID

访问 https://notebooklm.google.com/，打开你的 notebook，从 URL 中获取 ID：

```
https://notebooklm.google.com/notebook/abc123xyz
                                         ^^^^^^^^^
                                      这就是 notebook ID
```

或使用 CLI：

```bash
notebooklm list
```

### 3. 在 VPS 上部署

#### 使用 Docker（推荐）

```bash
# 拉取镜像
docker pull ghcr.io/samuncleorange/notebooklm2api:latest

# 运行容器
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  -e NOTEBOOKLM_AUTH_JSON='{"cookies":[...]}' \
  -e NOTEBOOKLM_NOTEBOOK_ID='your-notebook-id' \
  -e API_KEY='your-secret-key' \
  --restart unless-stopped \
  ghcr.io/samuncleorange/notebooklm2api:latest
```

#### 使用 Docker Compose

创建 `docker-compose.yml`:

```yaml
version: '3.8'

services:
  notebooklm-api:
    image: ghcr.io/samuncleorange/notebooklm2api:latest
    container_name: notebooklm-api
    ports:
      - "8000:8000"
    environment:
      - NOTEBOOKLM_AUTH_JSON=${NOTEBOOKLM_AUTH_JSON}
      - NOTEBOOKLM_NOTEBOOK_ID=${NOTEBOOKLM_NOTEBOOK_ID}
      - API_KEY=${API_KEY}
    restart: unless-stopped
```

创建 `.env` 文件并启动：

```bash
docker-compose up -d
```

## 使用示例

### 使用 curl

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-key" \
  -d '{
    "model": "notebooklm",
    "messages": [
      {"role": "user", "content": "What are the key themes?"}
    ]
  }'
```

### 使用 Python OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="your-secret-key",
    base_url="http://your-vps-ip:8000/v1"
)

response = client.chat.completions.create(
    model="notebooklm",
    messages=[
        {"role": "user", "content": "What are the key themes?"}
    ]
)

print(response.choices[0].message.content)
```

### 流式响应

```python
response = client.chat.completions.create(
    model="notebooklm",
    messages=[
        {"role": "user", "content": "What are the key themes?"}
    ],
    stream=True
)

for chunk in response:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="")
```

### 指定不同的 Notebook

```python
response = client.chat.completions.create(
    model="notebooklm",
    messages=[
        {"role": "user", "content": "What are the key themes?"}
    ],
    extra_body={"notebook_id": "another-notebook-id"}
)
```

## API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/v1/models` | GET | 列出可用模型 |
| `/v1/chat/completions` | POST | 聊天完成（OpenAI 兼容） |

## 环境变量

| 变量名 | 必需 | 说明 | 默认值 |
|--------|------|------|--------|
| `NOTEBOOKLM_AUTH_JSON` | 是* | Playwright 存储状态 JSON | - |
| `NOTEBOOKLM_NOTEBOOK_ID` | 否** | 默认 notebook ID | - |
| `API_KEY` | 否 | API 密钥 | 空（无认证） |
| `PORT` | 否 | 服务器端口 | 8000 |
| `HOST` | 否 | 服务器主机 | 0.0.0.0 |

\* 如果挂载了认证文件，则不需要  
\*\* 如果不设置，每个请求必须提供 `notebook_id`

## 文档

- [VPS 部署指南](VPS_DEPLOYMENT.md) - 详细的 VPS 部署和认证说明
- [原项目文档](https://github.com/teng-lin/notebooklm-py) - NotebookLM-py 完整文档

## 开发

### 本地运行

```bash
# 克隆仓库
git clone https://github.com/samuncleorange/notebooklm2api.git
cd notebooklm2api

# 安装依赖
pip install -e ".[browser]"

# 设置环境变量
export NOTEBOOKLM_AUTH_JSON='{"cookies":[...]}'
export NOTEBOOKLM_NOTEBOOK_ID='your-notebook-id'

# 运行服务器
python api_server.py
```

### 构建 Docker 镜像

```bash
docker build -t notebooklm2api .
```

## 自动构建

项目配置了 GitHub Actions，每次推送到 main 分支时会自动构建并推送 Docker 镜像到 GitHub Container Registry。

镜像标签：
- `latest` - 最新的 main 分支构建
- `main-<sha>` - 特定提交的构建
- `v*` - 版本标签

## 故障排除

### 认证失败

重新在本地运行 `notebooklm login` 并更新 `NOTEBOOKLM_AUTH_JSON`。

### Notebook ID 无效

确保设置了 `NOTEBOOKLM_NOTEBOOK_ID` 或在请求中提供 `notebook_id`。

### 查看日志

```bash
docker logs notebooklm-api
```

更多故障排除信息，请参阅 [VPS_DEPLOYMENT.md](VPS_DEPLOYMENT.md)。

## 安全建议

1. 使用 `API_KEY` 保护你的 API
2. 在生产环境使用 HTTPS（通过 Nginx 等反向代理）
3. 定期更新认证信息（Google cookies 会过期）
4. 限制 API 访问（使用防火墙）

## 致谢

- 原项目：[notebooklm-py](https://github.com/teng-lin/notebooklm-py) by Teng Lin
- 感谢 Google Antigravity 团队

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 贡献

欢迎提交 Issue 和 Pull Request！

## 更新日志

### v1.0.0 (2026-02-01)

- ✨ 添加 OpenAI 兼容 API 服务器
- 🐳 添加 Docker 支持
- 🚀 添加 GitHub Actions 自动构建
- 📝 添加 VPS 部署文档
- 🔐 支持无浏览器环境认证
