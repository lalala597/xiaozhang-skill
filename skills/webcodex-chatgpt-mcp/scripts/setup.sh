#!/usr/bin/env bash
# WebCodex × ChatGPT 一键部署脚本（分阶段）
# 用法: bash setup.sh <子命令> [参数...]
# 子命令:
#   doctor                        环境体检
#   install                       安装 webcodex + ripgrep
#   prepare <目录>...             检查待挂目录（git/未提交/敏感内容）
#   start-server                  初始化并启动 Server
#   create-pairing <用户名>       生成一次性配对码
#   login <配对码> <用户名> <allowed-root> <项目路径>...
#   start-runner                  启动 Runner
#   funnel                        Tailscale Funnel 固定公网地址（指引）
#   oauth <固定域名>              写入 OAuth 环境变量
#   create-oauth-client           OAuth client 创建指引（0.4.0 走 console UI）
#   status / stop                 状态 / 全部停止
# 所有坑的处理逻辑已内置；遇到报错先看 skill 的 references/pitfalls.md。

set -u
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY 2>/dev/null

ENVF="$HOME/.config/webcodex/webcodex.env"
DATA_DIR="$HOME/.local/share/webcodex"
LOG_DIR="$DATA_DIR/logs"
SERVER_URL="http://127.0.0.1:8080"
PORT=8080
OK='\033[32m[OK]\033[0m'; FAIL='\033[31m[FAIL]\033[0m'; WARN='\033[33m[注意]\033[0m'

# 动态定位 webcodex 原生二进制（坑 1：npm 包装层有 bug，必须用 vendor/bin）
find_wcx() {
  local p1="$HOME/.local/lib/node_modules/@yyjeqhc/webcodex/vendor/bin/webcodex"
  local npm_root; npm_root="$(npm root -g 2>/dev/null || true)"
  local p2="${npm_root:+$npm_root/@yyjeqhc/webcodex/vendor/bin/webcodex}"
  if [ -x "$p1" ]; then echo "$p1"; elif [ -n "$p2" ] && [ -x "$p2" ]; then echo "$p2"; else echo ""; fi
}
WCX="$(find_wcx)"
mkdir -p "$LOG_DIR" "$DATA_DIR"

banner() { echo ""; echo "================ $1 ================"; }

cmd_doctor() {
  banner "环境体检"
  local fail=0
  # OS / 架构
  local os arch; os="$(uname -s)"; arch="$(uname -m)"
  if [ "$os" = "Darwin" ]; then echo -e "$OK macOS ($arch) — 本 Skill 已实测平台"; else echo -e "$WARN $os ($arch) — macOS 以外平台流程未验证，Windows 官方支持 server init/run/tunnel 但无脚本保障"; fi
  # Node
  if command -v node >/dev/null 2>&1; then
    local nv; nv="$(node -v | sed 's/v//' | cut -d. -f1)"
    if [ "$nv" -ge 18 ] 2>/dev/null; then echo -e "$OK Node.js $(node -v)"; else echo -e "$FAIL Node.js 版本过低（需 18+），去 https://nodejs.org 装 LTS"; fail=1; fi
  else echo -e "$FAIL 未安装 Node.js 18+，去 https://nodejs.org 装 LTS 后重跑"; fail=1; fi
  # npm
  command -v npm >/dev/null 2>&1 && echo -e "$OK npm $(npm -v)" || { echo -e "$FAIL 缺 npm（随 Node 安装）"; fail=1; }
  # git
  command -v git >/dev/null 2>&1 && echo -e "$OK git $(git --version | awk '{print $3}')" || { echo -e "$FAIL 缺 git（brew install git 或 Xcode CLT）"; fail=1; }
  # ripgrep（坑 2）
  if command -v rg >/dev/null 2>&1 || [ -x "$HOME/.local/bin/rg" ]; then echo -e "$OK ripgrep 已安装"; else echo -e "$WARN 缺 ripgrep —— 不装的话 ChatGPT 搜索会报错并退化成纯文本回答（install 子命令会装）"; fi
  # 端口
  if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then echo -e "$WARN 端口 $PORT 已被占用（可能 Server 已在跑，status 看看）"; else echo -e "$OK 端口 $PORT 空闲"; fi
  # 代理（坑 3）
  if [ -n "${http_proxy:-}${https_proxy:-}${all_proxy:-}" ]; then echo -e "$WARN 检测到代理环境变量 —— 脚本已自动绕开；你自己在终端跑命令时也要先 unset"; fi
  echo ""
  [ $fail -eq 0 ] && echo "体检完成，可以继续 install" || echo "存在 FAIL 项，先修复再继续"
  return $fail
}

