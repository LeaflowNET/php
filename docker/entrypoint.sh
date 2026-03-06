#!/bin/sh

set -eu

file_env() {
  var_name="$1"
  default_value="${2:-}"
  file_var_name="${var_name}_FILE"

  eval current_value="\${${var_name}:-}"
  eval file_value="\${${file_var_name}:-}"

  if [ -n "${current_value}" ] && [ -n "${file_value}" ]; then
    echo "error: both ${var_name} and ${file_var_name} are set" >&2
    exit 1
  fi

  if [ -n "${current_value}" ]; then
    export "${var_name}=${current_value}"
  elif [ -n "${file_value}" ]; then
    export "${var_name}=$(cat "${file_value}")"
  elif [ -n "${default_value}" ]; then
    export "${var_name}=${default_value}"
  fi

  unset "${file_var_name}"
}

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

detect_memory_limit_mb() {
  limit_bytes=""

  if [ -r /sys/fs/cgroup/memory.max ]; then
    limit_bytes="$(cat /sys/fs/cgroup/memory.max)"
  elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    limit_bytes="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
  fi

  case "${limit_bytes}" in
    ""|max) echo 0; return ;;
  esac

  case "${limit_bytes}" in
    *[!0-9]*) echo 0; return ;;
  esac

  if [ "${limit_bytes}" -ge 9223372036854771712 ] 2>/dev/null; then
    echo 0
    return
  fi

  echo $((limit_bytes / 1024 / 1024))
}

auto_opcache_memory() {
  memory_mb="${1:-0}"

  if [ "${memory_mb}" -le 0 ] 2>/dev/null; then
    echo 256
  elif [ "${memory_mb}" -le 1024 ]; then
    echo 128
  elif [ "${memory_mb}" -le 2048 ]; then
    echo 192
  elif [ "${memory_mb}" -le 4096 ]; then
    echo 256
  else
    echo 384
  fi
}

auto_interned_strings_buffer() {
  memory_mb="${1:-0}"

  if [ "${memory_mb}" -le 0 ] 2>/dev/null; then
    echo 16
  elif [ "${memory_mb}" -le 1024 ]; then
    echo 8
  elif [ "${memory_mb}" -le 4096 ]; then
    echo 16
  else
    echo 32
  fi
}

runtime_ini_dir="${PHP_RUNTIME_INI_DIR:-/tmp/php-runtime.d}"
runtime_ini_file="${runtime_ini_dir}/99-runtime-env.ini"
mkdir -p "${runtime_ini_dir}"

file_env CADDY_GLOBAL_OPTIONS
file_env CADDY_EXTRA_CONFIG
file_env CADDY_SERVER_EXTRA_DIRECTIVES
file_env FRANKENPHP_CONFIG
file_env PHP_SESSION_REDIS_AUTH
file_env PHP_SESSION_REDIS_SAVE_PATH
file_env PHP_RUNTIME_INI_APPEND

memory_limit_mb="$(detect_memory_limit_mb)"

upload_max_filesize="${PHP_UPLOAD_MAX_FILESIZE:-100M}"
post_max_size="${PHP_POST_MAX_SIZE:-100M}"
memory_limit="${PHP_MEMORY_LIMIT:-256M}"
max_execution_time="${PHP_MAX_EXECUTION_TIME:-60}"
realpath_cache_size="${PHP_REALPATH_CACHE_SIZE:-4096K}"
realpath_cache_ttl="${PHP_REALPATH_CACHE_TTL:-600}"
output_buffering="${PHP_OUTPUT_BUFFERING:-On}"
expose_php="${PHP_EXPOSE_PHP:-Off}"
display_errors="${PHP_DISPLAY_ERRORS:-Off}"
log_errors="${PHP_LOG_ERRORS:-On}"
error_log="${PHP_ERROR_LOG:-/proc/self/fd/2}"
variables_order="${PHP_VARIABLES_ORDER:-EGPCS}"

opcache_enable="${PHP_OPCACHE_ENABLE:-1}"
opcache_enable_cli="${PHP_OPCACHE_ENABLE_CLI:-0}"
opcache_memory_consumption="${PHP_OPCACHE_MEMORY_CONSUMPTION:-$(auto_opcache_memory "${memory_limit_mb}")}"
opcache_interned_strings_buffer="${PHP_OPCACHE_INTERNED_STRINGS_BUFFER:-$(auto_interned_strings_buffer "${memory_limit_mb}")}"
opcache_max_accelerated_files="${PHP_OPCACHE_MAX_ACCELERATED_FILES:-65407}"
opcache_validate_timestamps="${PHP_OPCACHE_VALIDATE_TIMESTAMPS:-0}"
opcache_revalidate_freq="${PHP_OPCACHE_REVALIDATE_FREQ:-0}"
opcache_save_comments="${PHP_OPCACHE_SAVE_COMMENTS:-1}"
opcache_jit="${PHP_OPCACHE_JIT:-disable}"
opcache_jit_buffer_size="${PHP_OPCACHE_JIT_BUFFER_SIZE:-0}"
opcache_preload="${PHP_OPCACHE_PRELOAD:-}"
opcache_preload_user="${PHP_OPCACHE_PRELOAD_USER:-appuser}"

