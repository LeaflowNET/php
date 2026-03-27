# frankenphp-runtime

基于 `dunglas/frankenphp` 的通用 PHP 运行时镜像模板，默认 `Classic Mode`，可通过环境变量切换到 `Worker Mode`。

## 特性

- 基座使用 `bookworm`（glibc）以获得更好的 ZTS 兼容性与性能
- 默认生产配置（`php.ini-production` + 自定义性能项）
- 镜像内置 `composer`
- 保留全量扩展策略（移除 `imap`，FrankenPHP 已知不兼容）
- 版本拆分构建（`Dockerfile.php83`、`Dockerfile.php84`、`Dockerfile.php85`）
- 额外提供 `php8.3-nginx-fpm` 变体（`Dockerfile.nginx-php83-fpm`，仅此变体内置 ionCube）
- 扩展列表拆分配置（`docker/php-extensions/*.list`）
- 启动时基于环境变量动态生成 `99-runtime-env.ini`
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
- `PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d:/tmp/php-runtime.d`

## 环境变量功能索引

- **服务与路由**
  - `SERVER_NAME`: Caddy 监听/站点匹配
  - `SERVER_ROOT`: 应用根目录（默认 `public/`）
  - `HEALTHCHECK_PATH`: Docker 健康检查探测路径
  - `DEFAULT_HEALTHCHECK_PATH`: 内置健康端点路径（默认关闭）
- **FrankenPHP/Caddy**
  - `FRANKENPHP_CONFIG`: FrankenPHP 运行配置（可切 Worker）
  - `CADDY_GLOBAL_OPTIONS`: Caddy 全局块注入
  - `CADDY_EXTRA_CONFIG`: 顶层附加配置注入
  - `CADDY_SERVER_EXTRA_DIRECTIVES`: server 块附加指令
- **PHP 运行时**
  - `PHP_UPLOAD_MAX_FILESIZE` / `PHP_POST_MAX_SIZE` / `PHP_MEMORY_LIMIT`
  - `PHP_OPCACHE_ENABLE` / `PHP_OPCACHE_ENABLE_CLI`
  - `PHP_OPCACHE_MEMORY_CONSUMPTION` / `PHP_OPCACHE_INTERNED_STRINGS_BUFFER` / `PHP_OPCACHE_MAX_ACCELERATED_FILES` / `PHP_OPCACHE_VALIDATE_TIMESTAMPS`
  - `PHP_OPCACHE_JIT`（默认 `tracing`，可设 `disable` 关闭）/ `PHP_OPCACHE_JIT_BUFFER_SIZE`（默认 `64M`）
  - `PHP_OPCACHE_PRELOAD` / `PHP_OPCACHE_PRELOAD_USER`
  - `PHP_APCU_SHM_SIZE`（默认 `32M`）
  - `PHP_RUNTIME_INI_APPEND_FILE` / `PHP_RUNTIME_INI_APPEND`
  - `PHP_INI_SCAN_DIR`: 附加 ini 扫描目录
- **Session**
  - `PHP_SESSION_REDIS_ENABLED`: 开关（`1/true/on` 启用 Redis）
  - `PHP_SESSION_REDIS_HOST/PORT/DB/TIMEOUT/PREFIX/AUTH`
  - `PHP_SESSION_REDIS_SAVE_PATH`: 完整 save_path 覆盖
  - `PHP_SESSION_REDIS_SAVE_PATH_FILE`: 从文件读取 save_path
  - `PHP_SESSION_REDIS_AUTH_FILE`: 从文件读取密码

## Caddy 配置机制

- 镜像内固定主模板：`/etc/caddy/Caddyfile`
- 主模板通过占位符读取环境变量：`CADDY_GLOBAL_OPTIONS`、`FRANKENPHP_CONFIG`、`CADDY_EXTRA_CONFIG`、`CADDY_SERVER_EXTRA_DIRECTIVES`
- 额外覆盖入口：`/etc/caddy/Caddyfile.d/*.caddyfile`

Early Hints 建议放在应用层（PHP 发送 `103`）：

```php
header('Link: </app.css>; rel=preload; as=style');
headers_send(103);
```

如果确实要在 Caddy 注入额外逻辑，优先挂载 `Caddyfile.d` 片段文件。

