#!/bin/sh
set -eu

PHP_VERSION="${PHP_VERSION:-8.3}"
FPM_RUNTIME_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/zz-runtime-env.conf"

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

: "${PHP_FPM_PM:=dynamic}"
: "${PHP_FPM_PM_MAX_CHILDREN:=20}"
: "${PHP_FPM_PM_START_SERVERS:=4}"
: "${PHP_FPM_PM_MIN_SPARE_SERVERS:=2}"
: "${PHP_FPM_PM_MAX_SPARE_SERVERS:=8}"
: "${PHP_FPM_PM_MAX_REQUESTS:=500}"
: "${PHP_FPM_REQUEST_TERMINATE_TIMEOUT:=0}"

case "${PHP_FPM_PM}" in
  static)
    cat > "${FPM_RUNTIME_CONF}" <<EOF
[www]
pm = ${PHP_FPM_PM}
pm.max_children = ${PHP_FPM_PM_MAX_CHILDREN}
pm.max_requests = ${PHP_FPM_PM_MAX_REQUESTS}
request_terminate_timeout = ${PHP_FPM_REQUEST_TERMINATE_TIMEOUT}
EOF
    ;;
  ondemand)
    : "${PHP_FPM_PM_PROCESS_IDLE_TIMEOUT:=10s}"
    cat > "${FPM_RUNTIME_CONF}" <<EOF
[www]
pm = ${PHP_FPM_PM}
pm.max_children = ${PHP_FPM_PM_MAX_CHILDREN}
pm.process_idle_timeout = ${PHP_FPM_PM_PROCESS_IDLE_TIMEOUT}
pm.max_requests = ${PHP_FPM_PM_MAX_REQUESTS}
request_terminate_timeout = ${PHP_FPM_REQUEST_TERMINATE_TIMEOUT}
EOF
    ;;
  dynamic)
    cat > "${FPM_RUNTIME_CONF}" <<EOF
[www]
pm = ${PHP_FPM_PM}
pm.max_children = ${PHP_FPM_PM_MAX_CHILDREN}
pm.start_servers = ${PHP_FPM_PM_START_SERVERS}
pm.min_spare_servers = ${PHP_FPM_PM_MIN_SPARE_SERVERS}
pm.max_spare_servers = ${PHP_FPM_PM_MAX_SPARE_SERVERS}
pm.max_requests = ${PHP_FPM_PM_MAX_REQUESTS}
request_terminate_timeout = ${PHP_FPM_REQUEST_TERMINATE_TIMEOUT}
EOF
    ;;
  *)
    echo "Unsupported PHP_FPM_PM=${PHP_FPM_PM}, expected static|dynamic|ondemand" >&2
    exit 1
    ;;
esac

php-fpm${PHP_VERSION} -D
exec apache2ctl -D FOREGROUND
