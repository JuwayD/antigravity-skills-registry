---
name: p4_checkout
description: 全局技能：自动将文件添加/检出到合适的 Perforce Changelist
---

# P4 Checkout Skill

当需要新增或修改文件并加入版本控制时，请严格执行此技能。它会自动探测当前是否有合适的 P4 Changelist，如果没有则创建一个新的，并将目标文件加入其中。这是所有涉及代码或资源修改的前置保护步骤。

## 1. 检查文件状态
首先确认你要操作的文件（新增或修改）的绝对路径。

## 2. 查找可用 Changelist
运行命令：`p4 changes -s pending -u <你的用户名> -c <你的工作区名称>`
来查看当前是否有 Pending 状态且描述符合这次修改的 Changelist。

## 3. 创建新 Changelist（可选）
如果没有合适的 Pending Changelist，运行命令：`p4 change -o | p4 change -i`
创建一个新的 Changelist，并可以在描述中注明相关的修改内容。

## 4. 添加/检出文件
- 如果是 **新增** 的文件，运行命令：`p4 add -c <Changelist号> <文件绝对路径>`
- 如果是 **修改** 已有的文件，运行命令：`p4 edit -c <Changelist号> <文件绝对路径>`

### 示例用法
假设要修改的文件是：`f:\WorkSpace\V1D1\V1D1_Project\huangrongqi_DM42.Beyond_Beyond_v1d1_project\Assets\Beyond\Scripts\Gameplay\Core\NpcSystem\Data\NpcData.cs`
并且找到了一个可用的 changelist：`12345`
则执行：`p4 edit -c 12345 f:\WorkSpace\V1D1\V1D1_Project\huangrongqi_DM42.Beyond_Beyond_v1d1_project\Assets\Beyond\Scripts\Gameplay\Core\NpcSystem\Data\NpcData.cs`