## 运行时 PHP 配置

容器启动时会根据环境变量生成 `/tmp/php-runtime.d/99-runtime-env.ini`（优先级高于镜像内默认 `php.ini`），未设置则使用默认值。

常用性能与限制变量：

- `PHP_UPLOAD_MAX_FILESIZE`（默认 `100M`）
- `PHP_POST_MAX_SIZE`（默认 `100M`）
- `PHP_MEMORY_LIMIT`（默认 `256M`）
- `PHP_MAX_EXECUTION_TIME`（默认 `60`）
- `PHP_REALPATH_CACHE_SIZE`（默认 `4096K`）
- `PHP_REALPATH_CACHE_TTL`（默认 `600`）
- `PHP_OPCACHE_ENABLE`（默认 `1`）
- `PHP_OPCACHE_ENABLE_CLI`（默认 `0`）
- `PHP_OPCACHE_MEMORY_CONSUMPTION`（默认按 cgroup 内存自动估算）
- `PHP_OPCACHE_INTERNED_STRINGS_BUFFER`（默认 `32`，单位 MB）
- `PHP_OPCACHE_MAX_ACCELERATED_FILES`（默认 `65407`）
- `PHP_OPCACHE_VALIDATE_TIMESTAMPS`（默认 `0`，生产建议保持）
- `PHP_OPCACHE_JIT`（默认 `tracing`，可设 `disable` 关闭 JIT）
- `PHP_OPCACHE_JIT_BUFFER_SIZE`（默认 `64M`）
- `PHP_OPCACHE_PRELOAD`（默认空）
- `PHP_OPCACHE_PRELOAD_USER`（默认 `appuser`）
- `PHP_APCU_SHM_SIZE`（默认 `32M`）
- `PHP_RUNTIME_INI_APPEND_FILE`（默认空，挂载文件并追加到运行时 ini）
- `PHP_RUNTIME_INI_APPEND`（默认空，直接追加 ini 文本）

运行时 ini 由 `docker/php-runtime.ini.template` 通过 `envsubst` 渲染生成，所有变量均可通过对应环境变量覆盖。需要模板未覆盖的低层参数时，使用 `PHP_RUNTIME_INI_APPEND_FILE` 或 `PHP_RUNTIME_INI_APPEND` 追加。

示例：

```bash
docker run --rm -p 80:80 \
  -e PHP_UPLOAD_MAX_FILESIZE=256M \
  -e PHP_POST_MAX_SIZE=256M \
  -e PHP_MEMORY_LIMIT=512M \
  -e PHP_OPCACHE_MEMORY_CONSUMPTION=384 \
  ghcr.io/leaflownet/php:php8.4
```

## Session 存储到 Redis

默认 `session.save_handler=files`。开启 Redis：

- `PHP_SESSION_REDIS_ENABLED=1`
- `PHP_SESSION_REDIS_HOST`（默认 `redis`）
- `PHP_SESSION_REDIS_PORT`（默认 `6379`）
- `PHP_SESSION_REDIS_DB`（默认 `0`）
- `PHP_SESSION_REDIS_AUTH`（可选）
- `PHP_SESSION_REDIS_PREFIX`（可选）
- `PHP_SESSION_REDIS_TIMEOUT`（默认 `2.5`）
- `PHP_SESSION_REDIS_SAVE_PATH`（可选，设置后优先于 host/port 组合）
- `PHP_SESSION_REDIS_SAVE_PATH_FILE`（可选，优先用于 Secret 文件注入）
- `PHP_SESSION_REDIS_AUTH_FILE`（可选，优先用于 Secret 文件注入）

示例：

```bash
docker run --rm -p 80:80 \
  -e PHP_SESSION_REDIS_ENABLED=1 \
  -e PHP_SESSION_REDIS_HOST=redis.default.svc.cluster.local \
  -e PHP_SESSION_REDIS_PORT=6379 \
  -e PHP_SESSION_REDIS_DB=2 \
  -e PHP_SESSION_REDIS_AUTH=your-password \
  ghcr.io/leaflownet/php:php8.4
```

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

## Kubernetes 推荐用法

为避免在 Deployment 里塞大量多行环境变量，建议：

