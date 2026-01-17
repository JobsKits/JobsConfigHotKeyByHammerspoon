#!/bin/zsh
# ================================== Hammerspoon 安装与配置脚本 ==================================
# 功能：
# 1) 自检 Homebrew：已安装则升级/更新；未安装则安装最新版
# 2) 基于 brew 安装 Hammerspoon（cask）
# 3) 配置 ~/.hammerspoon/init.lua：存在则备份，不存在则新建；内容来自“脚本同级目录”的 init.lua
#
# 使用：
#   1) 将本脚本与 init.lua 放在同一目录
#   2) chmod +x ./install_hammerspoon.zsh
#   3) ./install_hammerspoon.zsh
#
# 注意：
# - 脚本会在关键步骤前等待你按回车确认
# - 备份文件会带时间戳
# - 日志写入：/tmp/<脚本名>.log
#
# 颜色输出：
# - 默认不输出颜色，避免终端/日志环境显示 \033[...] 乱码
# - 如需颜色：NO_COLOR=0 ./install_hammerspoon.zsh

set -euo pipefail

# ================================== 全局变量 ==================================
SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

LOCAL_INIT_LUA="${SCRIPT_DIR}/init.lua"
HS_DIR="${HOME}/.hammerspoon"
HS_INIT_LUA="${HS_DIR}/init.lua"

# ================================== 输出与日志（默认无颜色，避免 \033 乱码） ==================================
# NO_COLOR=1   => 纯文本（默认）
# NO_COLOR=0   => 开启颜色（终端支持 ANSI 时）
: "${NO_COLOR:=1}"

log() {
  local msg="$1"
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') | ${msg}" >> "${LOG_FILE}"
}

# 仅在开启颜色且 stdout 是 TTY 时才输出 ANSI 颜色
_should_color() {
  [[ "${NO_COLOR}" != "1" && -t 1 ]]
}

_color_print() { # $1: ansi_code, $2: message
  local code="$1"
  local msg="$2"
  if _should_color; then
    # %b 会解析 \033 转义序列；避免把 \033 当普通字符打印出来
    printf "%b\n" "${code}${msg}\033[0m"
  else
    print -r -- "${msg}"
  fi
  log "${msg}"
}

info_echo()    { _color_print "\033[36m" "ℹ️  $1"; }
success_echo() { _color_print "\033[32m" "✅ $1"; }
warn_echo()    { _color_print "\033[33m" "⚠️  $1"; }
error_echo()   { _color_print "\033[31m" "❌ $1"; }
note_echo()    { _color_print "\033[35m" "📝 $1"; }
gray_echo()    { _color_print "\033[90m" "·  $1"; }

# ================================== 通用：等待用户确认 ==================================
# 说明：打印自述并等待用户回车确认；用户不按回车就一直等待
wait_for_enter() {
  local title="$1"
  print -r -- ""
  note_echo "${title}"
  gray_echo "请确认无误后按【回车】继续执行（不按回车将一直等待）…"
  while true; do
    IFS= read -r _line
    break
  done
}

# ================================== 自述 ==================================
print_intro() {
  print -r -- ""
  print -r -- "============================================================"
  print -r -- "🛠️  Hammerspoon 安装与配置脚本"
  print -r -- "------------------------------------------------------------"
  print -r -- "将执行以下操作："
  print -r -- "1) 自检 Homebrew：存在则 brew update/upgrade；不存在则安装最新版"
  print -r -- "2) brew install --cask hammerspoon"
  print -r -- "3) 配置 ${HS_INIT_LUA}"
  print -r -- "   - 若已存在：备份为 init.lua.bak.<timestamp>"
  print -r -- "   - 若不存在：创建目录并新建文件"
  print -r -- "   - 内容来源：脚本同级目录 ${LOCAL_INIT_LUA}"
  print -r -- "------------------------------------------------------------"
  print -r -- "日志文件：${LOG_FILE}"
  print -r -- "脚本目录：${SCRIPT_DIR}"
  print -r -- "============================================================"
  print -r -- ""
}

# ================================== Homebrew：环境注入 ==================================
# 说明：为了让当前脚本能直接用 brew（尤其是 Apple Silicon 默认不在 PATH），需要注入 shellenv
ensure_brew_in_path() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  # Apple Silicon 通常在 /opt/homebrew/bin/brew
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return 0
  fi

  # Intel 通常在 /usr/local/bin/brew
  if [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    return 0
  fi

  return 1
}

