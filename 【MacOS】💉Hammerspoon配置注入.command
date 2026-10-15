#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】💉Hammerspoon配置注入.command
# - 核心用途：执行“💉Hammerspoon配置注入”对应的本机环境配置任务。
# - 影响范围：可能安装、更新或修改当前用户的工具链与配置文件。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
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


# ================================== 全局变量 ==================================
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
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
# 统一输出终端信息并同步记录日志。
log() {
  local msg="$1"
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') | ${msg}" >> "${LOG_FILE}"
}
# 仅在开启颜色且 stdout 是 TTY 时才输出 ANSI 颜色
_should_color() {
  [[ "${NO_COLOR}" != "1" && -t 1 ]]
}
# 封装 color print 对应的独立处理逻辑。
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
# 输出 info echo 对应级别的日志信息。
info_echo()    { _color_print "\033[36m" "ℹ️  $1"; }
# 输出 success echo 对应级别的日志信息。
success_echo() { _color_print "\033[32m" "✅ $1"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()    { _color_print "\033[33m" "⚠️  $1"; }
# 输出 error echo 对应级别的日志信息。
error_echo()   { _color_print "\033[31m" "❌ $1"; }
# 输出 note echo 对应级别的日志信息。
note_echo()    { _color_print "\033[35m" "📝 $1"; }
# 输出 gray echo 对应级别的日志信息。
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
  print -r -- "" | jobs_intro_style body
  print -r -- "============================================================" | jobs_intro_style title
  print -r -- "🛠️  Hammerspoon 安装与配置脚本" | jobs_intro_style body
  print -r -- "------------------------------------------------------------" | jobs_intro_style body
  print -r -- "将执行以下操作：" | jobs_intro_style title
  print -r -- "1) 自检 Homebrew：存在则 brew update/upgrade；不存在则安装最新版" | jobs_intro_style body
  print -r -- "2) 检查 Hammerspoon：已安装则跳过；Homebrew cask 已安装则可选择升级；未安装才安装" | jobs_intro_style body
  print -r -- "3) 配置 ${HS_INIT_LUA}" | jobs_intro_style body
  print -r -- "   - 若已存在：备份为 init.lua.bak.<timestamp>" | jobs_intro_style body
  print -r -- "   - 若不存在：创建目录并新建文件" | jobs_intro_style body
  print -r -- "   - 内容来源：脚本同级目录 ${LOCAL_INIT_LUA}" | jobs_intro_style body
  print -r -- "------------------------------------------------------------" | jobs_intro_style body
  print -r -- "日志文件：${LOG_FILE}" | jobs_intro_style body
  print -r -- "脚本目录：${SCRIPT_DIR}" | jobs_intro_style body
  print -r -- "============================================================" | jobs_intro_style title
  print -r -- "" | jobs_intro_style body
}
# ================================== Homebrew：环境注入 ==================================
# 说明：为了让当前脚本能直接用 brew（尤其是 Apple Silicon 默认不在 PATH），需要注入 shellenv
ensure_brew_in_path() {
  JOBS_HOMEBREW_BIN="$(jobs_brew_find)" || return 1
  jobs_brew_activate
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

  jobs_brew_install_or_exit

  if ! ensure_brew_in_path; then
    error_echo "Homebrew 安装后仍无法在当前 shell 找到 brew。请重新打开终端后再运行本脚本。"
    exit 1
  fi

  success_echo "Homebrew 安装完成：$(command -v brew)"
}
# ================================== Homebrew：可选自检（回车跳过；输入任意字符才执行） ==================================
# 说明：
# - 无论是否跳过，都必须保证 brew 可用（否则后续无法安装 cask）
# - 直接回车：仅确保 brew 已安装并可用，不做 update/upgrade
# - 输入任意字符再回车：执行 brew update/upgrade
self_check_brew_optional() {
  install_brew_if_missing

  print -r -- ""
  note_echo "Homebrew 自检选项"
  gray_echo "直接按【回车】=> 跳过 brew update/upgrade（更快）"
  gray_echo "输入任意字符后按【回车】=> 执行 brew update/upgrade（更稳但更慢）"
  print -r -- ""

  local input
  IFS= read -r input

  if [[ -z "${input}" ]]; then
    warn_echo "已选择跳过 Homebrew 自检（update/upgrade）。"
    return 0
  fi

  info_echo "执行 brew update…"
  brew update

  info_echo "执行 brew upgrade…"
  brew upgrade || true

  success_echo "Homebrew 自检完成（update/upgrade 已执行）。"
}
# ================================== 安装 Hammerspoon（cask） ==================================
# 说明：已安装则默认跳过；输入任意字符才尝试升级；未安装才安装
is_hammerspoon_app_installed() {
  if [[ -d "/Applications/Hammerspoon.app" || -d "${HOME}/Applications/Hammerspoon.app" ]]; then
    return 0
  fi

  if command -v mdfind >/dev/null 2>&1; then
    mdfind 'kMDItemCFBundleIdentifier == "org.hammerspoon.Hammerspoon"' | grep -q '/Hammerspoon.app$' && return 0
  fi

  return 1
}
# 准备并配置 install hammerspoon 对应的运行条件。
install_hammerspoon() {
  info_echo "检查 Hammerspoon 安装状态…"

  if brew list --cask hammerspoon >/dev/null 2>&1; then
    success_echo "已检测到 Hammerspoon cask。"
    print -r -- ""
    note_echo "Hammerspoon 升级选项"
    gray_echo "直接按【回车】=> 跳过 Hammerspoon 升级"
    gray_echo "输入任意字符后按【回车】=> 执行 brew upgrade --cask hammerspoon"
    print -r -- ""

    local input
    IFS= read -r input

    if [[ -z "${input}" ]]; then
      warn_echo "已选择跳过 Hammerspoon 升级。"
      return 0
    fi

    info_echo "执行 brew upgrade --cask hammerspoon…"
    brew upgrade --cask hammerspoon || true
    success_echo "Hammerspoon 升级流程已执行。"
    return 0
  fi

  if is_hammerspoon_app_installed; then
    success_echo "已检测到本机已安装 Hammerspoon.app。"
    warn_echo "该安装未登记在 Homebrew cask 中，跳过 brew install/upgrade，避免重复安装。"
    return 0
  fi

  info_echo "未检测到 Hammerspoon，开始安装…"
  wait_for_enter "确认：开始安装 Hammerspoon？"
  brew install --cask hammerspoon
  success_echo "Hammerspoon 安装完成。"
}
# 安装依赖前校验同级配置，写入前再检查，避免文件中途被移走。
check_local_init_lua() {
  if [[ ! -f "${LOCAL_INIT_LUA}" ]]; then
    error_echo "未找到脚本同级目录的 init.lua：${LOCAL_INIT_LUA}"
    error_echo "请把 init.lua 与当前脚本放在同一目录后重试：${SCRIPT_DIR}"
    return 1
  fi
  if [[ ! -r "${LOCAL_INIT_LUA}" ]]; then
    error_echo "无法读取脚本同级目录的 init.lua：${LOCAL_INIT_LUA}"
    return 1
  fi
}
# ================================== Hammerspoon 配置：检查 init.lua（备份/新建/写入） ==================================
# 说明：
# - 检查脚本同级目录 init.lua 是否存在
# - ~/.hammerspoon/init.lua 若存在则备份；不存在则创建
# - 用同级 init.lua 覆盖写入目标
prepare_hammerspoon_init() {
  info_echo "准备配置 Hammerspoon：${HS_INIT_LUA}"
  wait_for_enter "确认：开始写入/替换 ~/.hammerspoon/init.lua？"
  check_local_init_lua || return 1

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
# ================================== Hammerspoon 配置：自动 Reload ==================================
# 说明：
# - init.lua 写入完成后自动让 Hammerspoon 重新加载配置
# - 如果 Hammerspoon 正在运行：执行 hs.reload()
# - 如果 Hammerspoon 未运行：启动 Hammerspoon，启动时会自动加载 ~/.hammerspoon/init.lua
reload_hammerspoon_config() {
  info_echo "准备自动 Reload Hammerspoon 配置…"

  if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
    if command -v osascript >/dev/null 2>&1; then
      osascript <<'APPLESCRIPT' >/dev/null 2>&1
      tell application "Hammerspoon"
        execute lua code "hs.reload()"
      end tell
APPLESCRIPT
      success_echo "Hammerspoon 已自动 Reload 配置。"
      return 0
    fi

    warn_echo "未找到 osascript，无法自动 Reload。请手动点击菜单栏锤子图标 -> Reload Config。"
    return 0
  fi

  warn_echo "Hammerspoon 当前未运行，将启动 Hammerspoon。"

  if open -b "org.hammerspoon.Hammerspoon" >/dev/null 2>&1; then
    success_echo "Hammerspoon 已启动，并会加载最新 init.lua。"
    return 0
  fi

  if open -a "Hammerspoon" >/dev/null 2>&1; then
    success_echo "Hammerspoon 已启动，并会加载最新 init.lua。"
    return 0
  fi

  warn_echo "未能自动启动 Hammerspoon。请手动打开 Applications -> Hammerspoon。"
}
# ================================== 提示：如何生效 ==================================
post_steps() {
  print -r -- ""
  success_echo "全部完成 ✅"
  note_echo "提示："
  gray_echo "1) init.lua 已写入，脚本已尝试自动 Reload Hammerspoon"
  gray_echo "2) 首次使用请在 系统设置 -> 隐私与安全性 -> 辅助功能 中允许 Hammerspoon"
  print -r -- ""
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】💉Hammerspoon配置注入.command' | jobs_intro_style title
  print -r -- '核心用途：执行“💉Hammerspoon配置注入”对应的本机环境配置任务。' | jobs_intro_style body
  print -r -- '影响范围：可能安装、更新或修改当前用户的工具链与配置文件。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- "日志文件：${LOG_FILE}" | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# ================================== 主流程：收口执行入口 ==================================
# 初始化 Shell 选项和本次运行日志。
initialize_script_runtime() {
  set -euo pipefail
  setopt NO_NOMATCH
  : "${NO_COLOR:=1}"
  : > "${LOG_FILE}"
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait || return 1 # 打印内置自述并等待回车，取消或无交互时停止。
  initialize_script_runtime # 确认后设置运行选项并初始化日志。
  print_intro # 展示实际源文件、目标文件和依赖处理策略。
  wait_for_enter "确认：我已了解脚本用途，继续执行？" # 确认具体配置影响后继续。
  check_local_init_lua # 先校验脚本同级配置，缺失或不可读时停止安装。
  self_check_brew_optional # 确保 Homebrew 可用，并按选择执行更新。
  install_hammerspoon # 检查应用状态，按需安装或升级。
  prepare_hammerspoon_init # 再次校验源文件，备份并写入配置。
  reload_hammerspoon_config # 重新加载或启动应用，使配置生效。
  post_steps # 输出完成结果和系统授权提示。
}

main "$@"