- Caddy 自定义放 `ConfigMap -> /etc/caddy/Caddyfile.d/*.caddyfile`
- PHP 额外 ini 放 `ConfigMap -> /etc/php-extra/runtime.ini`，并设置 `PHP_RUNTIME_INI_APPEND_FILE=/etc/php-extra/runtime.ini`
- Redis 密码放 `Secret` 文件，使用 `PHP_SESSION_REDIS_AUTH_FILE`

示例（关键片段）：

```yaml
env:
  - name: PHP_SESSION_REDIS_ENABLED
    value: "1"
  - name: PHP_SESSION_REDIS_HOST
    value: "redis.default.svc.cluster.local"
  - name: PHP_SESSION_REDIS_AUTH_FILE
    value: "/var/run/secrets/php/redis-password"
  - name: PHP_RUNTIME_INI_APPEND_FILE
    value: "/etc/php-extra/runtime.ini"
volumeMounts:
  - name: php-extra
    mountPath: /etc/php-extra
    readOnly: true
  - name: caddy-extra
    mountPath: /etc/caddy/Caddyfile.d
    readOnly: true
  - name: php-secret
    mountPath: /var/run/secrets/php
    readOnly: true
```

## Laravel Octane

- 镜像已包含 Octane Worker 必需的 `pcntl` / `posix`（按 PHP 版本扩展清单安装）
- 默认基础 tag 使用 `php8.3-bookworm` / `php8.4-bookworm` / `php8.5-bookworm`
- 推荐保持 FrankenPHP 版本 `>= 1.5` 以避免 Octane 启动时尝试二进制升级
- 可直接使用 `php artisan octane:start --server=frankenphp`

## 多版本构建与推送

默认构建并推送：`php8.3`、`php8.4`、`php8.5`。

```bash
./build.sh all
```

指定仓库并附加参数：

```bash
./build.sh 8.5 ghcr.io/leaflownet/php --no-cache
```

单版本构建（推荐）：

```bash
./build.sh 8.3
./build.sh 8.4
./build.sh 8.5
```

高并发构建（用于多核构建机）：

```bash
IPE_PROCESSOR_COUNT="$(nproc)" \
IPE_MAKEFLAGS="-j$(nproc)" \
./build.sh 8.5 ghcr.io/leaflownet/php
```

可用环境变量：

- `FRANKENPHP_BASE_REPO`（默认 `dunglas/frankenphp`）
- `FRANKENPHP_TAG_83`（默认 `php8.3-bookworm`）
- `FRANKENPHP_TAG_84`（默认 `php8.4-bookworm`）
- `FRANKENPHP_TAG_85`（默认 `php8.5-bookworm`）
- `PHP_VERSIONS`（默认 `8.3 8.4 8.5`）
- `PLATFORMS`（默认 `linux/amd64`，多平台示例：`linux/amd64,linux/arm64`）
- `BUILD_OUTPUT`（默认 `--push`）
- `PHP_EXTENSIONS`（可覆盖 Dockerfile 默认扩展列表）

版本文件：

- `Dockerfile.php83` -> `docker/php-extensions/php83.list`
- `Dockerfile.php84` -> `docker/php-extensions/php84.list`
- `Dockerfile.php85` -> `docker/php-extensions/php85.list`

## 配置覆盖

- Caddy 主配置：`/etc/caddy/Caddyfile`
- 额外 Caddy 覆盖：`/etc/caddy/Caddyfile.d/*.caddyfile`
- PHP 运行时配置模板：`docker/php-runtime.ini.template`（envsubst 渲染，所有项均可通过环境变量覆盖）
- 额外 PHP 追加：`PHP_RUNTIME_INI_APPEND_FILE` 或 `PHP_RUNTIME_INI_APPEND`
- 额外 PHP ini 目录：`PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d:/tmp/php-runtime.d:/custom/php.d`

## 已知限制

- `imap` 扩展未包含（FrankenPHP 线程模型下不兼容）
- `swoole` 在 `PHP 8.5` 当前未包含（上游版本约束 `<= 8.4.99`）

## Nginx + PHP-FPM (8.3 + ionCube)

