#!/usr/bin/env bash
# WebCodex 部署验收 / 压测脚本
# 用法: bash verify.sh [公网域名]
#   无参数 → 只测本机链路（5 项）
#   带域名 → 加测公网链路 + 真实搜索调用（7 项）
# 七项全绿才算部署完成。任何 FAIL 先查 references/pitfalls.md。

set -u
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY 2>/dev/null
PORT=8080
ENVF="$HOME/.config/webcodex/webcodex.env"
DOMAIN="${1:-}"
PASS=0; FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
mcp()  { # $1=url $2...=额外 curl 参数透传
  local url="$1"; shift
  curl -sS -m 15 "$@" -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}' \
    "$url" 2>/dev/null
}

echo "================ WebCodex 部署验收 ================"

# ── 1. Server 进程/端口
echo ""
echo "① Server 本地端口"
if curl -s -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/"; then ok "Server 在 127.0.0.1:$PORT 响应"
else bad "8080 无响应 → Server 没跑。查日志: tail -30 ~/.local/share/webcodex/logs/server.log"; fi

# ── 2. ripgrep（坑 2）
echo ""
echo "② ripgrep（缺它 ChatGPT 搜索会退化成纯文本）"
RG="$(command -v rg || echo "$HOME/.local/bin/rg")"
if [ -x "$RG" ] && "$RG" --version >/dev/null 2>&1; then ok "ripgrep 可用: $RG ($("$RG" --version | head -1 | awk '{print $2}'))"
else bad "ripgrep 不可用 → setup.sh install 补装，装完重启 Server"; fi

# ── 3. 本地 MCP 握手
echo ""
echo "③ 本地 MCP 握手"
TOKEN_FILE="$(ls "$HOME"/.config/webcodex/http_127.0.0.1_$PORT/*/webcodex-user-token 2>/dev/null | head -1)"
if [ -z "$TOKEN_FILE" ]; then
  bad "找不到 user token（~/.config/webcodex/http_127.0.0.1_$PORT/<user>/webcodex-user-token）→ 先完成 login"
else
  TOKEN="$(cat "$TOKEN_FILE")"
  R="$(mcp "http://127.0.0.1:$PORT/mcp" -H "Authorization: Bearer $TOKEN")"
  echo "$R" | grep -q '"name":"webcodex"' && ok "本地 initialize 成功（serverInfo: webcodex）" \
    || bad "本地握手失败: $(echo "$R" | head -c 150)"
fi

# ── 4. 公网 MCP 握手（可选）
if [ -n "$DOMAIN" ]; then
  echo ""
  echo "④ 公网 MCP 握手（${DOMAIN}）"
  R="$(mcp "${DOMAIN%/}/mcp" -H "Authorization: Bearer $TOKEN")"
  echo "$R" | grep -q '"name":"webcodex"' && ok "公网 initialize 成功（Funnel → Server 全链路通）" \
    || bad "公网握手失败: 检查 Funnel 是否开启、域名是否正确。502 = Server 挂了或端口变了（坑 7）"
fi

# ── 5. 工具清单
echo ""
echo "⑤ MCP 工具清单"
SID_HDR="$(mktemp)"
INIT_OUT="$(curl -sS -m 15 -D "$SID_HDR" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}' \
  "http://127.0.0.1:$PORT/mcp" 2>/dev/null)"
SID="$(grep -i '^mcp-session-id:' "$SID_HDR" | tr -d '\r' | awk '{print $2}')"
rm -f "$SID_HDR"
if [ -n "$SID" ]; then
  TOOLS="$(curl -sS -m 15 -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SID" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    "http://127.0.0.1:$PORT/mcp" 2>/dev/null \
    | grep -o '"name":"[a-z_]*"' | wc -l | tr -d ' ')"
  [ "${TOOLS:-0}" -ge 20 ] && ok "工具清单正常（$TOOLS 个工具，含读写与执行类）" \
    || bad "工具数量异常（$TOOLS）→ 确认 Runner 在线（runner status）"
else bad "拿不到 MCP session id → 本地握手已失败，先修 ③"; fi

# ── 6. Runner / 项目可见性
echo ""
echo "⑥ 已注册项目可见性"
PROJ="$(curl -sS -m 15 -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: ${SID:-}" \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}' \
  "http://127.0.0.1:$PORT/mcp" 2>/dev/null)"
if echo "$PROJ" | grep -q '"success":true'; then
  NAMES="$(echo "$PROJ" | grep -o '"name":"[^"]*"' | head -8 | sed 's/"name"://;s/"//g' | tr '\n' ' ')"
  ok "list_projects 成功（${NAMES:-见审计}）"
else bad "list_projects 失败 → Runner 可能掉线: pkill -f webcodex-runner 后重启，或查 runner.log"; fi

# ── 7. 真实搜索调用（验证 rg 后端，坑 2 的端到端确认）
echo ""
echo "⑦ 真实搜索调用（backend=rg）"
FIRST_PROJ="$(echo "$PROJ" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | grep -v -E '^(name)$' | head -1)"
SEARCH_ARGS="{\"project\":\"${FIRST_PROJ:-}\",\"pattern\":\"the\"}"
SEARCH="$(curl -sS -m 30 -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: ${SID:-}" \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"search_project_text\",\"arguments\":$SEARCH_ARGS}}" \
  "http://127.0.0.1:$PORT/mcp" 2>/dev/null)"
if echo "$SEARCH" | grep -q '"backend":"rg"'; then
  ok "搜索工具返回 backend=rg（端到端搜索能力正常）"
elif echo "$SEARCH" | grep -q 'ripgrep is required'; then
  bad "ripgrep 仍缺失 → 装完 rg 必须重启 Server（PATH 才会生效），重跑本脚本"
elif echo "$SEARCH" | grep -qi 'error'; then
  bad "搜索报错: $(echo "$SEARCH" | head -c 200)"
else
  bad "响应异常: $(echo "$SEARCH" | head -c 200)"
fi

# ── 汇总
echo ""
echo "================ 结果: $PASS PASS / $FAIL FAIL ================"
if [ $FAIL -eq 0 ]; then
  echo "全部通过。最后一步：让用户在 ChatGPT 新对话里发——"
  echo "  『用连接器列出你能看到的项目，然后告诉我每个项目里大概有什么。』"
  [ -n "$DOMAIN" ] || echo "（本次未测公网链路；接入 ChatGPT 网页端前用「bash verify.sh <公网域名>」补测）"
else
  echo "存在失败项，按上面提示修复后重跑。坑对照表: references/pitfalls.md"
fi
exit $FAIL
