#!/bin/bash
#
# Zealot SSO 版本部署脚本
# 用于将 Zealot 部署到远程服务器
#
# 使用方式:
#   ./deploy.sh                      # 交互式
#   ./deploy.sh --host 192.168.1.100 --user admin
#

set -e

# 配置
IMAGE_NAME="zealot-zealot"
IMAGE_TAG="latest"
CONTAINER_NAME="zealot-zealot-1"
REMOTE_DIR="/opt/zealot-deploy"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_USER="${REMOTE_USER:-}"
REMOTE_SSH_PORT="${REMOTE_SSH_PORT:-22}"
REMOTE_SSH_KEY="${REMOTE_SSH_KEY:-}"

# Docker 网络配置
DOCKER_NETWORK="zealot_default"
DOCKER_PORT_MAPPING="3063:3061"

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
  --host HOST           服务器 IP 或主机名 (必填)
  --user USER           SSH 用户名 (必填)
  --ssh-port PORT       SSH 端口，默认: 22
  --ssh-key KEY         SSH 私钥路径
  --image-name NAME     Docker 镜像名，默认: zealot-zealot
  --container-name NAME 容器名，默认: zealot-zealot-1
  --network NAME        Docker 网络，默认: zealot_default
  --port-mapping MAP    端口映射，默认: 3063:3061
  --skip-build          跳过构建，直接部署已有镜像
  -h, --help            显示帮助

示例:
  ./deploy.sh --host 192.168.1.100 --user admin
  ./deploy.sh --host 192.168.1.100 --user admin --ssh-key ~/.ssh/id_rsa
  ./deploy.sh --host example.com --user ubuntu --ssh-key ~/.ssh/id_rsa --skip-build

EOF
}

# 解析参数
SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --host) REMOTE_HOST="$2"; shift 2 ;;
    --user) REMOTE_USER="$2"; shift 2 ;;
    --ssh-port) REMOTE_SSH_PORT="$2"; shift 2 ;;
    --ssh-key) REMOTE_SSH_KEY="$2"; shift 2 ;;
    --image-name) IMAGE_NAME="$2"; shift 2 ;;
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    --network) DOCKER_NETWORK="$2"; shift 2 ;;
    --port-mapping) DOCKER_PORT_MAPPING="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) log_error "未知参数: $1"; show_help; exit 1 ;;
  esac
done

# 检查必填参数
if [[ -z "$REMOTE_HOST" ]] || [[ -z "$REMOTE_USER" ]]; then
  log_error "缺少必填参数: --host 和 --user"
  show_help
  exit 1
fi

# 构建 SSH 命令
SSH_CMD="ssh -p ${REMOTE_SSH_PORT}"
if [[ -n "$REMOTE_SSH_KEY" ]]; then
  SSH_CMD="$SSH_CMD -i $REMOTE_SSH_KEY"
fi
SCP_CMD="scp -P ${REMOTE_SSH_PORT}"
if [[ -n "$REMOTE_SSH_KEY" ]]; then
  SCP_CMD="$SCP_CMD -i $REMOTE_SSH_KEY"
fi

REMOTE="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_IMAGE_PATH="${REMOTE_DIR}/${IMAGE_NAME}.tar"

log_info "=== Zealot SSO 部署开始 ==="
log_info "目标服务器: ${REMOTE}"
log_info "容器名: ${CONTAINER_NAME}"
log_info "Docker 网络: ${DOCKER_NETWORK}"

# ========== 步骤 1: 构建 Docker 镜像 ==========
if [[ "$SKIP_BUILD" == "false" ]]; then
  log_info "步骤 1/4: 构建 Docker 镜像..."

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

# ========== 步骤 3: 传输文件到服务器 ==========
log_info "步骤 3/4: 传输文件到服务器..."

$SSH_CMD ${REMOTE} "mkdir -p ${REMOTE_DIR}"

if [[ "$SKIP_BUILD" == "false" ]]; then
  log_info "  传输镜像文件 (~300MB，可能需要几分钟)..."
  $SCP_CMD /tmp/${IMAGE_NAME}.tar ${REMOTE}:${REMOTE_IMAGE_PATH}
  rm -f /tmp/${IMAGE_NAME}.tar
fi

log_info "文件传输完成"

# ========== 步骤 4: 在服务器上部署 ==========
log_info "步骤 4/4: 在服务器上部署..."

$SSH_CMD ${REMOTE} << 'REMOTE_EOF'
set -e

IMAGE_NAME="${IMAGE_NAME:-zealot-zealot}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-zealot-zealot-1}"
REMOTE_DIR="${REMOTE_DIR:-/opt/zealot-deploy}"
REMOTE_IMAGE_PATH="${REMOTE_DIR}/${IMAGE_NAME}.tar"
DOCKER_NETWORK="${DOCKER_NETWORK:-zealot_default}"
DOCKER_PORT_MAPPING="${DOCKER_PORT_MAPPING:-3063:3061}"

echo "[INFO] 停止并删除旧容器..."
docker stop ${CONTAINER_NAME} 2>/dev/null || true
docker rm ${CONTAINER_NAME} 2>/dev/null || true

if [[ -f "${REMOTE_IMAGE_PATH}" ]]; then
  echo "[INFO] 加载新镜像..."
  docker load -i ${REMOTE_IMAGE_PATH}
fi

echo "[INFO] 启动新容器..."
docker run -d \
  --name ${CONTAINER_NAME} \
  --restart unless-stopped \
  --network ${DOCKER_NETWORK} \
  -p ${DOCKER_PORT_MAPPING} \
  -e BIND_ON=0.0.0.0:3063 \
  -e ZEALOT_STANDARD_LOGIN_ENABLED=false \
  ${IMAGE_NAME}:${IMAGE_TAG}

echo "[INFO] 等待启动..."
sleep 10

# 检查容器状态
if docker ps | grep -q ${CONTAINER_NAME}; then
  echo "[INFO] 容器启动成功!"
  echo "[INFO] 访问 http://$(hostname -I | awk '{print $1}'):3063"
  echo "[INFO] 容器日志: docker logs ${CONTAINER_NAME}"
else
  echo "[ERROR] 容器启动失败，查看日志:"
  docker logs ${CONTAINER_NAME}
  exit 1
fi
REMOTE_EOF

log_info "=== 部署完成 ==="
log_info ""
log_info "访问 http://${REMOTE_HOST}:3063 验证"
