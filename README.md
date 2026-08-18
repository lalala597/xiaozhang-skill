# 小张Skill：AI 第二大脑与认知差值工具箱

这是一套给 AI 使用的中文 Skills。它不把你的经历压成一段漂亮的人设，而是把**目标、经历、判断变化、对标和外部材料之间的差值**整理成可以追溯、可以继续验证的工作材料。

仓库：`lalala597/xiaozhang-skill`  ·  GitHub 用户名：`lalala597`

## 适合什么需求

- 想把自己的日记、经历和判断交给 AI，找出可证据化的思考方式与知识缺口
- 想搭一个轻量的「第二大脑」，但不想先把整个私人知识库无差别塞进上下文
- 想把模糊愿望变成能裁定下一步和完成/失败的目标
- 想记录自己在具体问题上的信念版本，而不是让 AI 猜「你是怎样的人」
- 想找一个能观察决策过程的对标，再拆解文章、作品、方法或仓库

## 能力清单

| 入口 | 用途 | 什么时候调用 |
|---|---|---|
| `xiaozhang` | 总入口路由 | 不确定该用哪个 Skill，或想让 AI 按当前请求选择一个 |
| `xiaozhang-narrative` | 个人叙事系统 | 「把我的经历放进 AI」「搭第二大脑」「提取我的思考方式」 |
| `xiaozhang-goal` | 目标翻译器 | 目标、个人 IP 或任务仍在空转 |
| `xiaozhang-belief` | 信念状态库 | 记录/修订「我现在相信什么」及其边界 |
| `xiaozhang-benchmark` | 对标定位器 | 找可观察、可模仿且与目标同向的样本 |
| `xiaozhang-absorb` | 认知差值探测器 | 吸收外部文章、作品、方法、课程或仓库 |
| `xiaozhang-principles` | 五步流程决策工具 | 「我卡住了」「推不动」「拿不准」「帮我诊断一下」 |

入口只选择一个最匹配的按需 Skill。没有匹配时会明确说没有匹配，不会假装有一个万能 AI。

## 安装

在支持 Skills 的终端执行：

```bash
npx -y skills add lalala597/xiaozhang-skill -g --all
```

这会安装入口和全部按需 Skills。只想手动安装时，也可以克隆这个仓库，然后把 `skills/` 下需要的目录复制到你的 Agent 的 Skills 目录：

```bash
git clone https://github.com/lalala597/xiaozhang-skill.git
```

国内网络访问 GitHub 慢时，用加速镜像克隆：

```bash
git clone https://ghproxy.net/https://github.com/lalala597/xiaozhang-skill.git
```

不要把自己的日记、Obsidian 私人目录、凭证或聊天记录复制进这个公开仓库。安装的是规则，个人材料仍留在你自己的环境里。

## 最短用法

安装后直接把真实请求交给入口：

```text
/xiaozhang 我有一批自己的经历记录，想知道哪些判断方式是反复出现的。
```

也可以直接调用一个能力：

```text
/xiaozhang-narrative 只读我提供的这批记录，提取判断变化和知识缺口。
/xiaozhang-goal 我想做个人 IP，但还说不清做到什么算完成。
/xiaozhang-absorb 帮我拆解这个仓库，找出我和作者判断不同的地方。
/xiaozhang-principles 这件事我推了两个月没进展，帮我诊断卡在哪。
```

Codex、Claude Code 和其他支持 Skills 的客户端通常可以用 `/xiaozhang` 或客户端对应的 Skill 语法；Hermes、豆包、Trae 等通用 Agent 需要把 `skills/` 目录放进它们的 Skills 搜索路径，再告诉它「使用 `xiaozhang` 入口」。不同客户端的自动发现规则可能不同，仓库不承诺替客户端完成安装或保证每个模型自动调用。

## 一条管线

```text
当前请求 → xiaozhang 入口 → 一个按需 Skill → 证据化输出 → 用户决定下一步
```

`xiaozhang-narrative` 会先问本轮问题和材料范围，再把事实、用户原话、判断变化、推断和未知分开。它不会因为读到一段日记就声称已经完全了解你，也不会默认扫描整个 Obsidian。

## 尚未支持的边界

- 不自动构建向量数据库、RAG、长期记忆服务或全库索引
- 不做心理诊断、人格测评或治疗建议
- 不替用户决定人生目标，不自动修改信念或写回私人文件
- 不包含任何用户的私人经历；想让 AI 使用个人资料，需在自己的受控环境中提供相应材料
- 不保证所有 AI 客户端都能自动发现、安装或选择 Skill

## 口播

> 我把小张 Skill 开源在 GitHub 用户名 **lalala597** 的 **xiaozhang-skill** 仓库里，你不用记网址，去搜用户名或仓库名，让你的 AI 按需安装。

## 致谢

目标审计和按需 Skill 的部分思路受 [dbskill](https://github.com/dontbesilent2025/dbskill) 启发；本仓库是独立的小张 Skill 入口与个人叙事工具，不是 dbskill 的官方分支。
