---
name: Unity AI 闭环托管 (Unity AI Closed-Loop Management)
description: 一套通用的 Unity AI 托管开发方法论，定义了“编写-编译自检-静默执行-数据验证-资产同步”的自动化闭环逻辑。
---

# Unity AI 闭环托管 (Unity AI Closed-Loop Management)

本 Skill 不提供具体的类名或接口，而是定义了一套 **AI 与 Unity 系统进行深度交互的底层逻辑规范**。其核心目标是让 AI 能够脱离人类视觉确认，通过数据和日志完成“闭环”的开发迭代。

## 🎯 核心指导思想 (Core Philosophy)

1. **可感知性 (Visibility)**: AI 无法直接“看到”运行效果。系统必须将“视觉表现”转化为“结构化数据”或“可解析日志”。
2. **可干预性 (Controllability)**: AI 必须具备绕过 UI 操作（如点击按钮、拖拽物体），直接通过代码或指令触发核心逻辑的能力。
3. **自愈能力 (Self-Healing)**: AI 必须能够感知编译报错或运行时异常，并具备根据错误上下文自动尝试修正代码的闭环逻辑。
4. **MCP 桥接核心 (MCP-Centric)**: 所有外部交互（场景管理、对象操作、测试执行）**必须**通过 MCP (Model Context Protocol) 协议实现。**强烈推荐使用 `unityMCP https://github.com/CoplayDev/unity-mcp/tree/beta` 服务器**，它是本工作流实现“AI 托管”的基石。

## 🧱 闭环基础设施架构 (Infrastructure Methodology)

任何支持 AI 闭环托管的项目，应至少实现以下三种能力的抽象：

### A. 自主错误探测层 (Autonomous Error Detection)

* **方法论**：AI 必须有手段在不询问人类的情况下获知“代码工作是否正常”。
* **实现建议**：
  * **静态检查**：监控本地 `Editor.log` 或通过 CLI 执行 `dotnet build`。
  * **运行时监控**：实现一套能够捕获 `Debug.LogException` 并将其格式化为 AI 可识别指令的日志监听器。

### B. 状态验证中台 (Unified Data Verification Hub)

* **方法论**：提供一个“单一事实来源”(Single Source of Truth)，让 AI 可以通过键值查询了解游戏世界的瞬时状态。
* **设计原则**：
  * **精简接口**：避免为每个变量创建方法，建议使用 `Query(key, params)` 模式。
  * **零副作用**：查询接口必须是纯只读的，不能因为查询而改变游戏状态。

### C. 动作执行桥接 (Execution Bridge)

* **方法论**：建立一个允许 AI “跨时空”触发编辑器或运行时逻辑的通道。
* **设计原则**：
  * **无感触发**：支持通过菜单路径 (MenuPath) 或方法全名 (Fully Qualified Name) 触发逻辑。
  * **隔离性**：执行逻辑应尽量解耦输入层（Input），确保逻辑可以直接被脚本/MCP 指令调用。
  * **插件化扩展 (CustomTools)**：核心验证逻辑（如本项目的 `bd_tool`）应通过 `execute_custom_tool` 注册。AI 必须了解如何通过自定义指令扩展 Unity 的原生操作,参考文档`https://github.com/CoplayDev/unity-mcp/blob/beta/docs/reference/CUSTOM_TOOLS.md`。
  * **异步确认**：对于耗时操作（如测试运行、大批量资产生成），执行通道必须提供任务句柄或轮询机制（如 `job_id`），以便 AI 进行后续追踪。

## 🔄 标准闭环工作流 (Standard Workflow)

  1. **编写阶段 (Writing)**: AI 根据需求实现功能，并同步思考“我该如何验证它”。
  2. **强制编译与刷新 (Compile & Refresh) [MCP-REQUIRED]**: AI 写入代码后，**必须立即调用 `refresh_unity(compile='request')`**。否则，编辑器日志无法更新，且后续逻辑调用的仍是旧指令。
  3. **编译自检 (Compile Check)**: AI 完成写入后，**主动搜索错误特征**（如 `error CS`），发现红字则立即回归编写阶段进行修复。
  4. **静默执行 (Silent Execution) [MCP-REQUIRED]**: 编译通过后，AI 通过 `mcp_unityMCP` 提供的执行桥接器（如 `execute_custom_tool` 或 `execute_menu_item`）触发功能逻辑。
  5. **数据确认 (State Verification) [MCP-REQUIRED]**: AI 访问验证中台（通常通过 `execute_custom_tool` 查询），对比“实际数据”与“预期数据”。
  6. **结果审计 (Reporting)**: AI 将验证过程与结果记录到持久化文件中（如开发报告），作为人类审核的依据。

## 💡 给 AI 的实践准则 (Best Practices)

* **不要猜测**：如果验证回传的数据不符合预期，优先检查“验证工具本身”是否可靠，再检查“逻辑代码”。
* **最小化依赖**：在构建 AI 专用验证工具时，尽量避免依赖复杂的 UI 状态，优先通过底层数据结构（如 Singleton Managers）获取信息。
* **资产自动化**：对于 ScriptableObject、Prefab 等非代码逻辑，AI 应优先通过编辑器脚本进行自动化生成，而非指望人类手动创建。
* **异步依赖处理 (Handling Async)**：
  * **不要等待阻塞**：如果 MCP 工具返回 `job_id`，AI 应立即记录状态并进入下一轮次，而非卡在原地。
  * **主动轮询**：在后续轮次的“数据确认”阶段，优先通过 `get_test_job` 或类似工具检查异步任务是否完成。
  * **状态机思维**：将任务拆分为“提交 -> 准备 -> 运行中 -> 完成 -> 结果处理”的状态流，未完成时保持当前 Task 状态。

---
*Methodology defined by Antigravity AI — Optimized for Unattended Development.*
