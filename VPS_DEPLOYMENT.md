# NotebookLM2API - VPS Deployment Guide

这个文档说明如何在VPS上部署NotebookLM API服务，包括无浏览器环境下的认证方法。

## 目录

1. [认证方法](#认证方法)
2. [Docker部署](#docker部署)
3. [使用示例](#使用示例)
4. [故障排除](#故障排除)

## 认证方法

由于VPS通常没有图形界面和浏览器，我们需要在本地完成认证，然后将认证信息传输到VPS。

### 方法1：本地认证后导出JSON（推荐）

#### 步骤1：在本地机器上安装并认证

```bash
# 安装notebooklm-py（带浏览器支持）
pip install "notebooklm-py[browser]"
playwright install chromium

# 登录（会打开浏览器）
notebooklm login

# 认证文件保存在 ~/.notebooklm/storage_state.json
```

#### 步骤2：导出认证JSON

```bash
# 读取认证文件并压缩为单行JSON
cat ~/.notebooklm/storage_state.json | jq -c '.'
```

复制输出的JSON字符串，这就是你的认证信息。

#### 步骤3：在VPS上设置环境变量

```bash
# 将认证JSON设置为环境变量
export NOTEBOOKLM_AUTH_JSON='{"cookies":[...]}'  # 粘贴步骤2的JSON

# 设置默认notebook ID（可选）
export NOTEBOOKLM_NOTEBOOK_ID='your-notebook-id'

# 设置API密钥（可选，用于保护API）
export API_KEY='your-secret-api-key'
```

### 方法2：直接复制认证文件

如果你有VPS的文件访问权限：

```bash
# 在本地
scp ~/.notebooklm/storage_state.json user@your-vps:/root/.notebooklm/

# 在VPS上
chmod 600 /root/.notebooklm/storage_state.json
```

## Docker部署

### 构建镜像

项目已配置GitHub Actions自动构建。每次推送到main分支时，会自动构建并推送镜像到GitHub Container Registry。

手动构建：

```bash
docker build -t notebooklm2api .
```

### 从GitHub Container Registry拉取

```bash
# 拉取最新镜像
docker pull ghcr.io/samuncleorange/notebooklm2api:latest
```

### 运行容器

#### 使用环境变量（推荐）

```bash
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  -e NOTEBOOKLM_AUTH_JSON='{"cookies":[...]}' \
  -e NOTEBOOKLM_NOTEBOOK_ID='your-notebook-id' \
  -e API_KEY='your-secret-key' \
  --restart unless-stopped \
  ghcr.io/samuncleorange/notebooklm2api:latest
```

#### 使用认证文件挂载

```bash
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  -v /root/.notebooklm:/root/.notebooklm:ro \
  -e NOTEBOOKLM_NOTEBOOK_ID='your-notebook-id' \
  -e API_KEY='your-secret-key' \
  --restart unless-stopped \
  ghcr.io/samuncleorange/notebooklm2api:latest
```

### 使用Docker Compose

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
      - PORT=8000
      - HOST=0.0.0.0
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python", "-c", "import httpx; httpx.get('http://localhost:8000/health', timeout=5.0)"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
```

创建 `.env` 文件：

```bash
NOTEBOOKLM_AUTH_JSON={"cookies":[...]}
NOTEBOOKLM_NOTEBOOK_ID=your-notebook-id
API_KEY=your-secret-key
```

启动：

```bash
docker-compose up -d
```

## 使用示例

### 健康检查

```bash
curl http://localhost:8000/health
```

### 列出模型

```bash
curl http://localhost:8000/v1/models \
  -H "Authorization: Bearer your-secret-key"
```

### OpenAI兼容的聊天完成

#### 非流式请求

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

#### 流式请求

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-key" \
  -d '{
    "model": "notebooklm",
    "messages": [
      {"role": "user", "content": "What are the key themes?"}
    ],
    "stream": true
  }'
```

#### 指定notebook ID

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-key" \
  -d '{
    "model": "notebooklm",
    "messages": [
      {"role": "user", "content": "What are the key themes?"}
    ],
    "notebook_id": "specific-notebook-id"
  }'
```

### 使用Python OpenAI SDK

```python
from openai import OpenAI

# 配置客户端
client = OpenAI(
    api_key="your-secret-key",
    base_url="http://your-vps-ip:8000/v1"
)

# 发送请求
response = client.chat.completions.create(
    model="notebooklm",
    messages=[
        {"role": "user", "content": "What are the key themes?"}
    ]
)

print(response.choices[0].message.content)
```

### 使用curl模拟OpenAI API

```python
import requests

url = "http://your-vps-ip:8000/v1/chat/completions"
headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer your-secret-key"
}
data = {
    "model": "notebooklm",
    "messages": [
        {"role": "user", "content": "What are the key themes?"}
    ]
}

response = requests.post(url, json=data, headers=headers)
print(response.json())
```

## 环境变量说明

| 变量名 | 必需 | 说明 | 默认值 |
|--------|------|------|--------|
| `NOTEBOOKLM_AUTH_JSON` | 是* | Playwright存储状态JSON | - |
| `NOTEBOOKLM_NOTEBOOK_ID` | 否** | 默认notebook ID | - |
| `API_KEY` | 否 | API密钥（用于保护API） | 空（无认证） |
| `PORT` | 否 | 服务器端口 | 8000 |
| `HOST` | 否 | 服务器主机 | 0.0.0.0 |

\* 如果挂载了认证文件到 `/root/.notebooklm/storage_state.json`，则不需要  
\*\* 如果不设置，每个请求必须提供 `notebook_id` 参数

## 获取Notebook ID

### 方法1：使用CLI

```bash
# 在本地机器上
notebooklm list

# 输出会显示所有notebook的ID和标题
```

### 方法2：从URL获取

访问 https://notebooklm.google.com/，打开你的notebook，URL中的ID就是notebook ID：

```
https://notebooklm.google.com/notebook/abc123xyz
                                         ^^^^^^^^^
                                      这就是notebook ID
```

## 故障排除

### 认证失败

**错误**: `Authentication failed: Missing required cookies: {'SID'}`

**解决方案**:
1. 确认 `NOTEBOOKLM_AUTH_JSON` 包含完整的cookies数组
2. 重新在本地运行 `notebooklm login`
3. 检查JSON格式是否正确（使用 `jq` 验证）

```bash
# 验证JSON格式
echo $NOTEBOOKLM_AUTH_JSON | jq .
```

### 认证过期

**错误**: `Authentication expired or invalid`

**解决方案**:
1. Google的认证cookies会过期
2. 在本地重新运行 `notebooklm login`
3. 更新VPS上的 `NOTEBOOKLM_AUTH_JSON`

### Notebook ID无效

**错误**: `notebook_id is required`

**解决方案**:
1. 设置 `NOTEBOOKLM_NOTEBOOK_ID` 环境变量，或
2. 在每个请求中提供 `notebook_id` 参数

### 容器无法启动

**检查日志**:

```bash
docker logs notebooklm-api
```

**常见问题**:
1. 端口8000已被占用 → 修改 `-p` 参数
2. 环境变量未设置 → 检查 `-e` 参数
3. 认证JSON格式错误 → 验证JSON格式

### 健康检查失败

```bash
# 检查容器状态
docker ps -a

# 查看详细日志
docker logs notebooklm-api --tail 100

# 进入容器调试
docker exec -it notebooklm-api /bin/bash
```

## 安全建议

1. **使用API密钥**: 设置 `API_KEY` 环境变量保护你的API
2. **使用HTTPS**: 在生产环境中使用反向代理（如Nginx）配置HTTPS
3. **限制访问**: 使用防火墙限制API访问
4. **定期更新认证**: Google cookies会过期，建议定期更新

### Nginx反向代理示例

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
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 更新镜像

```bash
# 拉取最新镜像
docker pull ghcr.io/samuncleorange/notebooklm2api:latest

# 停止并删除旧容器
docker stop notebooklm-api
docker rm notebooklm-api

# 使用新镜像启动
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  -e NOTEBOOKLM_AUTH_JSON='{"cookies":[...]}' \
  -e NOTEBOOKLM_NOTEBOOK_ID='your-notebook-id' \
  -e API_KEY='your-secret-key' \
  --restart unless-stopped \
  ghcr.io/samuncleorange/notebooklm2api:latest
```

## 监控和日志

### 查看实时日志

```bash
docker logs -f notebooklm-api
```

### 查看最近日志

```bash
docker logs --tail 100 notebooklm-api
```

### 导出日志

```bash
docker logs notebooklm-api > notebooklm-api.log 2>&1
```

## 性能优化

1. **使用持久化存储**: 挂载 `/root/.notebooklm` 避免每次重启重新认证
2. **资源限制**: 使用Docker资源限制避免内存泄漏

```bash
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  --memory="512m" \
  --cpus="1.0" \
  -e NOTEBOOKLM_AUTH_JSON='{"cookies":[...]}' \
  ghcr.io/samuncleorange/notebooklm2api:latest
```

## 支持

如有问题，请在GitHub仓库提交Issue：
https://github.com/samuncleorange/notebooklm2api/issues
