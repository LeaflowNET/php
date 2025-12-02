#!/bin/bash

# 多架构 Docker 镜像构建脚本
# 使用方法: ./build.sh [仓库地址] [镜像标签] [额外构建参数]
# 示例1: ./build.sh myrepo/app 1.0.0
# 示例2: ./build.sh myrepo/app 1.0.0 --no-cache --build-arg ENV=production

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
  echo -e "${YELLOW}多架构 Docker 镜像构建脚本${NC}"
  echo -e "用法: $0 [仓库地址] [镜像标签] [额外构建参数]"
  echo -e "示例:"
  echo -e "  ${GREEN}$0 myrepo/app 1.0.0${NC}          # 构建并推送 myrepo/app:1.0.0"
  echo -e "  ${GREEN}$0 myrepo/app latest --no-cache${NC} # 带额外构建参数"
  echo -e "\n选项:"
  echo -e "  ${YELLOW}--help${NC}    显示帮助信息"
  exit 0
}

# 检查帮助参数
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  show_help
fi

# 检查参数
if [ -z "$2" ]; then
  echo -e "${RED}错误: 参数不足${NC}"
  show_help
  exit 1
fi

REPO=$1
TAG=$2
shift 2
BUILD_ARGS=$@
IMAGE="${REPO}:${TAG}"

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}错误: Docker 守护进程未运行${NC}"
  exit 1
fi

# 初始化 buildx 环境
init_buildx() {
  if ! docker buildx version &> /dev/null; then
    echo -e "${YELLOW}警告: docker buildx 不可用，尝试启用实验性功能...${NC}"
    export DOCKER_CLI_EXPERIMENTAL=enabled
  fi

  BUILDER_NAME="multiarch_builder_$(date +%s)"
  if ! docker buildx inspect $BUILDER_NAME &> /dev/null; then
    echo -e "${GREEN}正在初始化多架构构建环境...${NC}"
    docker run --privileged --rm tonistiigi/binfmt --install all > /dev/null
    docker buildx create --name $BUILDER_NAME --use > /dev/null
    docker buildx inspect --bootstrap > /dev/null
  fi
}

# 构建镜像
build_image() {
  echo -e "\n${GREEN}=== 开始构建多架构镜像 ===${NC}"
  echo -e "镜像: ${YELLOW}${IMAGE}${NC}"
  echo -e "平台: ${YELLOW}linux/amd64,linux/arm64${NC}"
  [ -n "$BUILD_ARGS" ] && echo -e "参数: ${YELLOW}${BUILD_ARGS}${NC}"

  docker buildx build \
    --platform linux/amd64,linux/arm64 \
    -t $IMAGE \
    $BUILD_ARGS \
    --push .
}

# 验证镜像
verify_image() {
  echo -e "\n${GREEN}=== 验证镜像 ===${NC}"
  if docker manifest inspect $IMAGE > /dev/null; then
    echo -e "镜像清单:"
    docker manifest inspect $IMAGE | grep -E "architecture|os"
    echo -e "\n${GREEN}✓ 多架构镜像构建成功${NC}"
    echo -e "AMD64 镜像: ${YELLOW}${IMAGE} (x86_64)${NC}"
    echo -e "ARM64 镜像: ${YELLOW}${IMAGE} (aarch64)${NC}"
  else
    echo -e "${RED}错误: 镜像验证失败${NC}"
    exit 1
  fi
}

# 主执行流程
init_buildx
build_image
verify_image

