#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

show_help() {
  echo -e "${YELLOW}FrankenPHP 手动串行构建脚本${NC}"
  echo -e "用法: $0 <php-version|all> [仓库地址] [额外 buildx 参数]"
  echo -e ""
  echo -e "可选版本: 8.3 | 8.4 | 8.5 | 8.3-nginx-fpm | 8.3-apache-fpm | all"
  echo -e "默认仓库: ghcr.io/leaflownet/php"
  echo -e "默认平台: linux/amd64,linux/arm64"
  echo -e "默认输出: --push"
  echo -e ""
  echo -e "环境变量:"
  echo -e "  FRANKENPHP_BASE_REPO 基础镜像仓库 (默认: dunglas/frankenphp)"
  echo -e "  FRANKENPHP_TAG_83   覆盖 PHP 8.3 基础 tag"
  echo -e "  FRANKENPHP_TAG_84   覆盖 PHP 8.4 基础 tag"
  echo -e "  FRANKENPHP_TAG_85   覆盖 PHP 8.5 基础 tag"
  echo -e "  PLATFORMS           构建平台 (默认: linux/amd64,linux/arm64)"
  echo -e "  BUILD_OUTPUT        buildx 输出模式 (默认: --push)"
  echo -e "  PHP_EXTENSIONS      覆盖 Dockerfile 内置扩展列表"
  echo -e "  IPE_PROCESSOR_COUNT install-php-extensions 编译并发数"
  echo -e "  IPE_MAKEFLAGS       透传给 make 的参数，如 '-j64'"
  echo -e ""
  echo -e "示例:"
  echo -e "  ${GREEN}$0 8.4${NC}"
  echo -e "  ${GREEN}$0 8.5 ghcr.io/leaflownet/php --no-cache${NC}"
  echo -e "  ${GREEN}BUILD_OUTPUT='--load' PLATFORMS='linux/amd64' $0 8.3 local/php${NC}"
  echo -e "  ${GREEN}$0 all ghcr.io/leaflownet/php${NC}"
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo -e "${RED}错误: 缺少 php 版本参数${NC}"
  show_help
  exit 1
fi

TARGET_VERSION="$1"
shift

REPO="ghcr.io/leaflownet/php"
if [[ $# -gt 0 ]] && [[ "${1:0:1}" != "-" ]]; then
  REPO="$1"
  shift
fi

EXTRA_ARGS=("$@")

FRANKENPHP_BASE_REPO="${FRANKENPHP_BASE_REPO:-dunglas/frankenphp}"
FRANKENPHP_TAG_83="${FRANKENPHP_TAG_83:-php8.3-bookworm}"
FRANKENPHP_TAG_84="${FRANKENPHP_TAG_84:-php8.4-bookworm}"
FRANKENPHP_TAG_85="${FRANKENPHP_TAG_85:-php8.5-bookworm}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
BUILD_OUTPUT="${BUILD_OUTPUT:---push}"
PHP_EXTENSIONS="${PHP_EXTENSIONS:-}"
IPE_PROCESSOR_COUNT="${IPE_PROCESSOR_COUNT:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
IPE_MAKEFLAGS="${IPE_MAKEFLAGS:-}"

if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}错误: Docker 守护进程未运行${NC}"
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo -e "${RED}错误: docker buildx 不可用${NC}"
  exit 1
fi

if [[ "${BUILD_OUTPUT}" == "--load" ]] && [[ "${PLATFORMS}" == *","* ]]; then
  echo -e "${RED}错误: --load 仅支持单平台构建，请设置单一 PLATFORMS${NC}"
  exit 1
fi

case "${TARGET_VERSION}" in
  8.3|8.4|8.5|8.3-nginx-fpm|8.3-apache-fpm)
    VERSIONS=("${TARGET_VERSION}")
    ;;
  all)
    VERSIONS=("8.3" "8.4" "8.5")
    ;;
  *)
    echo -e "${RED}错误: 不支持的版本 ${TARGET_VERSION}${NC}"
    show_help
    exit 1
    ;;
esac

