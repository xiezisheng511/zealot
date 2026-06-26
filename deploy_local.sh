#!/bin/bash
#
# Zealot SSO 本地 Docker 部署脚本
#

set -e

cd "$(dirname "$0")"

echo "=== Zealot SSO 本地部署 ==="

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "Error: Docker 未安装"
    exit 1
fi

if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "Error: Docker Compose 未安装"
    exit 1
fi

DOCKER_COMPOSE="docker compose"
if ! docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
fi

echo "1/4: 构建镜像..."
$DOCKER_COMPOSE build

echo "2/4: 启动服务 (PostgreSQL + Redis + Zealot)..."
$DOCKER_COMPOSE up -d

echo "3/4: 等待数据库就绪..."
sleep 10

echo "4/4: 初始化数据库..."
$DOCKER_COMPOSE exec -T zealot bundle exec rails db:prepare 2>/dev/null || \
$DOCKER_COMPOSE exec -T zealot bundle exec rails db:migrate

echo ""
echo "=== 部署完成 ==="
echo ""
echo "访问地址: http://localhost:3000"
echo ""
echo "SSO 回调地址: POST http://localhost:3000/users/auth/sso/callback?token=<token>"
echo ""
echo "常用命令:"
echo "  查看日志: $DOCKER_COMPOSE logs -f zealot"
echo "  停止服务: $DOCKER_COMPOSE down"
echo "  重启服务: $DOCKER_COMPOSE restart zealot"