cmd_install() {
  banner "安装 WebCodex + ripgrep"
  # webcodex
  if [ -n "$WCX" ]; then echo -e "$OK WebCodex 已安装: $WCX"; else
    echo "→ npm 全局安装 @yyjeqhc/webcodex ..."
    npm install -g @yyjeqhc/webcodex || { echo -e "$FAIL npm 安装失败"; return 1; }
    WCX="$(find_wcx)"
    [ -n "$WCX" ] && echo -e "$OK WebCodex 安装完成（原生二进制: $WCX）" || { echo -e "$FAIL 安装后仍找不到 vendor/bin 二进制，手动查 npm root -g"; return 1; }
  fi
  "$WCX" --version 2>/dev/null | sed 's/^/  版本: /'
  # ripgrep（坑 2）
  if command -v rg >/dev/null 2>&1 || [ -x "$HOME/.local/bin/rg" ]; then echo -e "$OK ripgrep 已存在，跳过"; return 0; fi
  echo "→ 下载 ripgrep 官方二进制 ..."
  local os arch tg rgdir
  os="$(uname -s)"; arch="$(uname -m)"
  if [ "$os" != "Darwin" ]; then echo -e "$WARN 非 macOS，请用系统包管理器装 ripgrep（apt install ripgrep / choco install ripgrep）"; return 0; fi
  if [ "$arch" = "arm64" ]; then tg="aarch64-apple-darwin"; else tg="x86_64-apple-darwin"; fi
  rgdir="ripgrep-14.1.1-$tg"
  curl -sL -o /tmp/rg.tgz "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-$tg.tar.gz" \
    && tar -xzf /tmp/rg.tgz -C /tmp && mkdir -p "$HOME/.local/bin" \
    && cp "/tmp/$rgdir/rg" "$HOME/.local/bin/rg" && rm -rf "/tmp/$rgdir" /tmp/rg.tgz \
    && echo -e "$OK ripgrep 装到 ~/.local/bin/rg（装完 Server 后启动时 PATH 需包含它）" \
    || echo -e "$FAIL ripgrep 下载失败，手动装后再继续"
}

cmd_prepare() {
  banner "待挂目录检查（此步 = 授权 AI 读这些目录，务必已获用户逐个确认）"
  [ $# -eq 0 ] && { echo "用法: setup.sh prepare <目录>..."; return 1; }
  for d in "$@"; do
    echo ""
    echo "▸ $d"
    if [ ! -d "$d" ]; then echo -e "$FAIL 目录不存在"; continue; fi
    if [ ! -d "$d/.git" ]; then
      echo -e "$WARN 不是 Git 仓库 → 现状是 fail-closed：AI 只能读不能写"
      echo "  需要写入能力？执行: git -C \"$d\" init && git -C \"$d\" add -A && git -C \"$d\" commit -m init"
      echo "  注意嵌套 git 仓库的目录不要在外层 init（pitfalls.md 坑 5d）"
    else
      echo -e "$OK Git 仓库"
      git -C "$d" config --get remote.origin.url >/dev/null 2>&1 && echo "  远端: $(git -C "$d" remote get-url origin)" || echo "  远端: 无（纯本地，可接受）"
    fi
    local dirty; dirty="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${dirty:-0}" -gt 0 ]; then
      echo -e "$FAIL 有 $dirty 个未提交文件 —— 未提交的改动不在写入保护链里，accept 时可能被覆盖（坑 5）"
      echo "  先提交: git -C \"$d\" add -A && git -C \"$d\" commit -m \"快照：挂载到 AI 前\""
    else echo -e "$OK 工作区干净"; fi
    echo "  ⚠ 提醒用户：确认目录内无个人日记/他人聊天记录/硬编码密钥后再挂载"
  done
}