BUILDER_NAME="manual_buildx_$(date +%s)"
cleanup() {
  docker buildx rm "$BUILDER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo -e "${GREEN}初始化 buildx 构建器: ${YELLOW}${BUILDER_NAME}${NC}"
docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
docker buildx create --name "$BUILDER_NAME" --use >/dev/null
docker buildx inspect --bootstrap >/dev/null

echo -e "${GREEN}仓库: ${YELLOW}${REPO}${NC}"
echo -e "${GREEN}目标版本: ${YELLOW}${VERSIONS[*]}${NC}"
echo -e "${GREEN}平台: ${YELLOW}${PLATFORMS}${NC}"
echo -e "${GREEN}基础仓库: ${YELLOW}${FRANKENPHP_BASE_REPO}${NC}"
echo -e "${GREEN}编译并发: ${YELLOW}${IPE_PROCESSOR_COUNT}${NC}"
if [[ -n "${IPE_MAKEFLAGS}" ]]; then
  echo -e "${GREEN}MAKEFLAGS: ${YELLOW}${IPE_MAKEFLAGS}${NC}"
fi

for version in "${VERSIONS[@]}"; do
  case "${version}" in
    8.3)
      dockerfile="Dockerfile.php83"
      frankenphp_tag="${FRANKENPHP_TAG_83}"
      image_tag="${REPO}:php8.3"
      build_mode="frankenphp"
      ;;
    8.4)
      dockerfile="Dockerfile.php84"
      frankenphp_tag="${FRANKENPHP_TAG_84}"
      image_tag="${REPO}:php8.4"
      build_mode="frankenphp"
      ;;
    8.5)
      dockerfile="Dockerfile.php85"
      frankenphp_tag="${FRANKENPHP_TAG_85}"
      image_tag="${REPO}:php8.5"
      build_mode="frankenphp"
      ;;
    8.3-nginx-fpm)
      dockerfile="Dockerfile.nginx-php83-fpm"
      frankenphp_tag="-"
      image_tag="${REPO}:php8.3-nginx-fpm"
      build_mode="nginx-fpm"
      ;;
    8.3-apache-fpm)
      dockerfile="Dockerfile.apache-php83-fpm"
      frankenphp_tag="-"
      image_tag="${REPO}:php8.3-apache-fpm"
      build_mode="apache-fpm"
      ;;
  esac
  echo -e "\n${GREEN}=== 开始构建 ${YELLOW}${image_tag}${GREEN} ===${NC}"
  echo -e "Dockerfile: ${YELLOW}${dockerfile}${NC}"
  echo -e "Base Tag : ${YELLOW}${frankenphp_tag}${NC}"

  build_args=(
    --platform "${PLATFORMS}"
    --file "${dockerfile}"
  )

  if [[ "${build_mode}" == "frankenphp" ]]; then
    build_args+=(
      --build-arg "FRANKENPHP_REPO=${FRANKENPHP_BASE_REPO}"
      --build-arg "FRANKENPHP_TAG=${frankenphp_tag}"
      --build-arg "IPE_PROCESSOR_COUNT=${IPE_PROCESSOR_COUNT}"
    )
  fi

  if [[ "${build_mode}" == "frankenphp" ]] && [[ -n "${PHP_EXTENSIONS}" ]]; then
    build_args+=(--build-arg "PHP_EXTENSIONS=${PHP_EXTENSIONS}")
  fi

  if [[ "${build_mode}" == "frankenphp" ]] && [[ -n "${IPE_MAKEFLAGS}" ]]; then
    build_args+=(--build-arg "IPE_MAKEFLAGS=${IPE_MAKEFLAGS}")
  fi

  docker buildx build \
    "${build_args[@]}" \
    -t "${image_tag}" \
    "${EXTRA_ARGS[@]}" \
    "${BUILD_OUTPUT}" \
    .

  if [[ "${BUILD_OUTPUT}" == "--push" ]]; then
    echo -e "${GREEN}验证镜像清单: ${YELLOW}${image_tag}${NC}"
    docker manifest inspect "${image_tag}" >/dev/null
  fi

  echo -e "${GREEN}✓ 版本 ${YELLOW}${version}${GREEN} 构建完成${NC}"
done

echo -e "\n${GREEN}✓ 全部目标版本构建完成${NC}"
