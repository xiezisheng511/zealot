#!/bin/bash
#
# Zealot SSO 版本部署脚本
# 用于将修改后的 Zealot 部署到 NAS
#
# 使用方式:
#   ./deploy.sh                      # 交互式
#   ./deploy.sh --nas-host 192.168.1.100 --nas-user admin
#

set -e

# 配置
IMAGE_NAME="zealot-sso"
IMAGE_TAG="latest"
CONTAINER_NAME="zealot"
NAS_HOST="${NAS_HOST:-}"
NAS_USER="${NAS_USER:-}"
NAS_SSH_PORT="${NAS_SSH_PORT:-22}"
NAS_SSH_KEY="${NAS_SSH_KEY:-}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 帮助
show_help() {
  cat << EOF
Zealot SSO 部署脚本

用法: ./deploy.sh [选项]

选项:
  --nas-host HOST       NAS 的 IP 地址或主机名 (必填)
  --nas-user USER       SSH 用户名 (必填)
  --nas-ssh-port PORT   SSH 端口，默认: 22
  --nas-ssh-key KEY     SSH 私钥路径
  --image-name NAME     Docker 镜像名，默认: zealot-sso
  --container-name NAME 容器名，默认: zealot
  --skip-build          跳过构建，直接部署已有镜像
  -h, --help            显示帮助

示例:
  ./deploy.sh --nas-host 192.168.1.100 --nas-user admin
  ./deploy.sh --nas-host 192.168.1.100 --nas-user admin --nas-ssh-key ~/.ssh/id_rsa

环境变量:
  SSO_BASE_URL  必填。灵盾 API 地址:
    国内: https://api-unify.lingjiptai.com
    新加坡: https://api-unify.seerq.io

EOF
}

# 解析参数
SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --nas-host) NAS_HOST="$2"; shift 2 ;;
    --nas-user) NAS_USER="$2"; shift 2 ;;
    --nas-ssh-port) NAS_SSH_PORT="$2"; shift 2 ;;
    --nas-ssh-key) NAS_SSH_KEY="$2"; shift 2 ;;
    --image-name) IMAGE_NAME="$2"; shift 2 ;;
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) log_error "未知参数: $1"; show_help; exit 1 ;;
  esac
done

# 检查必填参数
if [[ -z "$NAS_HOST" ]] || [[ -z "$NAS_USER" ]]; then
  log_error "缺少必填参数: --nas-host 和 --nas-user"
  show_help
  exit 1
fi

# 构建 SSH 命令
SSH_CMD="ssh -p ${NAS_SSH_PORT}"
if [[ -n "$NAS_SSH_KEY" ]]; then
  SSH_CMD="$SSH_CMD -i $NAS_SSH_KEY"
fi
SCP_CMD="scp -P ${NAS_SSH_PORT}"
if [[ -n "$NAS_SSH_KEY" ]]; then
  SCP_CMD="$SCP_CMD -i $NAS_SSH_KEY"
fi

REMOTE="${NAS_USER}@${NAS_HOST}"

# 准备远程目录
REMOTE_DIR="/opt/zealot-deploy"
REMOTE_IMAGE_PATH="${REMOTE_DIR}/${IMAGE_NAME}.tar"
REMOTE_ENV_FILE="${REMOTE_DIR}/.env"

log_info "=== Zealot SSO 部署开始 ==="
log_info "NAS: ${REMOTE}"
log_info "容器名: ${CONTAINER_NAME}"

# ========== 步骤 1: 构建 Docker 镜像 ==========
if [[ "$SKIP_BUILD" == "false" ]]; then
  log_info "步骤 1/4: 构建 Docker 镜像..."

  # 检查 Dockerfile 是否存在
  if [[ ! -f "Dockerfile" ]]; then
    log_error "Dockerfile 不存在!"
    exit 1
  fi

  docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
  log_info "镜像构建完成: ${IMAGE_NAME}:${IMAGE_TAG}"
else
  log_info "步骤 1/4: 跳过构建 (--skip-build)"
fi

