# 已踩过的坑（全部实测，共 13 个）

按部署阶段排列。出现报错先来这里对号入座，每个坑都给出已验证的解法。

## 安装阶段

**坑 1：npm 包装层 bug**
`webcodex` 命令带路径参数（如 `--env-file X`）时报 `node: X: not found`。
→ 一律使用原生二进制：`~/.local/lib/node_modules/@yyjeqhc/webcodex/vendor/bin/webcodex`（setup.sh 已封装）。

**坑 2：ripgrep 缺失 → ChatGPT 退化成"只会聊天"**
`search_project_text` 报 `"ripgrep is required for the requested search_project_text features"`。ChatGPT 收到工具报错后往往不再重试，直接变成纯文本回答——用户会误以为"没有 Agent 能力"。
→ 装 ripgrep 到 PATH：macOS 无 brew 时直接下官方二进制（setup.sh install 已处理）。装完**必须重启 Server**（PATH 是启动时继承的）。验证：tools/call 返回 `"backend":"rg"`。
版本参考：ripgrep 14.1.1，Apple Silicon 用 `aarch64-apple-darwin.tar.gz`。

**坑 3：本地代理（Clash 等）拦截本机通信**
代理进程监听本机时，`127.0.0.1:8080` 的通信可能被劫持，表现为各种诡异的连接失败。
→ 启动/测试前 `unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY`（setup.sh 已内置）。

## Git 准备阶段

**坑 4：非 Git 目录无法建立写入隔离（fail closed）**
worktree 隔离依赖 Git。非 Git 目录注册后**只能读不能写**（不会退化成直写，这是安全设计）。
→ 挂载前 `git init` + 首次 commit。想要写入能力的目录必须过这关。

**坑 5：未提交的改动不在保护链里**
worktree 从某个 commit 切出，主目录里尚未 commit 的修改不会出现在副本中，accept 时可能被覆盖或冲突。Git 也救不回没提交过的东西。
→ 挂载前对每个目录跑一轮 commit（prepare 阶段脚本会检查并提示）。

**坑 5b：陈旧 index.lock**
git 操作被中途杀死（如沙箱回收进程）会留下 `.git/index.lock`，下一次 git 操作报 "File exists"。
→ 确认无并发 git 进程后 `rm -f .git/index.lock`。

**坑 5c：macOS 的 `com.apple.macl` 目录无法 git init**
直接 `git init` 报 unlink config.lock 被拒（`项目资产` 目录实测中过）。
→ 绕法：在别处 `git init`，再把整个 `.git` 目录拷过去。

**坑 5d：嵌套 git 仓库**
外层目录 `git add -A` 会把内嵌的子仓库加成 gitlink，内容不进库。
→ 目录里已有嵌套 git 仓库时，不要在外层建库，逐个子仓库单独处理。

## 运行阶段

**坑 6：Cloudflare 临时隧道地址每次重启都变**
`trycloudflare.com` 的 URL 每次重启全换，ChatGPT 里的 MCP URL 必须手动跟着改。
→ 要固定地址用 Tailscale Funnel（免费，`*.ts.net` 域名）。注意：旧隧道和新 Funnel 并存时，两套 issuer 元数据冲突会让 ChatGPT 报 "does not implement OAuth"——切换后必须杀掉旧 cloudflared 进程。

**坑 7：macOS 不支持 `runner install`**
systemd 服务命令只有 Linux 支持。macOS 常驻靠 nohup / launchd / 由 agent 的后台任务托管。
→ 另注意：某些 agent 沙箱会回收 `nohup ... &` 启动的后台进程——Server 看似启动成功，几分钟后悄悄消失（端口拒绝连接、Funnel 报 502）。用 Bash 工具的 run_in_background 托管，或让用户在真实终端里跑。

**坑 8：重启 Server 不需要动隧道和授权**
Tailscale Funnel 是系统级服务，只转发 `127.0.0.1:8080`；Server 重启后 Funnel 自动恢复，ChatGPT 的 OAuth 授权也仍然有效。不知道这点的人会白白重配一遍。

## 使用阶段

**坑 9：ChatGPT 闲聊式提问不触发工具**
ChatGPT 网页端连接器是"模型自主决定调不调工具"。问"你觉得我的知识库怎么样"它就用自己的知识闲聊。
→ 教用户下明确指令："在我的 XX 库里搜索 X 并引用原文" / "列出你能看到的项目"。调用时回复里会出现"正在调用 xxx"的折叠提示。

**坑 10：模型编造 FORBIDDEN（幻觉式自我合理化）**
实测出现过：ChatGPT 声称"写库返回 FORBIDDEN"，但服务端审计表（`action_events`）里当天零记录、全库零 FORBIDDEN——它根本没发请求。它还编造过不存在的项目名（"小张数据库"）。
→ 诊断法见 `chatgpt-oauth.md` 的「FORBIDDEN 幻觉诊断」节。审计表是唯一真相。

**坑 11：旧 Cloudflare 隧道残留导致 OAuth 元数据冲突**
"获取 OAuth 配置时出错... does not implement OAuth" 的真实原因之一：旧隧道的 issuer 与新固定域名不一致。
→ 杀掉全部 cloudflared 进程，只留一条通往 Server 的路。

**坑 12：Server 死了 4 天没人发现 → ChatGPT 报"连不上你的账号"**
症状：ChatGPT 报 `We couldn't connect your account. Please try again.`，连接器调不通。**这次是真的，不是模型编的**（区别于坑 10）。
根因排查顺序（别跳步）：
1. `lsof -nP -iTCP:8080 -sTCP:LISTEN` 空 → Server 没了（最常见）
2. 公网 `curl -o /dev/null -w "%{http_code}" https://<域名>/` → **502 = 隧道通、回源死**；超时/DNS 失败 = Funnel 自身问题
3. `tail -3 ~/.local/share/webcodex/logs/server.log` 看最后时间戳 → 直接知道是几号停的
4. `tail -3 .../runner.log` → runner 通常还活着并在每 30 秒重试 `Connection refused (os error 61)`，**Server 起来后它会自动重连，不用手动重启**
→ 修复只需重启 Server。注意区分两类报错：**连接类大概率为真，权限类（FORBIDDEN）大概率是编的**——两种都发生过，每次都查账本，别形成单边预期。

**坑 13：`launchctl bootstrap` 报 `Input/output error`（Agent 会话装不上自启）**
在 agent 会话里执行 `launchctl bootstrap gui/$(id -u) <plist>` 或 `launchctl load -w <plist>`，一律返回 `Bootstrap failed: 5: Input/output error`。
已排除：plist 语法（`plutil -lint` OK）、权限（644，与在用的 `ai.hermes.*` 一致）、Label 与文件名不匹配、代理干扰、沙箱（非沙箱重试同样失败）。**用 `/bin/sleep 600` 的最小 plist 测试也失败** → 环境级限制，该会话无法向 GUI 域注册服务，不是配置问题。
→ **plist 照写不误**：`~/Library/LaunchAgents/` 下的文件会在**下次登录时**被 launchd 自动扫描加载，`RunAtLoad` + `KeepAlive` 随即生效。
→ 先确认没被禁用：`launchctl print-disabled gui/$(id -u) | grep <label>`，无输出即会加载。
→ 应急：本回合先用 Bash 的 `run_in_background` 把服务跑起来（见坑 7），并告知用户下次重启后由 plist 接管。