# ================================== Homebrew：安装（缺失时） ==================================
# 说明：未检测到 brew 时安装最新版 Homebrew（官方脚本方式）
install_brew_if_missing() {
  if ensure_brew_in_path; then
    success_echo "已检测到 Homebrew：$(command -v brew)"
    return 0
  fi

  warn_echo "未检测到 Homebrew，将安装最新版 Homebrew（官方安装脚本）。"
  wait_for_enter "确认：开始安装 Homebrew？"

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if ! ensure_brew_in_path; then
    error_echo "Homebrew 安装后仍无法在当前 shell 找到 brew。请重新打开终端后再运行本脚本。"
    exit 1
  fi

  success_echo "Homebrew 安装完成：$(command -v brew)"
}

# ================================== Homebrew：自检（存在则升级） ==================================
# 说明：存在 brew 的基础上执行 update/upgrade（符合“自检=存在则升级，没有则安装最新”）
self_check_brew() {
  install_brew_if_missing

  info_echo "执行 brew update…"
  brew update

  info_echo "执行 brew upgrade…"
  brew upgrade || true

  success_echo "Homebrew 自检完成（update/upgrade 已执行）。"
}

# ================================== 安装 Hammerspoon（cask） ==================================
# 说明：已安装则尝试升级；未安装则安装
install_hammerspoon() {
  info_echo "准备安装 Hammerspoon（brew cask）…"
  wait_for_enter "确认：开始安装/升级 Hammerspoon？"

  if brew list --cask hammerspoon >/dev/null 2>&1; then
    info_echo "已检测到 Hammerspoon cask，尝试升级…"
    brew upgrade --cask hammerspoon || true
    success_echo "Hammerspoon 升级流程已执行。"
  else
    info_echo "未检测到 Hammerspoon cask，开始安装…"
    brew install --cask hammerspoon
    success_echo "Hammerspoon 安装完成。"
  fi
}

# ================================== Hammerspoon 配置：检查 init.lua（备份/新建/写入） ==================================
# 说明：
# - 检查脚本同级目录 init.lua 是否存在
# - ~/.hammerspoon/init.lua 若存在则备份；不存在则创建
# - 用同级 init.lua 覆盖写入目标
prepare_hammerspoon_init() {
  if [[ ! -f "${LOCAL_INIT_LUA}" ]]; then
    error_echo "未找到脚本同级目录的 init.lua：${LOCAL_INIT_LUA}"
    error_echo "请把你的 init.lua 放到脚本同目录后重试。"
    exit 1
  fi

  info_echo "准备配置 Hammerspoon：${HS_INIT_LUA}"
  wait_for_enter "确认：开始写入/替换 ~/.hammerspoon/init.lua？"

  if [[ ! -d "${HS_DIR}" ]]; then
    info_echo "创建目录：${HS_DIR}"
    mkdir -p "${HS_DIR}"
  fi

  if [[ -f "${HS_INIT_LUA}" ]]; then
    local ts backup
    ts="$(date '+%Y%m%d_%H%M%S')"
    backup="${HS_INIT_LUA}.bak.${ts}"
    info_echo "检测到已存在 init.lua，备份为：${backup}"
    cp -a "${HS_INIT_LUA}" "${backup}"
    success_echo "备份完成。"
  else
    info_echo "未检测到 init.lua，将新建。"
    touch "${HS_INIT_LUA}"
  fi

  info_echo "从 ${LOCAL_INIT_LUA} 写入到 ${HS_INIT_LUA}"
  cp -f "${LOCAL_INIT_LUA}" "${HS_INIT_LUA}"
  success_echo "init.lua 已更新完成。"
}

# ================================== 提示：如何生效 ==================================
post_steps() {
  print -r -- ""
  success_echo "全部完成 ✅"
  note_echo "下一步（手动）："
  gray_echo "1) 打开 Applications -> Hammerspoon（或用 Spotlight 搜索）"
  gray_echo "2) 菜单栏锤子图标 -> Reload Config"
  gray_echo "3) 首次使用请在 系统设置 -> 隐私与安全性 -> 辅助功能 中允许 Hammerspoon"
  print -r -- ""
}

# ================================== main：收口执行入口 ==================================
# 说明：主函数中只做流程编排，保持清晰简洁；所有逻辑均封装在函数中
main() {
  : > "${LOG_FILE}" 2>/dev/null || true

  print_intro
  wait_for_enter "确认：我已了解脚本用途，继续执行？"

  self_check_brew
  install_hammerspoon
  prepare_hammerspoon_init
  post_steps
}

main "$@"
