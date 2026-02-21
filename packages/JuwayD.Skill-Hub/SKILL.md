---
name: Skill-Hub 包管理与发布器
description: 核心平台工具。专门用于发布 (publish) 本地 skills，以及搜索 (search) 和下载 (install/下载) 远程 skills。当用户提到“发布 skill”、“上传插件”、“下载 skill”、“找个 skill”等意图时，必须触发此技能。
---
# Skill-Hub: Antigravity Skill Registry Manager

Skill-Hub 是组织内部的 Skill 包管理中心。它利用 Antigravity 的 AI 能力，配合本地 VCS 工具（Git/P4），实现 Skill 的一键发布、智能搜索和无感安装。

## 核心指令

### 1. 发现 (Search)

- **触发句式**：“Skill-Hub，帮我找找[关键字]相关的工具”、“看看组织里有哪些关于[功能]的 Skill”。
- **工作流**：
    1. 调用适配器拉取远程索引。
    2. 结合 AI 语义理解对搜索词与 Skill 描述进行相关性评分。
    3. 返回结构化列表（名称、作者、描述、推荐指数）。

### 2. 安装 (Install)

- **触发句式**：“下载第一个”、“安装 [Skill 名称]”、“把那个代码审查工具装上”、“把它装到全局”。
- **工作流**：
    1. 锁定目标 Skill 的仓库路径。
    2. **路径判定**：系统默认下载路径由 `config.json` 中的 `local.install_default` 决定（默认值为 `workspace` 即当前项目下的 `.agent/skills`）。
       - 如果用户在指令中明确指定了“全局”或“当前项目”，则**以用户口头提示为最高优先级**覆盖配置。
    3. 自动调用本地 VCS (Git/P4) 将 Skill 部署到确定好的路径下。
    4. 提醒用户刷新 Antigravity 以启用新 Skill。

### 3. 发布 (Publish)

- **触发句式**：“帮我把那个画图的 Skill 发了”、“发布当前的翻译工具”、“就把刚写好的那个发上去”。
- **工作流**：
    1. **智能检索**：按“当前工作空间 > 全局路径”的优先级，根据模糊描述自动锁定目标 Skill 文件夹。
    2. **自动补全**：若无 `skill.json`，自动从代码内容生成名称与描述。
    3. **背景推送**：静默完成所有 VCS (Git/P4) 提交逻辑，发布成功后给一个简短确认。

### 4. 异常处理：多个匹配项冲突 (Ambiguity)

- **Agent 责任**：当执行发布或下载操作时，如果你在后台运行 `core.js` 后收到包含 `AMBIGUITY_ERROR` 的错误输出（说明有多个 Skill 名称或描述匹配了用户的指示），你**绝对不能自己瞎猜**。
- **处理方式**：你需要立即中断当前操作，读取终端错误输出里的候选列表，并用自然语言询问用户：“我找到了几个名字相似的工具，请问您需要处理哪一个？

1. xxx
2. yyy”
等到用户明确指出具体名字后，再带着完整的、精确的名称重新调用适配器脚本。

- **增强模式 (Preferred)**: Node.js (v18+) 或 Python (3.10+)。
- **原生模式 (Fallback)**: PowerShell (Win) / Zsh (Mac)。

## 首次运行配置指南 (Agent 必读准则)

这不仅仅是一个工具指令，更是对用户数据的尊重：

1. **核心原则**：你（Agent）**绝对不可以**在未经用户明确同意或告知的情况下随意填入 `config.json` 里诸如 `registry.url` 或作者名之类的敏感信息。
2. **缺失处理**：当执行 `publish` 等操作发现 `config.json` 为空或为初始占位符时，你**必须立刻停下动作并询问用户**。
3. **询问模板参考**：“我发现你还没有配置组织内部的 Skill 仓库地址和个人身份。您可以打开 [config.json](file:///c:/Users/一天不说骚话就浑身难受/.gemini/antigravity/skills/Skill-Hub/config.json) 自己填一下，或者直接把地址和你的作者名发我，我用核心脚本帮你安全配好。”
4. **安全写入机制**：如果用户选择让你帮忙填报，**严禁对文件进行直接读写**。请务必使用：
   `node adapters/core.js config registry.url <URL>` 和 `node adapters/core.js config user.author_default <Name>`。

详情见同目录下的 `config.json` 及 `adapters/` 驱动。
