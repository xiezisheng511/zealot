# Zealot 本地开发部署

基于 [Zealot](https://github.com/tryzealot/zealot) 的本地部署版本，集成 SSO 登录功能。

## 部署方式

### Docker Compose 部署

```bash
# 构建并启动
docker compose build --build-arg REPLACE_CHINA_MIRROR=false
docker compose up -d

# 查看日志
docker compose logs -f zealot

# 停止服务
docker compose down
```

### 访问地址

- 本地访问：http://127.0.0.1:3063
- 初始账号：admin@zealot.com
- 初始密码：zealot123

## SSO 登录配置

### 回调地址

```
GET http://127.0.0.1:3063/users/auth/sso/auth?access_token=你的token&region=区域
```

### 环境变量

在 `docker-compose.yml` 中配置：

```yaml
environment:
  - SSO_BASE_URL=https://api-unify.seerq.io  # SSO 接口地址
```

### 后端接口要求

Zealot 会调用以下接口获取用户信息：

```
GET {SSO_BASE_URL}/api/auths/{access_token}?backend_id=178246419580930726
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

在 `config/initializers/devise.rb` 中修改：

```ruby
config.timeout_in = 3.hours  # 3小时超时
```

测试环境可设置为：

```ruby
config.timeout_in = 3.minutes  # 3分钟超时
```

修改后需要重新构建镜像：

```bash
docker compose build --build-arg REPLACE_CHINA_MIRROR=false --no-cache zealot
docker compose up -d
```

## 主要修改

1. **SSO 回调接口**：`/users/auth/sso/auth`（支持 GET 请求）
2. **access_token 参数**：替代原来的 token 参数
3. **backend_id 参数**：自动添加到 SSO 请求中
4. **Session 超时**：可配置的无操作超时时间
5. **移除赞助按钮**：导航栏已移除"支持 Zealot"按钮

## 推送到 GitHub

```bash
git add -A
git commit -m "描述"
git remote set-url origin https://ghp_你的TOKEN@github.com/xiezisheng511/zealot.git
git push -u origin main
```