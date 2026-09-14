---
name: webcodex-chatgpt-mcp
description: 把本地 Obsidian 知识库（或任意本地目录）通过 WebCodex 暴露成公网 MCP，接入 ChatGPT 网页端 / Codex CLI。面向零基础用户的完整部署向导：讲解原理、前提条件、风险告知、分步安装、OAuth 配置、验收测试与撤销方法。已实测平台 macOS（arm64/x64），Windows 有官方二进制但未验证。触发词：webcodex、知识库接ChatGPT、本地 MCP、让 ChatGPT 读写我的 Obsidian、ChatGPT 连接器、给 GPT 挂知识库。
agent_created: true
---

# WebCodex × ChatGPT：本地知识库接入向导

本 Skill 是一个**向导剧本**：执行它的 agent 要扮演"技术向导"，带着一个可能完全不懂的用户，从零把 WebCodex 部署起来并接入 ChatGPT。全程分阶段推进，每个阶段先解释再动手，重要决策必须用户确认。

## 你（向导 agent）必须遵守的节奏

1. **禁止一上来就敲命令**。第一次触发时，先按下面的「第 0 步」向用户讲解，等用户明确说"开始"再动手。
2. **不可逆/高危动作前必须停下确认**：挂载目录（等于授权 AI 读它）、开启 OAuth、创建 OAuth client。列出具体路径再问。
3. **每完成一个阶段，用一句话告诉用户发生了什么、下一步是什么**。不要倾倒技术细节。
4. 所有命令一律使用 skill 自带脚本 `scripts/setup.sh` 和 `scripts/verify.sh`，不要现编命令——每一个坑都已埋在脚本的处理逻辑里。
5. 遇到失败：先查 `references/pitfalls.md`（13 个已踩过的坑），再查 `references/chatgpt-oauth.md` 的故障排查节。不要凭猜测重试超过 2 次。
6. 用户质疑"ChatGPT 怎么不干活/被拒绝"时：先跑 `references/chatgpt-oauth.md` 里的「FORBIDDEN 幻觉诊断」，用服务端审计分清是工具报错还是模型编造。
7. **报错分流：先查后端，再怀疑模型。** 模型报错有两类，处理方向相反——
   - **连接类**（"连不上你的账号""We couldn't connect your account"、工具列表为空）→ **大概率是真的**。先查 8080 存活，再查 Funnel，最后才怀疑 ChatGPT 侧。
   - **权限类**（"被 FORBIDDEN""没有权限"）→ **大概率是编的**。先查审计表有没有真实请求记录。
   两类都会发生，不要形成单边预期。

## 第 0 步：向用户讲解（未确认前不动手）

用大白话向用户讲清以下四件事，允许展开成对话，但四个点都要覆盖：

**① 这是什么、装完能得到什么**
"把你电脑上的 Obsidian 知识库（或任何文件夹）变成 ChatGPT 能直接查阅和（经你批准后）修改的东西。装完后你在 ChatGPT 网页里就能说『在我的第二大脑里搜一下 XX』，它会真去搜你的文件并引用原文，而不是瞎编。多步任务（连续查好几个库、写文档草稿）建议配合 Codex CLI 使用。"

**② 前提条件（逐条核对，缺哪条告诉用户怎么办）**
- ChatGPT **Plus / Pro / Team** 套餐（免费版没有自定义连接器入口，无法绕过）
- ChatGPT 设置里能开启 **Developer Mode**（Apps & Connectors → Advanced settings）
- 一台 Mac（本 Skill 已实测 macOS；Windows 有官方二进制但流程未验证，需自行探索）
- Node.js 18+（没有也没关系，脚本会指路）
- 一批**已经是 Git 仓库**（或愿意被 git init）的待挂目录
- 可选：Tailscale 免费账号（要固定公网地址时用；不装则每次重启换地址）

**③ 风险告知（读 `references/risks.md` 后用其中「30 秒版本」讲，用户追问再展开）**
核心三条：挂上的库 AI 能**全量读**（读不走隔离，回退救不了已读走的内容）；AI 写入有双保险（隔离副本 + 你本机 accept 才落盘）；但命令执行类工具（run_shell）是逃生口，保护弱于文件编辑。OAuth 授权页可能勾出高危 scope，授权后有撤销开关。

**④ 隐私劝退检查（必须问）**
"你打算挂的目录里有没有：个人日记/叙事、别人的聊天记录、录音转写？" 有 → 建议先不挂这些目录，或明确接受风险再继续。列出用户给的目录清单，逐个确认后才进入安装。

## 第 1 步：环境体检

```bash
bash <skill目录>/scripts/setup.sh doctor
```

全绿 → 进入第 2 步。有红 → 按脚本输出修复（Node 缺失给用户装法；代理在跑则脚本已自动绕开）。

## 第 2 步：安装 WebCodex 与 ripgrep

```bash
bash <skill目录>/scripts/setup.sh install
```

装两个东西：WebCodex 本体（npm 包，含原生二进制）和 ripgrep（搜索工具，缺它 ChatGPT 的搜索调用会报错并退化成纯文本回答——真实踩过的坑）。

## 第 3 步：准备待挂目录（高危，逐个确认）

