#!/bin/sh

set -eu

file_env() {
  var_name="$1"
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
    echo 128
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

# ── Secret 文件注入 ────────────────────────────────────────────────────────────

file_env PHP_SESSION_REDIS_AUTH
file_env PHP_SESSION_REDIS_SAVE_PATH

# ── 计算派生值 ─────────────────────────────────────────────────────────────────

memory_limit_mb="$(detect_memory_limit_mb)"

# Session handler & save_path
_php_session_handler="${PHP_SESSION_HANDLER:-files}"
if is_true "${PHP_SESSION_REDIS_ENABLED:-0}"; then
  _php_session_handler="redis"
fi

_php_session_save_path=""
if [ "${_php_session_handler}" = "redis" ]; then
  _php_session_save_path="${PHP_SESSION_REDIS_SAVE_PATH:-}"

  if [ -z "${_php_session_save_path}" ]; then
    redis_host="${PHP_SESSION_REDIS_HOST:-redis}"
    redis_port="${PHP_SESSION_REDIS_PORT:-6379}"
    redis_db="${PHP_SESSION_REDIS_DB:-0}"
    redis_timeout="${PHP_SESSION_REDIS_TIMEOUT:-2.5}"
    redis_auth="${PHP_SESSION_REDIS_AUTH:-}"
    redis_prefix="${PHP_SESSION_REDIS_PREFIX:-}"

    _php_session_save_path="tcp://${redis_host}:${redis_port}?database=${redis_db}&timeout=${redis_timeout}"

    if [ -n "${redis_auth}" ]; then
      _php_session_save_path="${_php_session_save_path}&auth=${redis_auth}"
    fi

    if [ -n "${redis_prefix}" ]; then
      _php_session_save_path="${_php_session_save_path}&prefix=${redis_prefix}"
    fi
  fi
fi

# ── 导出所有模板变量（含默认值） ──────────────────────────────────────────────

export PHP_VARIABLES_ORDER="${PHP_VARIABLES_ORDER:-EGPCS}"
export PHP_OUTPUT_BUFFERING="${PHP_OUTPUT_BUFFERING:-On}"
export PHP_EXPOSE_PHP="${PHP_EXPOSE_PHP:-Off}"
export PHP_DISPLAY_ERRORS="${PHP_DISPLAY_ERRORS:-Off}"
export PHP_LOG_ERRORS="${PHP_LOG_ERRORS:-On}"
export PHP_ERROR_LOG="${PHP_ERROR_LOG:-/proc/self/fd/2}"

export PHP_UPLOAD_MAX_FILESIZE="${PHP_UPLOAD_MAX_FILESIZE:-100M}"
export PHP_POST_MAX_SIZE="${PHP_POST_MAX_SIZE:-100M}"
export PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-256M}"
export PHP_MAX_EXECUTION_TIME="${PHP_MAX_EXECUTION_TIME:-60}"
export PHP_REALPATH_CACHE_SIZE="${PHP_REALPATH_CACHE_SIZE:-4096K}"
export PHP_REALPATH_CACHE_TTL="${PHP_REALPATH_CACHE_TTL:-600}"

export PHP_OPCACHE_ENABLE="${PHP_OPCACHE_ENABLE:-1}"
export PHP_OPCACHE_ENABLE_CLI="${PHP_OPCACHE_ENABLE_CLI:-0}"
export PHP_OPCACHE_MEMORY_CONSUMPTION="${PHP_OPCACHE_MEMORY_CONSUMPTION:-$(auto_opcache_memory "${memory_limit_mb}")}"
export PHP_OPCACHE_INTERNED_STRINGS_BUFFER="${PHP_OPCACHE_INTERNED_STRINGS_BUFFER:-32}"
export PHP_OPCACHE_MAX_ACCELERATED_FILES="${PHP_OPCACHE_MAX_ACCELERATED_FILES:-65407}"
export PHP_OPCACHE_VALIDATE_TIMESTAMPS="${PHP_OPCACHE_VALIDATE_TIMESTAMPS:-0}"
export PHP_OPCACHE_SAVE_COMMENTS="${PHP_OPCACHE_SAVE_COMMENTS:-1}"
export PHP_OPCACHE_JIT="${PHP_OPCACHE_JIT:-tracing}"
export PHP_OPCACHE_JIT_BUFFER_SIZE="${PHP_OPCACHE_JIT_BUFFER_SIZE:-64M}"
export PHP_OPCACHE_PRELOAD="${PHP_OPCACHE_PRELOAD:-}"
export PHP_OPCACHE_PRELOAD_USER="${PHP_OPCACHE_PRELOAD_USER:-appuser}"

export PHP_SESSION_GC_MAXLIFETIME="${PHP_SESSION_GC_MAXLIFETIME:-1440}"
export _PHP_SESSION_HANDLER="${_php_session_handler}"
export _PHP_SESSION_SAVE_PATH="${_php_session_save_path}"

export PHP_APCU_SHM_SIZE="${PHP_APCU_SHM_SIZE:-32M}"

# ── 渲染模板 ──────────────────────────────────────────────────────────────────

runtime_ini_dir="${PHP_RUNTIME_INI_DIR:-/tmp/php-runtime.d}"
runtime_ini_file="${runtime_ini_dir}/99-runtime-env.ini"
mkdir -p "${runtime_ini_dir}"

envsubst < /etc/php-runtime.ini.template > "${runtime_ini_file}"

# ── 可选追加 ──────────────────────────────────────────────────────────────────

if [ -n "${PHP_RUNTIME_INI_APPEND_FILE:-}" ] && [ -f "${PHP_RUNTIME_INI_APPEND_FILE}" ]; then
  printf '\n' >> "${runtime_ini_file}"
  cat "${PHP_RUNTIME_INI_APPEND_FILE}" >> "${runtime_ini_file}"
  printf '\n' >> "${runtime_ini_file}"
fi

if [ -n "${PHP_RUNTIME_INI_APPEND:-}" ]; then
  printf '\n%s\n' "${PHP_RUNTIME_INI_APPEND}" >> "${runtime_ini_file}"
fi

exec docker-php-entrypoint "$@"
