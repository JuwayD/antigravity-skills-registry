---
name: setup_p4config
description: 全局技能：修复并配置多工作区下的 Perforce 环境探测
---

# Setup P4 Config Skill

当你遇到由于全局锁定导致在另一个新工作区（Workspace）中 Perforce 或 AI 助手插件无法正确探测到工作区时，请执行以下技能排除环境问题：

## 1. 启用目录级别的环境变量读取
开启目录级别的 P4 变量读取支持。请运行此指令（此命令可安全运行）：
```powershell
p4 set P4CONFIG=.p4config
```

## 2. 探测与配置 P4CLIENT
探测你在这个工作区所对应的 `P4CLIENT` 名字，并将其写入当前工程根目录的 `.p4config` 文件中：
1. 你可以通过运行命令 `p4 clients -u <你的用户名>` 找到正确的名称。
2. 在此之后，将提取的名称写入工程根目录的 `.p4config` 文件。

### 示例
如果你当前在 v1d1 分支对应的工作区，找到的名字是 `huangrongqi_DM42.Beyond_Beyond_v1d1_project`，那么在该工作区的根目录下创建或向其 `.p4config` 文件写入：
```
P4CLIENT=huangrongqi_DM42.Beyond_Beyond_v1d1_project
```
