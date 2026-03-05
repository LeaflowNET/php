# frankenphp-runtime

基于 `dunglas/frankenphp` 的通用 PHP 运行时镜像模板，默认 `Classic Mode`，可通过环境变量切换到 `Worker Mode`。

## 特性

- 基座使用 `bookworm`（glibc）以获得更好的 ZTS 兼容性与性能
- 默认生产配置（`php.ini-production` + 自定义性能项）
- 镜像内置 `composer`
- 保留全量扩展策略（移除 `imap`，FrankenPHP 已知不兼容）
- 支持 `Caddyfile.d` 和 `PHP_INI_SCAN_DIR` 进行运行时覆盖
- 支持非 root 运行，同时保留 80/443 监听能力

## 默认环境变量

- `SERVER_NAME=:80`
- `SERVER_ROOT=public/`
- `FRANKENPHP_CONFIG=`（留空即 Classic）
- `CADDY_GLOBAL_OPTIONS=`
- `CADDY_EXTRA_CONFIG=`
- `CADDY_SERVER_EXTRA_DIRECTIVES=`
- `DEFAULT_HEALTHCHECK_PATH=/__builtin_healthcheck_disabled__`
- `HEALTHCHECK_PATH=`（留空时 Docker `HEALTHCHECK` 不探测）
- `GODEBUG=cgocheck=0`

## 健康检查策略

- 内置健康端点默认关闭（避免覆盖应用自身 `/healthz`）
- 开启内置健康端点：设置 `DEFAULT_HEALTHCHECK_PATH=/healthz`
- Docker 探针路径：设置 `HEALTHCHECK_PATH=/healthz`
- 若应用已有健康路由，仅设置 `HEALTHCHECK_PATH` 即可

## Worker 模式

默认不启用。示例：

```bash
docker run --rm -p 80:80 \
  -e FRANKENPHP_CONFIG="worker /app/public/index.php" \
  ghcr.io/leaflownet/php:php8.4
```

Worker 健康检查建议由应用自行提供并通过 `HEALTHCHECK_PATH` 指向应用路由。

## 多版本构建与推送

默认构建并推送：`php8.3`、`php8.4`、`php8.5`。

```bash
./build.sh
```

指定仓库并附加参数：

```bash
./build.sh ghcr.io/leaflownet/php --no-cache
```

可用环境变量：

- `FRANKENPHP_BASE_REPO`（默认 `dunglas/frankenphp`）
- `FRANKENPHP_SERIES`（仅用于 `8.3/8.4`，默认 `1.3`）
- `FRANKENPHP_TAG_85`（`8.5` 基础 tag，默认 `php8.5-bookworm`）
- `PHP_VERSIONS`（默认 `8.3 8.4 8.5`）
- `PLATFORMS`（默认 `linux/amd64,linux/arm64`）
- `BUILD_OUTPUT`（默认 `--push`）
- `PHP_EXTENSIONS`（可覆盖 Dockerfile 默认扩展列表）

## 配置覆盖

- Caddy 主配置：`/etc/caddy/Caddyfile`
- 额外 Caddy 覆盖：`/etc/caddy/Caddyfile.d/*.caddyfile`
- 额外 PHP 覆盖：`PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d:/custom/php.d`

## 已知限制

- `imap` 扩展未包含（FrankenPHP 线程模型下不兼容）