- 该仓库默认产物仍是 FrankenPHP（`php8.3` / `php8.4` / `php8.5`）
- 额外提供独立 tag：`ghcr.io/leaflownet/php:php8.3-nginx-fpm`
- 仅 `php8.3-nginx-fpm` 内置 ionCube（来自仓库 `ioncube/ioncube_loader_lin_8.3.so`）
- ionCube 通过 `zend_extension=` 注入到 FPM/CLI；FrankenPHP 变体不注入 ionCube
- 该镜像默认仅监听 `80`，设计用于上游反代（Traefik/Nginx Ingress/ALB），不在容器内做 TLS 终结
- 预留 Nginx 覆盖目录：`/etc/nginx/custom/http.d/*.conf` 与 `/etc/nginx/custom/server.d/*.conf`
- FPM 镜像支持 `php.ini` 覆盖（可挂载 `conf.d` 文件，或设置 `PHP_INI_SCAN_DIR`）
- FPM 池参数支持环境变量覆盖（如 `pm.max_children`、`pm.max_requests` 等）
- Nginx 与 PHP-FPM 日志输出到容器 `stdout/stderr`

示例：

```bash
docker run --rm -p 8080:80 ghcr.io/leaflownet/php:php8.3-nginx-fpm
```

Traefik/反向代理场景可挂载自定义配置（如 real ip）：

```bash
docker run --rm -p 8080:80 \
  -v $(pwd)/nginx-http.d:/etc/nginx/custom/http.d:ro \
  -v $(pwd)/nginx-server.d:/etc/nginx/custom/server.d:ro \
  ghcr.io/leaflownet/php:php8.3-nginx-fpm
```

示例 `nginx-http.d/real-ip.conf`（按你的上游网关网段调整）：

```nginx
set_real_ip_from 10.0.0.0/8;
set_real_ip_from 172.16.0.0/12;
set_real_ip_from 192.168.0.0/16;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
```

PHP 配置覆盖（推荐挂载额外 ini）：

```bash
docker run --rm -p 8080:80 \
  -v $(pwd)/php-extra/99-custom.ini:/etc/php/8.3/fpm/conf.d/99-custom.ini:ro \
  -v $(pwd)/php-extra/99-custom.ini:/etc/php/8.3/cli/conf.d/99-custom.ini:ro \
  ghcr.io/leaflownet/php:php8.3-nginx-fpm
```

也可以用 `PHP_INI_SCAN_DIR` 增加扫描目录：

```bash
docker run --rm -p 8080:80 \
  -e PHP_INI_SCAN_DIR="/etc/php/8.3/fpm/conf.d:/custom/php.d" \
  -v $(pwd)/php-extra:/custom/php.d:ro \
  ghcr.io/leaflownet/php:php8.3-nginx-fpm
```

PHP-FPM 池参数覆盖示例：

```bash
docker run --rm -p 8080:80 \
  -e PHP_FPM_PM=dynamic \
  -e PHP_FPM_PM_MAX_CHILDREN=80 \
  -e PHP_FPM_PM_START_SERVERS=8 \
  -e PHP_FPM_PM_MIN_SPARE_SERVERS=4 \
  -e PHP_FPM_PM_MAX_SPARE_SERVERS=16 \
  -e PHP_FPM_PM_MAX_REQUESTS=1000 \
  -e PHP_FPM_REQUEST_TERMINATE_TIMEOUT=120s \
  ghcr.io/leaflownet/php:php8.3-nginx-fpm
```

支持的 FPM 环境变量：

- `PHP_FPM_PM` (`static` | `dynamic` | `ondemand`)
- `PHP_FPM_PM_MAX_CHILDREN`
- `PHP_FPM_PM_START_SERVERS`（`dynamic`）
- `PHP_FPM_PM_MIN_SPARE_SERVERS`（`dynamic`）
- `PHP_FPM_PM_MAX_SPARE_SERVERS`（`dynamic`）
- `PHP_FPM_PM_PROCESS_IDLE_TIMEOUT`（`ondemand`）
- `PHP_FPM_PM_MAX_REQUESTS`
- `PHP_FPM_REQUEST_TERMINATE_TIMEOUT`

本地构建该变体：

```bash
./build.sh 8.3-nginx-fpm ghcr.io/leaflownet/php
```
