#!/bin/sh
set -eu

# =========================
# 离线模式配置
# =========================
VERSION="v1.5.5"
LOCAL_BINARY="${LOCAL_BINARY:-./vohive_v1.5.5_linux_amd64}"

NO_SYSTEMD=0
DRY_RUN=0
FORCE=0

REPO="offline"
CHANNEL="offline"

# =========================
# 安装路径
# =========================
ROOT_DIR="${VOHIVE_INSTALL_ROOT:-/opt/vohive}"
INSTALL_DIR="${ROOT_DIR}/bin"
CONFIG_DIR="${ROOT_DIR}/config"
DATA_DIR="${ROOT_DIR}/data"
LOG_DIR="${ROOT_DIR}/logs"

BIN_PATH="${INSTALL_DIR}/vohive"
BACKUP_PATH="${INSTALL_DIR}/vohive.bak"

SYSTEMD_SERVICE_PATH="${VOHIVE_SYSTEMD_SERVICE_PATH:-/etc/systemd/system/vohive.service}"
OPENWRT_INIT_PATH="${VOHIVE_OPENWRT_INIT_PATH:-/etc/init.d/vohive}"
OPENWRT_RELEASE_FILE="${VOHIVE_OPENWRT_RELEASE_FILE:-/etc/openwrt_release}"
PROCD_PATH="${VOHIVE_PROCD_PATH:-/sbin/procd}"
SYSTEMD_RUN_DIR="${VOHIVE_SYSTEMD_RUN_DIR:-/run/systemd/system}"

ACTIVE_PLATFORM="none"

# =========================
# 工具函数
# =========================
log() { printf '[vohive-install] %s\n' "$*"; }
err() { printf '[vohive-install] 错误: %s\n' "$*" >&2; }

usage() {
  cat <<USAGE
用法: ./install.sh [选项]
  --no-systemd
  --dry-run
  --force
USAGE
}

run_root() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    err "需要 root 权限"
    exit 1
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-systemd) NO_SYSTEMD=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --force) FORCE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) err "未知参数: $1"; exit 1 ;;
    esac
  done
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) err "不支持架构 $(uname -m)"; exit 1 ;;
  esac
}

detect_platform() {
  if [ -f "${OPENWRT_RELEASE_FILE}" ] || [ -x "${PROCD_PATH}" ]; then
    echo "openwrt"
    return
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -d "${SYSTEMD_RUN_DIR}" ]; then
    echo "systemd"
    return
  fi

  echo "none"
}

install_default_config() {
  run_root mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}"

  if [ ! -f "${CONFIG_DIR}/config.yaml" ] || [ "${FORCE}" = "1" ]; then
    run_root sh -c "cat >${CONFIG_DIR}/config.yaml" <<'CFG'
server:
  port: ":7575"

web:
  username: "admin"
  password: "admin"
CFG
  fi
}

install_systemd() {
  tmp="$1"

  cat >"${tmp}" <<EOF
[Unit]
Description=VoHive Service
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${ROOT_DIR}
ExecStart=${BIN_PATH} -c ${CONFIG_DIR}/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  run_root install -m 0644 "${tmp}" "${SYSTEMD_SERVICE_PATH}"
  run_root systemctl daemon-reload
  run_root systemctl enable vohive
  run_root systemctl restart vohive
}

install_openwrt() {
  tmp="$1"

  cat >"${tmp}" <<EOF
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
  procd_open_instance
  procd_set_param command ${BIN_PATH} -c ${CONFIG_DIR}/config.yaml
  procd_set_param directory ${ROOT_DIR}
  procd_set_param respawn
  procd_close_instance
}
EOF

  run_root install -m 0755 "${tmp}" "${OPENWRT_INIT_PATH}"
  run_root "${OPENWRT_INIT_PATH}" enable
  run_root "${OPENWRT_INIT_PATH}" restart
}

print_ips() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' \
    || hostname -I 2>/dev/null | awk '{print $1}'
}

print_info() {
  log "安装完成: ${BIN_PATH}"
  log "Web: http://127.0.0.1:7575"

  for ip in $(print_ips); do
    case "$ip" in
      127.*|::1|"") continue ;;
    esac
    log "Web: http://${ip}:7575"
  done
}

# =========================
# 主流程（纯离线核心）
# =========================
main() {
  parse_args "$@"

  arch="$(detect_arch)"

  LOCAL_BINARY="$(cd "$(dirname "$0")" && pwd)/vohive_v1.5.5_linux_${arch}"

  log "使用本地二进制: ${LOCAL_BINARY}"

  if [ ! -f "${LOCAL_BINARY}" ]; then
    err "找不到本地文件: ${LOCAL_BINARY}"
    err "请确保二进制与脚本在同目录"
    exit 1
  fi

  if [ -x "${BIN_PATH}" ]; then
    log "备份旧版本"
    run_root cp -f "${BIN_PATH}" "${BACKUP_PATH}"
  fi

  install_default_config

  run_root mkdir -p "${INSTALL_DIR}"
  run_root install -m 0755 "${LOCAL_BINARY}" "${BIN_PATH}"

  ACTIVE_PLATFORM="$(detect_platform)"

  if [ "${NO_SYSTEMD}" = "1" ]; then
    log "跳过服务安装"
  else
    case "${ACTIVE_PLATFORM}" in
      systemd)
        install_systemd "/tmp/vohive.service"
        ;;
      openwrt)
        install_openwrt "/tmp/vohive.init"
        ;;
      none)
        log "未检测服务管理器，仅安装二进制"
        ;;
    esac
  fi

  print_info
}

main "$@"