# ========== 步骤 2: 保存镜像为 tar ==========
if [[ "$SKIP_BUILD" == "false" ]]; then
  log_info "步骤 2/4: 保存镜像为 tar 文件..."
  docker save -o /tmp/${IMAGE_NAME}.tar ${IMAGE_NAME}:${IMAGE_TAG}
  log_info "镜像已保存到: /tmp/${IMAGE_NAME}.tar"
else
  log_info "步骤 2/4: 跳过构建 (使用已有镜像)"
fi

# ========== 步骤 3: 传输文件到 NAS ==========
log_info "步骤 3/4: 传输文件到 NAS..."

# 创建远程目录
$SSH_CMD ${REMOTE} "mkdir -p ${REMOTE_DIR}"

# 传输镜像
if [[ "$SKIP_BUILD" == "false" ]]; then
  log_info "  传输镜像文件 (~300MB，可能需要几分钟)..."
  $SCP_CMD /tmp/${IMAGE_NAME}.tar ${REMOTE}:${REMOTE_IMAGE_PATH}
  rm -f /tmp/${IMAGE_NAME}.tar
fi

# 创建 env 文件
cat > /tmp/zealot.env << 'ENVEOF'
# Zealot 环境配置
RAILS_ENV=production
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/zealot
REDIS_URL=redis://localhost:6379/0

# ========== SSO 配置 (必填) ==========
# 灵盾 API 地址，根据你的业务选择:
#   国内: https://api-unify.lingjiptai.com
#   新加坡: https://api-unify.seerq.io
SSO_BASE_URL=https://api-unify.lingjiptai.com

# 可选配置
# ZEALOT_USE_HTTPS=true
# ZEALOT_PORT=3000
ENVEOF
$SCP_CMD /tmp/zealot.env ${REMOTE}:${REMOTE_ENV_FILE}
rm -f /tmp/zealot.env

log_info "文件传输完成"

# ========== 步骤 4: 在 NAS 上部署 ==========
log_info "步骤 4/4: 在 NAS 上部署..."

$SSH_CMD ${REMOTE} << 'REMOTE_EOF'
set -e

IMAGE_NAME="zealot-sso"
IMAGE_TAG="latest"
CONTAINER_NAME="zealot"
REMOTE_DIR="/opt/zealot-deploy"
REMOTE_IMAGE_PATH="${REMOTE_DIR}/${IMAGE_NAME}.tar"
REMOTE_ENV_FILE="${REMOTE_DIR}/.env"

echo "[INFO] 停止并删除旧容器..."
docker stop ${CONTAINER_NAME} 2>/dev/null || true
docker rm ${CONTAINER_NAME} 2>/dev/null || true

echo "[INFO] 加载新镜像..."
docker load -i ${REMOTE_IMAGE_PATH}

echo "[INFO] 启动新容器..."
docker run -d \
  --name ${CONTAINER_NAME} \
  --restart unless-stopped \
  --env-file ${REMOTE_ENV_FILE} \
  -p 3000:3000 \
  -v zealot_data:/app/data \
  ${IMAGE_NAME}:${IMAGE_TAG}

echo "[INFO] 等待启动..."
sleep 5

# 检查容器状态
if docker ps | grep -q ${CONTAINER_NAME}; then
  echo "[INFO] 容器启动成功!"
  echo "[INFO] 访问 http://$(hostname -I | awk '{print $1}'):3000"
else
  echo "[ERROR] 容器启动失败，查看日志:"
  docker logs ${CONTAINER_NAME}
  exit 1
fi
REMOTE_EOF

log_info "=== 部署完成 ==="
log_info ""
log_info "下一步操作:"
log_info "1. SSH 到 NAS: ssh ${NAS_USER}@${NAS_HOST}"
log_info "2. 编辑配置文件: vim ${REMOTE_ENV_FILE}"
log_info "3. 确认 SSO_BASE_URL 配置正确"
log_info "4. 重启容器: docker restart ${CONTAINER_NAME}"
log_info ""
log_info "从你的后台跳转到 Zealot 的链接格式:"
log_info "POST https://你的zealot域名/users/auth/sso/callback?token=<灵盾token>"
log_info ""
log_info "灵盾 token 有效期只有 10 秒，请在生成后立即跳转!"