cmd_start-server() {
  banner "启动 Server"
  [ -z "$WCX" ] && { echo -e "$FAIL 先跑 install"; return 1; }
  if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then echo -e "$OK 端口 $PORT 已有服务在监听，跳过启动"; return 0; fi
  # server init（幂等；8 个环境变量来自 env 文件）
  "$WCX" server init --listen 127.0.0.1:$PORT --data-dir "$DATA_DIR" --env-file "$ENVF" --json >/dev/null 2>&1 \
    || echo -e "$WARN server init 返回非零（首次运行属正常，继续）"
  # 后台启动。注意坑 7：agent 沙箱会回收 nohup 进程
  echo "→ 后台启动 Server（日志: $LOG_DIR/server.log）"
  if [ -n "${CODEBUDDY_SESSION_ID:-}" ] || [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    echo -e "$WARN 当前在 agent 沙箱内：请用 Bash 工具的 run_in_background 方式执行下面这行，"
    echo "  否则进程几分钟后会被沙箱回收（表现为 8080 拒连、Funnel 报 502）："
    echo "  exec \"$WCX\" server run --env-file \"$ENVF\" >> \"$LOG_DIR/server.log\" 2>&1"
    return 0
  fi
  nohup "$WCX" server run --env-file "$ENVF" >> "$LOG_DIR/server.log" 2>&1 &
  sleep 4
  if curl -s -o /dev/null --max-time 3 "$SERVER_URL/"; then echo -e "$OK Server 已启动 ($SERVER_URL)"
  else echo -e "$FAIL 启动失败，查看: tail -30 $LOG_DIR/server.log"; return 1; fi
}

cmd_create-pairing() {
  banner "生成一次性配对码"
  [ -z "${1:-}" ] && { echo "用法: setup.sh create-pairing <用户名>"; return 1; }
  [ -z "$WCX" ] && { echo -e "$FAIL 先跑 install"; return 1; }
  # 配对码 15 分钟有效、一次性；打印出来立刻用
  "$WCX" pairing create --server-url "$SERVER_URL" --env-file "$ENVF" --username "$1" --ttl-secs 900 2>&1
}

cmd_login() {
  banner "项目机器登录 + 注册项目"
  [ $# -lt 4 ] && { echo "用法: setup.sh login <配对码> <用户名> <allowed-root父目录> <项目路径>..."; return 1; }
  local code="$1" user="$2" root="$3"; shift 3
  "$WCX" login "$SERVER_URL" --code "$code" --device "$(hostname -s)" \
    --allowed-root "$root" --project "$1" --print-mcp-config 2>&1
  shift
  local cfg; cfg="$HOME/.config/webcodex/http_127.0.0.1_${PORT}/${user}/runner.toml"
  for p in "$@"; do
    echo "→ 追加注册项目: $p"
    "$WCX" project register --config "$cfg" "$p" 2>&1
  done
  echo -e "$OK 登录完成。Runner 配置: $cfg"
  echo "  MCP 地址（给 Codex/CLI 用 Bearer 时）见上方 print-mcp-config 输出"
}

cmd_start-runner() {
  banner "启动 Runner"
  local user="${1:-}"; [ -z "$user" ] && { echo "用法: setup.sh start-runner <用户名>"; return 1; }
  local cfg="$HOME/.config/webcodex/http_127.0.0.1_${PORT}/${user}/runner.toml"
  [ -f "$cfg" ] || { echo -e "$FAIL 找不到 $cfg，先 login"; return 1; }
  echo "→ 后台启动 Runner（日志: $LOG_DIR/runner.log）"
  if [ -n "${CODEBUDDY_SESSION_ID:-}" ] || [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    echo -e "$WARN agent 沙箱内：用 run_in_background 执行:"
    echo "  exec \"$WCX\" runner run --config \"$cfg\" >> \"$LOG_DIR/runner.log\" 2>&1"
    return 0
  fi
  nohup "$WCX" runner run --config "$cfg" >> "$LOG_DIR/runner.log" 2>&1 &
  sleep 3 && echo -e "$OK Runner 已启动（坑 8：重启 Server 不用动它，会自动重连）"
}

cmd_funnel() {
  banner "Tailscale Funnel 固定公网地址"
  cat <<'EOF'
前提：已安装 Tailscale 并登录（免费套餐够用，https://tailscale.com）。
方式一（App）：菜单栏 Tailscale 图标 → Settings → Funnel → 开启，指向 http://127.0.0.1:8080
方式二（CLI）：tailscale funnel --bg 8080
开启后域名形如 https://<机器名>.< tailnet >.ts.net —— 这个就是「固定公网域名」，
后续 oauth 子命令和 ChatGPT 里都填它 + /mcp。
注意（坑 6/11）：如果之前用过 Cloudflare 临时隧道，务必先杀掉全部 cloudflared 进程，
否则新旧 issuer 冲突会让 ChatGPT 报 "does not implement OAuth"。
EOF
  pgrep -f cloudflared >/dev/null 2>&1 && echo -e "$WARN 检测到 cloudflared 仍在运行 —— pkill -f 'cloudflared tunnel'" || echo -e "$OK 无旧隧道残留"
  pgrep -f Tailscale >/dev/null 2>&1 && echo -e "$OK Tailscale 在运行" || echo -e "$WARN 未检测到 Tailscale 进程"
}

cmd_oauth() {
  banner "写入 OAuth 环境变量"
  [ -z "${1:-}" ] && { echo "用法: setup.sh oauth <固定域名，如 https://xxx.ts.net>"; return 1; }
  local domain="${1%/}"
  mkdir -p "$(dirname "$ENVF")"
  touch "$ENVF"
  # 幂等写入/更新四行
  for kv in \
    "WEBCODEX_PUBLIC_URL=$domain" \
    "WEBCODEX_OAUTH2_ENABLED=true" \
    "WEBCODEX_OAUTH2_ISSUER=$domain" \
    "WEBCODEX_OAUTH2_SHARED_KEY_BRIDGE=true"; do
    local key="${kv%%=*}"
    if grep -q "^${key}=" "$ENVF" 2>/dev/null; then
      sed -i.bak "s|^${key}=.*|${kv}|" "$ENVF" && rm -f "$ENVF.bak"
    else echo "$kv" >> "$ENVF"; fi
  done
  echo -e "$OK 已写入 $ENVF："
  grep -E "^WEBCODEX_(PUBLIC_URL|OAUTH2)" "$ENVF" | sed 's/^/  /'
  echo "→ 需要重启 Server 生效（stop 后重新 start-server）。"
  echo "→ 验证发现端点（重启后）："
  echo "  curl -s https://${domain#https://}/.well-known/oauth-protected-resource   # 应 200"
}

cmd_create-oauth-client() {
  banner "创建 OAuth Client（0.4.0 无 CLI 命令，走 console 网页）"
  cat <<'EOF'
1. 浏览器打开 http://127.0.0.1:8080/console （或固定域名 /console）
2. 找到 OAuth 客户端管理 → 创建新客户端：
   - Callback URL 必须填: https://chatgpt.com/connector_platform_oauth_redirect
   - 允许 scopes: 全部勾选（除 offline_access —— WebCodex 不支持，勾了会报 invalid scope）
3. 保存后得到 Client ID（wc_client_...）和 Client Secret（wc_csec_...）
   ⚠ Secret 只显示一次（服务端只存哈希），丢了只能撤销重建；别贴群、别进 git。
4. ChatGPT 端填法见 references/chatgpt-oauth.md 第四节。
EOF
}

cmd_status() {
  banner "状态"
  curl -s -o /dev/null -w "" --max-time 2 "$SERVER_URL/" 2>/dev/null \
    && echo -e "$OK Server: $SERVER_URL" || echo -e "$FAIL Server 未运行"
  [ -n "$WCX" ] && "$WCX" server status --env-file "$ENVF" 2>/dev/null | grep -Ei "runner" | sed 's/^/  /'
  [ -f "$LOG_DIR/current-url.txt" ] && echo "  公网地址: $(cat "$LOG_DIR/current-url.txt")"
  command -v rg >/dev/null 2>&1 || [ -x "$HOME/.local/bin/rg" ] || echo -e "$WARN ripgrep 未装（坑 2）"
}

cmd_stop() {
  banner "全部停止（AI 立刻断线，文件不受影响）"
  pkill -f "cloudflared tunnel" 2>/dev/null
  pkill -f "webcodex.*runner run" 2>/dev/null; pkill -f "webcodex-runner" 2>/dev/null
  pkill -f "webcodex.*server run" 2>/dev/null; pkill -f "webcodex-server" 2>/dev/null
  sleep 2; echo "已停止。重新上线：start-server → start-runner"
}

case "${1:-}" in
  doctor) cmd_doctor ;;
  install) cmd_install ;;
  prepare) shift; cmd_prepare "$@" ;;
  start-server) cmd_start-server ;;
  create-pairing) shift; cmd_create-pairing "$@" ;;
  login) shift; cmd_login "$@" ;;
  start-runner) shift; cmd_start-runner "$@" ;;
  funnel) cmd_funnel ;;
  oauth) shift; cmd_oauth "$@" ;;
  create-oauth-client) cmd_create-oauth-client ;;
  status) cmd_status ;;
  stop) cmd_stop ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
