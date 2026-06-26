# Zealot 本地开发部署

基于 [Zealot](https://github.com/tryzealot/zealot) 的本地部署版本，集成 SSO 登录功能。

## 快速开始

### 1. 配置文件

复制环境变量配置文件：

```bash
cp .env.example .env
```

然后编辑 `.env` 文件，填入你的配置值。

### 2. Docker Compose 部署

```bash
# 构建并启动
docker compose build --build-arg REPLACE_CHINA_MIRROR=false
docker compose up -d

# 查看日志
docker compose logs -f zealot

# 停止服务
docker compose down
```

### 3. 访问地址

- 本地访问：http://127.0.0.1:3063
- 初始账号：admin@zealot.com
- 初始密码：zealot123

## 配置说明

### 环境变量 (.env)

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `SECRET_KEY_BASE` | Rails 密钥 | 随机字符串 |
| `ZEALOT_DATABASE_URL` | 数据库连接 | `postgresql://postgres:password@db:5432/zealot` |
| `REDIS_URL` | Redis 连接 | `redis://redis:6379/0` |
| `BIND_ON` | 服务端口 | `0.0.0.0:3063` |
| `SSO_BASE_URL` | SSO 接口地址 | `https://api-unify.seerq.io` |
| `SSO_BACKEND_ID` | SSO 后端 ID | `178246419580930726` |
| `POSTGRES_PASSWORD` | 数据库密码 | `your_password` |
| `SESSION_TIMEOUT` | Session 超时(分钟) | `180` |

## SSO 登录配置

### 回调地址

```
GET http://127.0.0.1:3063/users/auth/sso/auth?access_token=你的token&region=区域
```

### 后端接口要求

Zealot 会调用以下接口获取用户信息：

```
GET {SSO_BASE_URL}/api/auths/{access_token}?backend_id={SSO_BACKEND_ID}
```

接口返回格式：

```json
{
  "user_id": "12345",
  "user": {
    "account": "用户名",
    "realname": "姓名",
    "email": "邮箱@example.com",
    "avatar": "https://example.com/avatar.png"
  }
}
```

## Session 超时配置

在 `.env` 中修改：

```bash
SESSION_TIMEOUT=180  # 3小时
```

或修改 `config/initializers/devise.rb`：

```ruby
config.timeout_in = 3.hours
```

修改后需要重新构建：

```bash
docker compose build --build-arg REPLACE_CHINA_MIRROR=false --no-cache zealot
docker compose up -d
```

## 主要修改

1. **SSO 回调接口**：`/users/auth/sso/auth`（支持 GET 请求）
2. **access_token 参数**：替代原来的 token 参数
3. **backend_id 参数**：从环境变量读取
4. **Session 超时**：可配置的无操作超时时间
5. **移除赞助按钮**：导航栏已移除"支持 Zealot"按钮
6. **环境变量配置**：敏感信息通过 `.env` 文件管理

## 推送到 GitHub

```bash
git add -A
git commit -m "描述"
git remote set-url origin https://ghp_你的TOKEN@github.com/xiezisheng511/zealot.git
git push -u origin main
```

## 目录结构

```
├── .env.example      # 环境变量模板
├── .env              # 环境变量（不提交）
├── docker-compose.yml
├── Dockerfile
├── config/
│   └── initializers/
│       └── devise.rb  # Session 超时配置
└── app/
    └── controllers/
        └── users/
            └── sso_callbacks_controller.rb  # SSO 回调处理
```