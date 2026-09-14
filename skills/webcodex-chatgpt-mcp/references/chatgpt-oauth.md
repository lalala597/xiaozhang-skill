# ChatGPT 端接入手册：OAuth 流程 + 故障排查

## 一、为什么必须 OAuth（一句话背景）

ChatGPT 网页端的自定义连接器**只支持 OAuth 或无认证**，没有填 Bearer token 的输入框（五个独立来源一致 + 实测：裸 token / `?token=` / 非标准头全部 401，只有标准 `Authorization: Bearer` 头返回 200）。所以要让网页版 ChatGPT 用起来，服务端必须开 OAuth。

例外：Codex CLI / IDE 扩展不走 ChatGPT 连接器界面，直接在 `~/.codex/config.toml` 里配 `http_headers = { "Authorization" = "Bearer wc_pat_..." }` 即可，**不需要 OAuth**。

## 二、前提自查（进不去连接器界面的先看这里）

- ChatGPT 套餐：需要 **Plus / Pro / Team**。免费版没有自定义连接器，无法绕过。
- **Developer Mode**：ChatGPT → 头像 → Settings → Apps & Connectors → 底部 Advanced settings → 打开 Developer Mode。没有这个开关 = 套餐或工作区不允许，WebCodex 无法绕过。

## 三、WebCodex 服务端 OAuth 配置要点

在 `webcodex.env` 里写入（setup.sh oauth 子命令会做）：

```
WEBCODEX_PUBLIC_URL=https://<固定域名>       # 必须与实际访问域名完全一致
WEBCODEX_OAUTH2_ENABLED=true
WEBCODEX_OAUTH2_ISSUER=https://<固定域名>
WEBCODEX_OAUTH2_SHARED_KEY_BRIDGE=true
```

配好后验证发现端点（都应返回 200）：
- `/.well-known/oauth-protected-resource`
- `/.well-known/oauth-authorization-server`（应含 PKCE S256、`client_secret_post`）
- 无认证访问 `/mcp` → 401 + `WWW-Authenticate: Bearer resource_metadata=...`

**关键事实：WebCodex 不支持 DCR（动态客户端注册）**。所以 ChatGPT 里必须选 **User-Defined OAuth Client（用户自定义 OAuth 客户端）**，手动填 Client ID / Secret。

创建 OAuth client 的命令（setup.sh create-oauth-client 封装了）：

```bash
$WCX tokens ...   # 或按当前版本文档；回调 URL 必须注册：
# https://chatgpt.com/connector_platform_oauth_redirect
```

Client Secret **只显示一次**（服务端只存哈希），丢了只能 revoke 重建。别贴群、别进 git。

## 四、ChatGPT 网页端逐屏操作

1. ChatGPT → 头像 → **Settings** → **Apps & Connectors**
2. 确认 Developer Mode 已开（见第二节）
3. Apps 页右上角 **Create**（创建连接器）
4. 选择 **User-Defined OAuth Client**，填写：
   - Name：随意（如"我的知识库"）
   - MCP Server URL：`https://<固定域名>/mcp`
   - Client ID：服务端输出的 `wc_client_...`
   - Client Secret：服务端输出的 `wc_csec_...`
5. 提交后 ChatGPT 会跳转到 WebCodex 的授权登录页 → 登录 → 授权页列出全部 scope → **Allow**
6. 回到 ChatGPT，连接器显示已连接、能扫出工具（`list_projects`、`read_file`、`search_project_text` 等）即成功

**关于授权页的高危 scope**：会看到 `account:manage`、`computer:control`、`ssh:local` 等。这些是 WebCodex 声明的全集；文件访问实际锁定在已注册目录内。向导 agent 必须在用户点 Allow 前如实说明（详见 risks.md），由用户自主决定。

## 五、故障排查（按症状对号）

### "does not implement OAuth" / 获取 OAuth 配置出错
→ 十有八九是**旧隧道残留**：新固定域名的 issuer 与旧临时隧道元数据冲突。杀掉全部 cloudflared 进程，只留一条通往 Server 的路径，重试。
→ 另查 `WEBCODEX_PUBLIC_URL` 是否与实际访问域名逐字符一致。

### "invalid scope"
→ OAuth client 创建时允许的 scope 太少。把允许范围扩到除 `offline_access` 外的全部声明 scope（offline_access 是协议层的，WebCodex 不在 allowlist 里支持）。

### "invalid token"（授权登录时）
→ 用户贴错了字符串。最常见：把 Client Secret 或 Client ID 当成了 PAT。PAT 以 `wc_pat_` 开头。用 `pbcopy < token文件` 放进剪贴板再贴。

### "invalid authorization request"
→ 多为 scope 问题（见上）。修正 client 允许范围后让用户重新发起授权。

### 连接器显示正常但 ChatGPT 不调用工具
→ 正常现象之一：闲聊式提问不触发工具。教用户明确指令："在我的 XX 库里搜索 X 并引用原文"。调用时回复里出现"正在调用 xxx"折叠提示。
→ 若明确指令也不触发：查服务端是否有请求进来（见下节）。

### FORBIDDEN 幻觉诊断（重要！）

用户转述"ChatGPT 说被 FORBIDDEN / 没有权限 / 无法访问"时，**先查服务端审计，别信模型的转述**：

```bash
# 1. 最近 20 小时失败/异常调用
sqlite3 -readonly ~/.local/share/webcodex/webcodex.db \
  "SELECT datetime(started_at,'unixepoch','+8 hours'), action_name, project, status, substr(error_summary,1,200) \
   FROM action_events WHERE started_at > strftime('%s','now','-20 hours') \
   AND (status!='success' OR error_summary!='') ORDER BY started_at DESC LIMIT 20;"

# 2. 全库搜 FORBIDDEN（本项目实测结果：零命中 = 模型编造）
sqlite3 -readonly ~/.local/share/webcodex/webcodex.db \
  "SELECT count(*) FROM action_events WHERE error_summary LIKE '%orbid%';"

# 3. 最近调用总览（看 ChatGPT 到底发没发请求、调了什么工具）
sqlite3 -readonly ~/.local/share/webcodex/webcodex.db \
  "SELECT datetime(started_at,'unixepoch','+8 hours'), \
     json_extract(summary_json,'\$.model_ergonomics.tool_name'), project, status \
   FROM action_events WHERE action_name='toolsCall' ORDER BY started_at DESC LIMIT 25;"
```

判读：
- **审计里有记录且 success** → 链路通，AI 真的读到了。模型转述与事实不符时以审计为准。
- **审计里有记录但 failed** → 真 bug，按 error_summary 对号 pitfalls.md。
- **零记录** → 模型根本没发请求，"被拒绝"是它编的。实测案例：它声称写库 FORBIDDEN（当天服务端零记录），还编造了不存在的项目名。对策：给用户一段纠正话术，点名真实项目名和真实工具名（写文件用 `apply_patch`），要求它"报真实错误而不是说被拒绝"。

### 写入流程说明（用户问"写的东西去哪了"）

AI 的编辑（apply_patch 等）落在隔离 worktree，生成待审 task：

```bash
$WCX task list            # 看待审改动（含 diff）
$WCX task accept <编号>   # 确认 → 真正落盘
$WCX task reject <编号>   # 拒绝 → 副本丢弃，原库零改动
```

## 六、第一句话怎么问（验收话术）

```
用连接器列出你能看到的项目，然后告诉我每个项目里大概有什么。不要修改任何文件。
```

能列出项目并描述内容 = 端到端全通。之后再逐步放开写权限。
