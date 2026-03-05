#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

show_help() {
  echo -e "${YELLOW}FrankenPHP 多版本多架构构建脚本${NC}"
  echo -e "用法: $0 [仓库地址] [额外 buildx 参数]"
  echo -e ""
  echo -e "默认仓库: ghcr.io/leaflownet/php"
  echo -e "默认 PHP 版本: 8.3 8.4 8.5"
  echo -e "默认平台: linux/amd64,linux/arm64"
  echo -e "默认基础版本: FRANKENPHP_SERIES=1.3"
  echo -e ""
  echo -e "环境变量:"
  echo -e "  FRANKENPHP_SERIES   FrankenPHP 小版本 (默认: 1.3)"
  echo -e "  PHP_VERSIONS        版本列表，空格分隔 (默认: '8.3 8.4 8.5')"
  echo -e "  PLATFORMS           构建平台 (默认: linux/amd64,linux/arm64)"
  echo -e "  BUILD_OUTPUT        buildx 输出模式 (默认: --push)"
  echo -e "  PHP_EXTENSIONS      覆盖 Dockerfile 内置扩展列表"
  echo -e ""
  echo -e "示例:"
  echo -e "  ${GREEN}$0${NC}"
  echo -e "  ${GREEN}$0 ghcr.io/leaflownet/php --no-cache${NC}"
  echo -e "  ${GREEN}PHP_VERSIONS='8.4' BUILD_OUTPUT='--load' $0 local/php${NC}"
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

REPO="ghcr.io/leaflownet/php"
if [[ $# -gt 0 ]] && [[ "${1:0:1}" != "-" ]]; then
  REPO="$1"
  shift
fi

FRANKENPHP_SERIES="${FRANKENPHP_SERIES:-1.3}"
PHP_VERSIONS="${PHP_VERSIONS:-8.3 8.4 8.5}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILD_OUTPUT="${BUILD_OUTPUT:---push}"
PHP_EXTENSIONS="${PHP_EXTENSIONS:-}"

EXTRA_ARGS=("$@")

if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}错误: Docker 守护进程未运行${NC}"
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo -e "${RED}错误: docker buildx 不可用${NC}"
  exit 1
fi

BUILDER_NAME="multiarch_builder_$(date +%s)"
cleanup() {
  docker buildx rm "$BUILDER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo -e "${GREEN}初始化 buildx 构建器: ${YELLOW}${BUILDER_NAME}${NC}"
docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
docker buildx create --name "$BUILDER_NAME" --use >/dev/null
docker buildx inspect --bootstrap >/dev/null

echo -e "${GREEN}仓库: ${YELLOW}${REPO}${NC}"
echo -e "${GREEN}版本: ${YELLOW}${PHP_VERSIONS}${NC}"
echo -e "${GREEN}平台: ${YELLOW}${PLATFORMS}${NC}"
echo -e "${GREEN}FrankenPHP: ${YELLOW}${FRANKENPHP_SERIES}${NC}"

if [[ "${BUILD_OUTPUT}" == "--load" ]] && [[ "${PLATFORMS}" == *","* ]]; then
  echo -e "${RED}错误: --load 仅支持单平台构建，请设置单一 PLATFORMS${NC}"
  exit 1
fi

for version in ${PHP_VERSIONS}; do
  tag="${REPO}:php${version}"
  build_args=(
    --platform "${PLATFORMS}"
    --build-arg "FRANKENPHP_SERIES=${FRANKENPHP_SERIES}"
    --build-arg "PHP_VERSION=${version}"
  )

  if [[ -n "${PHP_EXTENSIONS}" ]]; then
    build_args+=(--build-arg "PHP_EXTENSIONS=${PHP_EXTENSIONS}")
  fi

  echo -e "\n${GREEN}=== 构建 ${YELLOW}${tag}${GREEN} ===${NC}"
  docker buildx build \
    "${build_args[@]}" \
    -t "${tag}" \
    "${EXTRA_ARGS[@]}" \
    "${BUILD_OUTPUT}" \
    .

  if [[ "${BUILD_OUTPUT}" == "--push" ]]; then
    echo -e "${GREEN}验证清单: ${YELLOW}${tag}${NC}"
    docker manifest inspect "${tag}" >/dev/null
  fi
done

echo -e "\n${GREEN}✓ 全部构建完成${NC}"
