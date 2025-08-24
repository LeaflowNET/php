FROM debian:12-slim

# 定义 PHP 版本
ARG PHP_VERSION=8.4
ENV PHP_VERSION=${PHP_VERSION}

# 复制并执行安装脚本
COPY setup.sh /setup.sh
RUN chmod +x /setup.sh && /setup.sh && rm /setup.sh

# 最后复制配置文件 (单独层便于修改)
COPY php.ini /etc/php/${PHP_VERSION}/cli/conf.d/99-custom.ini

# 默认启动 Nginx 和 PHP-FPM 如果没有传入命令
CMD ["/bin/sh", "-c", "php-fpm${PHP_VERSION} -D && nginx -g 'daemon off;'"]