session_handler="${PHP_SESSION_HANDLER:-files}"
if is_true "${PHP_SESSION_REDIS_ENABLED:-0}"; then
  session_handler="redis"
fi

session_gc_maxlifetime="${PHP_SESSION_GC_MAXLIFETIME:-1440}"
session_cookie_secure="${PHP_SESSION_COOKIE_SECURE:-0}"
session_cookie_httponly="${PHP_SESSION_COOKIE_HTTPONLY:-1}"
session_cookie_samesite="${PHP_SESSION_COOKIE_SAMESITE:-Lax}"
session_use_strict_mode="${PHP_SESSION_USE_STRICT_MODE:-1}"
session_use_only_cookies="${PHP_SESSION_USE_ONLY_COOKIES:-1}"

session_save_path=""
if [ "${session_handler}" = "redis" ]; then
  session_save_path="${PHP_SESSION_REDIS_SAVE_PATH:-}"

  if [ -z "${session_save_path}" ]; then
    redis_host="${PHP_SESSION_REDIS_HOST:-redis}"
    redis_port="${PHP_SESSION_REDIS_PORT:-6379}"
    redis_db="${PHP_SESSION_REDIS_DB:-0}"
    redis_timeout="${PHP_SESSION_REDIS_TIMEOUT:-2.5}"
    redis_auth="${PHP_SESSION_REDIS_AUTH:-}"
    redis_prefix="${PHP_SESSION_REDIS_PREFIX:-}"

    session_save_path="tcp://${redis_host}:${redis_port}?database=${redis_db}&timeout=${redis_timeout}"

    if [ -n "${redis_auth}" ]; then
      session_save_path="${session_save_path}&auth=${redis_auth}"
    fi

    if [ -n "${redis_prefix}" ]; then
      session_save_path="${session_save_path}&prefix=${redis_prefix}"
    fi
  fi
fi

cat > "${runtime_ini_file}" <<EOF
[PHP]
variables_order = ${variables_order}
output_buffering = ${output_buffering}
expose_php = ${expose_php}
display_errors = ${display_errors}
log_errors = ${log_errors}
error_log = ${error_log}
upload_max_filesize = ${upload_max_filesize}
post_max_size = ${post_max_size}
memory_limit = ${memory_limit}
max_execution_time = ${max_execution_time}
realpath_cache_size = ${realpath_cache_size}
realpath_cache_ttl = ${realpath_cache_ttl}

[opcache]
opcache.enable = ${opcache_enable}
opcache.enable_cli = ${opcache_enable_cli}
opcache.memory_consumption = ${opcache_memory_consumption}
opcache.interned_strings_buffer = ${opcache_interned_strings_buffer}
opcache.max_accelerated_files = ${opcache_max_accelerated_files}
opcache.validate_timestamps = ${opcache_validate_timestamps}
opcache.revalidate_freq = ${opcache_revalidate_freq}
opcache.save_comments = ${opcache_save_comments}
opcache.jit = ${opcache_jit}
opcache.jit_buffer_size = ${opcache_jit_buffer_size}

[Session]
session.save_handler = ${session_handler}
session.gc_maxlifetime = ${session_gc_maxlifetime}
session.cookie_secure = ${session_cookie_secure}
session.cookie_httponly = ${session_cookie_httponly}
session.cookie_samesite = ${session_cookie_samesite}
session.use_strict_mode = ${session_use_strict_mode}
session.use_only_cookies = ${session_use_only_cookies}
EOF

if [ "${session_handler}" = "redis" ] && [ -n "${session_save_path}" ]; then
  printf 'session.save_path = "%s"\n' "${session_save_path}" >> "${runtime_ini_file}"
fi

if [ -n "${opcache_preload}" ]; then
  printf 'opcache.preload = "%s"\n' "${opcache_preload}" >> "${runtime_ini_file}"
  printf 'opcache.preload_user = "%s"\n' "${opcache_preload_user}" >> "${runtime_ini_file}"
fi

if [ -n "${PHP_RUNTIME_INI_APPEND_FILE:-}" ] && [ -f "${PHP_RUNTIME_INI_APPEND_FILE}" ]; then
  printf '\n' >> "${runtime_ini_file}"
  cat "${PHP_RUNTIME_INI_APPEND_FILE}" >> "${runtime_ini_file}"
  printf '\n' >> "${runtime_ini_file}"
fi

if [ -n "${PHP_RUNTIME_INI_APPEND:-}" ]; then
  printf '\n%s\n' "${PHP_RUNTIME_INI_APPEND}" >> "${runtime_ini_file}"
fi

exec docker-php-entrypoint "$@"
