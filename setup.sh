#!/bin/bash
set -eux

# 从环境变量获取 PHP 版本
PHP_VERSION=${PHP_VERSION:-8.4}

# 创建 Laravel 快捷命令
cat > /usr/bin/art <<EOF
#!/bin/bash
php artisan "\$@"
EOF
chmod +x /usr/bin/art

# 更新系统并安装基础工具
apt update
apt install -y --no-install-recommends wget unzip ca-certificates gnupg lsb-release

# 添加 PHP 仓库
wget --no-check-certificate -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

# 安装 PHP 及运行时依赖
apt update
apt install -y --no-install-recommends \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-dom \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-sqlite3 \
    php${PHP_VERSION}-redis \
    php${PHP_VERSION}-pgsql \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-bz2 \
    php${PHP_VERSION}-mongodb \
    php${PHP_VERSION}-memcached \
    php${PHP_VERSION}-imap \
    php${PHP_VERSION}-exif \
    php${PHP_VERSION}-fileinfo \
    php${PHP_VERSION}-apcu \
    php${PHP_VERSION}-gmp \
    libz-dev \
    libbrotli-dev

# 安装 Nginx
apt install -y --no-install-recommends nginx

# 安装构建依赖 (仅编译时使用)
apt install -y --no-install-recommends php${PHP_VERSION}-dev build-essential php-pear libgmp-dev libicu-dev librdkafka-dev

# 安装 PECL 扩展
pecl channel-update pecl.php.net
MAKEFLAGS="-j $(nproc)" pecl install swoole grpc rdkafka

# 移除构建依赖和缓存
strip --strip-debug /usr/lib/php/*/*.so
apt purge -y --auto-remove php${PHP_VERSION}-dev build-essential php-pear
rm -rf /var/lib/apt/lists/* /tmp/pear /usr/share/man/*

# 安装 Composer
wget -qO /usr/bin/composer https://mirrors.aliyun.com/composer/composer.phar
chmod +x /usr/bin/composer
composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/

# 配置 PHP-FPM
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
sed -i 's/;clear_env = no/clear_env = no/' "$PHP_FPM_CONF"

# 确保 PHP-FPM 监听的 socket 文件存在
mkdir -p /run/php
chown www-data:www-data /run/php

# 配置 Nginx 默认站点
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    server_name _;
    root /var/www/html/public;

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
