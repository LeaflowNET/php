FROM debian:12-slim

# 合并所有安装操作到单个 RUN 层减少镜像体积
RUN set -eux; \
    # 创建快捷命令
    echo '#!/bin/bash\nphp artisan "$@"' > /usr/bin/art && \
    chmod +x /usr/bin/art; \
    \
    # 更新系统并安装基础工具
    apt update; \
    apt install -y --no-install-recommends wget ca-certificates; \
    \
    # 添加 PHP 仓库
    wget --no-check-certificate -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg; \
    echo "deb https://packages.sury.org/php/ bookworm main" > /etc/apt/sources.list.d/php.list; \
    \
    # 安装 PHP 及运行时依赖
    apt update; \
    apt install -y --no-install-recommends \
        php8.4-cli \
        php8.4-bcmath \
        php8.4-curl \
        php8.4-mbstring \
        php8.4-zip \
        php8.4-dom \
        php8.4-mysql \
        php8.4-sqlite3 \
        php8.4-redis \
        php8.4-pgsql \
        php8.4-gd \
        php8.4-intl \
        php8.4-bz2 \
        php8.4-mongodb \
        php8.4-memcached \
        php8.4-imap \
        php8.4-exif \
        php8.4-fileinfo \
        php8.4-apcu \
        php8.4-gmp \
        libz-dev; \
    \
    # 安装构建依赖 (仅编译时使用)
    apt install -y --no-install-recommends php8.4-dev build-essential php-pear libgmp-dev libicu-dev; \
    \
    # 安装 PECL 扩展
    pecl channel-update pecl.php.net; \
    MAKEFLAGS="-j $(nproc)" pecl install grpc openswoole; \
    \
    # 移除构建依赖和缓存
    strip --strip-debug /usr/lib/php/*/*.so; \
    apt purge -y --auto-remove php8.4-dev build-essential php-pear; \
    rm -rf /var/lib/apt/lists/* /tmp/pear /usr/share/man/*; \
    \
    # 安装 Composer
    wget -qO /usr/bin/composer https://mirrors.aliyun.com/composer/composer.phar; \
    chmod +x /usr/bin/composer; \
    composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/

# 最后复制配置文件 (单独层便于修改)
COPY php.ini /etc/php/8.4/cli/conf.d/99-custom.ini