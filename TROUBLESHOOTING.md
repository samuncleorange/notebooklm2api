# VPS 部署快速修复指南

## 问题：镜像拉取被拒绝

如果遇到 `denied` 错误，说明 GitHub Actions 还在构建或镜像权限问题。

## 解决方案

### 方案 1：本地构建（立即可用）

```bash
# 在 VPS 上操作
cd /root/notebooklm-api

# 本地构建镜像
docker build -t notebooklm2api:local .

# 使用本地镜像启动
docker compose up -d
```

### 方案 2：等待 GitHub Actions 完成

1. 访问 https://github.com/samuncleorange/notebooklm2api/actions
2. 等待构建完成（约 5-10 分钟）
3. 修改 `docker-compose.yml`：

```yaml
services:
  notebooklm-api:
    image: ghcr.io/samuncleorange/notebooklm2api:latest  # 使用远程镜像
    # 注释掉 build 行
    # build: .
```

4. 重新启动：
```bash
docker compose pull
docker compose up -d
```

## 问题：环境变量警告

### 原因
Docker Compose 把 JSON 中的 `$` 符号当成了变量（如 `$o1`, `$g1`）。

### 解决方法 1：使用 env_file（推荐）

修改 `docker-compose.yml`：

```yaml
services:
  notebooklm-api:
    # ... 其他配置 ...
    env_file:
      - .env
    # 删除 environment 部分
```

然后在 `.env` 文件中直接写（不需要引号）：

```bash
NOTEBOOKLM_AUTH_JSON={"cookies":[...]}
NOTEBOOKLM_NOTEBOOK_ID=abc123
API_KEY=my-key
```

### 解决方法 2：转义 $ 符号

在 `.env` 文件中，把所有 `$` 改成 `$$`：

```bash
# 原来的 JSON
{"cookies":[{"name":"__Secure-1PSID","value":"g.a000..."}]}

# 改成（所有 $ 变成 $$）
{"cookies":[{"name":"__Secure-1PSID","value":"g.a000..."}]}
# 如果有 $ 符号，写成 $$
```

### 解决方法 3：使用 Docker Run

不使用 Docker Compose，直接用 Docker Run：

```bash
# 读取 .env 文件
source .env

# 运行容器
docker run -d \
  --name notebooklm-api \
  -p 8000:8000 \
  -e NOTEBOOKLM_AUTH_JSON="$NOTEBOOKLM_AUTH_JSON" \
  -e NOTEBOOKLM_NOTEBOOK_ID="$NOTEBOOKLM_NOTEBOOK_ID" \
  -e API_KEY="$API_KEY" \
  --restart unless-stopped \
  notebooklm2api:local
```

## 完整操作步骤（推荐）

### 步骤 1：准备代码

```bash
cd /root
git clone https://github.com/samuncleorange/notebooklm2api.git notebooklm-api
cd notebooklm-api
```

### 步骤 2：创建 .env 文件

```bash
cat > .env << 'EOF'
NOTEBOOKLM_AUTH_JSON={"cookies":[你的认证JSON]}
NOTEBOOKLM_NOTEBOOK_ID=你的notebook_id
API_KEY=你的api密钥
PORT=8000
EOF
```

### 步骤 3：本地构建

```bash
docker build -t notebooklm2api:local .
```

### 步骤 4：启动服务

```bash
docker compose up -d
```

### 步骤 5：查看日志

```bash
docker compose logs -f
```

### 步骤 6：测试

```bash
curl http://localhost:8000/health
```

## 常见问题

### Q: 构建很慢怎么办？
A: 第一次构建需要下载依赖，约 5-10 分钟。后续会使用缓存。

### Q: 如何更新镜像？
A: 
```bash
git pull
docker build -t notebooklm2api:local .
docker compose up -d --force-recreate
```

### Q: 如何查看详细错误？
A:
```bash
docker compose logs notebooklm-api
```

### Q: 如何重启服务？
A:
```bash
docker compose restart
```

### Q: 如何停止服务？
A:
```bash
docker compose down
```

## 验证部署成功

```bash
# 1. 健康检查
curl http://localhost:8000/health

# 2. 列出模型
curl http://localhost:8000/v1/models -H "Authorization: Bearer your-api-key"

# 3. 测试聊天
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{"model":"notebooklm","messages":[{"role":"user","content":"Hello"}]}'
```

如果以上都正常，说明部署成功！