```bash
bash <skill目录>/scripts/setup.sh prepare "<目录1>" "<目录2>"
```

脚本会检查每个目录：是否 Git 仓库（不是则问用户是否 git init——非 Git 目录 fail-closed，AI 只能读不能写）、是否有未提交改动（未提交的文件**不在写入保护链里**，accept 时可能被覆盖，必须先 commit）、提示扫描敏感内容。**这一步等于把目录授权给 AI 读，挂之前逐个向用户确认。**

## 第 4 步：启动服务 + 注册项目

```bash
bash <skill目录>/scripts/setup.sh start-server
bash <skill目录>/scripts/setup.sh create-pairing <用户名>
# 脚本打印 wc_pair_ 开头的一次性配对码，15 分钟有效，立刻用：
bash <skill目录>/scripts/setup.sh login <配对码> <用户名> <allowed-root父目录> "<项目路径>"
bash <skill目录>/scripts/setup.sh start-runner
```

向用户解释：Server 是大门，Runner 是只认已注册目录的搬运工，配对码用一次就作废。

## 第 5 步：公网入口（二选一，向用户说明差别后让他选）

- **方案 A（推荐）：Tailscale Funnel 固定地址**。免费，地址永不变。需要用户装 Tailscale 登录，然后脚本开启 Funnel。ChatGPT 里配置一次以后不用再动。
- **方案 B：Cloudflare 临时隧道**。零账号零安装，但**每次重启地址都变**，ChatGPT 里的 URL 要跟着改。适合先试跑 10 分钟验证价值。

```bash
bash <skill目录>/scripts/setup.sh funnel    # 方案 A
# 方案 B 使用 cloudflared，见 references/pitfalls.md 坑 6
```

## 第 6 步：OAuth（ChatGPT 网页端必经，Codex CLI 可跳过）

**先解释为什么**：ChatGPT 网页端的自定义连接器**只支持 OAuth**，没有填 token 的地方（五个独立来源核实过，实测四种传法只有标准 Bearer 头能过）。Codex CLI / IDE 不受此限，可直接 Bearer。

```bash
bash <skill目录>/scripts/setup.sh oauth <固定公网域名>
bash <skill目录>/scripts/setup.sh create-oauth-client
```

脚本输出 Client ID / Client Secret。**警告用户：Secret 只显示一次，丢了只能撤销重建；别贴群、别进 git。**

然后带用户在 ChatGPT 里操作（点击路径见 `references/chatgpt-oauth.md` 第二节，含每一屏填什么）。授权页会列出全部 scope（含 account:manage、computer:control、ssh:local 等高危项）——**这是 WebCodex 声明的全集，实际文件访问仍被锁定在已注册目录内**，但必须如实告知用户后由他决定 Allow。

## 第 7 步：验收（不许跳过）

```bash
bash <skill目录>/scripts/verify.sh <公网域名>
```

脚本做七项检查：进程、端口、ripgrep、本地 MCP 握手、公网 MCP 握手、工具列表、真实搜索调用（验证 `backend:"rg"`）。全绿后，让用户在 ChatGPT 新对话里发这句做最终验收：

> 用连接器列出你能看到的项目，然后告诉我每个项目是干什么的。

能列出 → 完成。给用户留三样东西：日常启停命令、撤销方法（见 risks.md 末节）、"ChatGPT 不干活时先来找你查审计"的预期。

## 使用阶段用户最常问的四句话（答案要点）

- **"它说连不上我的库"／"We couldn't connect your account"／连接器消失了** → **这是真的坏了，不是模型编的。** 按序查三层（每条一条命令）：
  1. `lsof -nP -iTCP:8080 -sTCP:LISTEN` —— 空 = Server 没了。**这是最常见原因**，因为 Server 是前台进程，终端一关、或它跑在 agent 沙箱里被回收，就死。
  2. `/Applications/Tailscale.app/Contents/MacOS/Tailscale funnel status` —— 应显示 `proxy http://127.0.0.1:8080`。同时 curl 公网域名：**502 = 隧道通、回源死**（即第 1 层挂了）；超时/DNS 失败 = Funnel 本身有问题。
  3. `tail -5 ~/.local/share/webcodex/logs/server.log` —— 看最后一条时间戳，就知道是几号停的。
  修法：重启 Server（见第 4 步的 `start-server`；**在 agent 沙箱内必须用 run_in_background**，否则几分钟后被回收，症状正是 8080 拒连 + Funnel 502，即坑 7）。Runner 通常还活着并在每 30 秒重试，Server 起来后会自动接上，不用重启它。
- "它只会回内容不会干活" → 八成是闲聊式提问没触发工具；教用户下明确指令（"在我的 XX 库里搜索 X 并引用原文"）；再查审计表。
- "它说被 FORBIDDEN 了" → 先查服务端审计（`references/chatgpt-oauth.md` 诊断节），本项目实测出现过模型编造 FORBIDDEN、实际请求根本没发出的情况。
- "写的内容去哪了" → 在隔离副本里，等用户本机 accept 才落盘：`webcodex task list` → `webcodex task accept <编号>`，accept 前可看完整 diff，可 reject。
