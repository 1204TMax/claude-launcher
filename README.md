# ClaudeLauncher

ClaudeLauncher 是一个原生 macOS 桌面端工具，用来把 **Claude Code** 从“终端里的单个 CLI 会话”提升成一个可视化的 **多会话工作台**。

它的目标不是单纯帮你启动命令，而是帮你：
- 在一台 Mac 上统一查看当前所有 Claude Code 实时会话
- 批量启动多个带配置的 Claude Code 会话
- 对会话进行命名、查看状态、关闭会话
- 管理会话上下文，而不是只管理终端进程

---

## 这个项目是做什么的？

这个项目解决的是 Claude Code 在日常使用里的几个痛点：

1. **多会话难管理**
   - 终端里同时开很多 Claude Code，会很难分辨哪个会话在做什么
   - 手动开的、应用开的，原本分散在不同终端标签页里

2. **批量启动麻烦**
   - 需要重复输入模型、权限模式、思考深度、工作目录等配置
   - 很难一次性开多个同配置会话

3. **会话缺少统一工作台**
   - 没有一个地方能统一看到：
     - 哪些会话还活着
     - 哪些已经结束
     - 每个会话当前叫什么
     - 最近在干什么

4. **命名、关闭、状态同步不直观**
   - Claude Code 本身是终端工具，不是桌面会话管理器
   - 这个项目就是在 macOS 上补上“会话控制台”这一层

---

## 当前已经实现的功能

### 1. 配置（Profile）管理
- 创建、复制、删除启动配置
- 每个配置可设置：
  - 工作目录
  - 附加上下文目录
  - 权限模式（Permission Mode）
  - 启动模式（Launch Mode）
  - 思考深度（Thinking Depth）
  - 模型（支持下拉和自定义输入）
  - 会话命名模板
  - 启动后首条消息
  - 附加系统提示词

### 2. 批量启动 Claude Code
- 支持输入数量，一次启动多个 Claude Code 会话
- 批量会话继承同一套配置
- 支持启动前预览将要创建的会话名
- 支持命令预览

### 3. 全局会话发现
- 会话记录页以本机 Claude Code transcript / session 文件为准展示会话
- 会自动发现并展示这台设备上的 Claude Code 会话
- 包括手动在终端里打开的 Claude Code 会话
- 列表展示不再依赖“是否由本应用启动”这个来源区分

### 4. 会话状态同步
- 支持刷新会话记录并重新扫描当前状态
- 已打开会话会显示 `已打开` 标签
- 已关闭会话仍可保留在列表中继续操作
- 会话状态变更后，列表会重新按当前状态同步

### 5. 会话记录操作
- 左侧“会话记录”列表支持：
  - 置顶 / 取消置顶
  - 重命名
  - 重新打开（恢复会话）
  - 删除
- 置顶会话会显示 `置顶` 标签，并排序到列表顶部
- 更多操作菜单同一时刻只会展开一个
- 点击页面其他位置会自动关闭当前菜单

### 6. 会话命名
- 支持在工作台中给会话重命名
- 重命名通过 Claude Code 的 `/rename` 命令执行
- 对外部发现的会话也会尽量同步 rename
- 如果 Claude Code transcript / metadata 中已有名字，会优先展示该名字

### 7. 重新打开与关闭会话
- 删除会先尝试终止对应 Claude Code 会话，再从列表移除
- 对已关闭会话支持“重新打开”
- 重新打开会基于原会话的 `cwd` + `sessionID` 调用 Claude Code `--resume` 恢复会话

### 8. 工作台界面
当前主界面已经按“工作台”思路组织成三块：
- 左栏：配置与批量启动
- 中栏：会话记录列表
- 右栏：当前会话 transcript / 对话内容

顶部还有总览栏，显示：
- Live 会话数
- 运行中数量
- 空闲数量
- 最近同步时间

---

## 技术栈

### 桌面端
- **SwiftUI**
- **AppKit**（通过 macOS 原生能力辅助）

### 工程组织
- **XcodeGen** 用于生成 Xcode 工程
- 原生 macOS App

### 运行时能力
- **AppleScript / osascript**
  - 用于与 Terminal.app 交互
- **Process / ps / kill**
  - 用于发现和关闭 Claude Code 进程
- **本地文件读取**
  - 读取 `~/.claude/sessions/<pid>.json` 识别当前 live Claude Code 会话

### 配置与存储
- **Application Support JSON 存储**
  - 保存 profiles / sessions / gateways 等非敏感配置
- **Keychain**
  - 保存 API key / token 等敏感信息

---

## 当前依赖的外部环境

要正常使用这个项目，至少需要以下环境：

### 1. macOS
- 当前项目是 **macOS 桌面端**
- 目标支持最近几代 macOS
- 建议 macOS 14+

### 2. Claude Code 已安装
需要本机可直接运行：

```bash
claude
```

也就是说，`claude` 命令必须已安装并能在终端里启动。

### 3. 有权访问本地 `~/.claude/` 目录
本项目当前会读取：

- `~/.claude/sessions/<pid>.json`

来发现 live Claude Code 会话。

### 4. Terminal.app 可用
当前部分控制能力依赖：
- Terminal.app
- AppleScript

因此：
- app 启动的会话在 Terminal.app 中可控性更高
- 外部会话的控制能力取决于它的运行来源和上下文

---

## 当前已知限制

这个项目目前仍然有一些明确的边界：

### 1. “信任文件夹”提示不能被稳定强跳过
Claude Code 的 trust prompt 没有公开稳定 API。
所以当前项目不会通过不可靠的内部文件 hack 去伪造 trust state。

### 2. 外部会话的控制能力不如 app 启动会话稳定
- 外部发现的会话可以显示、关闭、尽量 rename
- 但如果它来自复杂上下文（如 tmux / ssh / 特殊终端），可控性会下降

### 3. rename 已经可用，但不同来源会话的稳定性不同
- 本应用启动的会话通常更可控
- 外部发现会话会尽量同步 rename，但仍受运行环境影响

### 4. 当前列表以“实时 live 会话”为主
- 已关闭会话会从当前列表中消失
- 当前不是历史归档浏览器

### 5. 网关功能已接入底层，但主界面暂时降级
- 网关（baseURL / key / provider）逻辑还在
- 但目前主界面重点是会话工作台，不是网关管理台

---

## 项目结构（核心）

```text
claude-launcher/
├── ClaudeLauncherApp/
│   ├── App/
│   │   └── ClaudeLauncherApp.swift
│   ├── Domain/
│   │   └── Models.swift
│   ├── Features/
│   │   └── Profiles/
│   │       └── RootView.swift
│   ├── Services/
│   │   ├── AppModel.swift
│   │   ├── ProfileStore.swift
│   │   ├── SessionStore.swift
│   │   ├── GatewayStore.swift
│   │   ├── KeychainService.swift
│   │   ├── LaunchCoordinator.swift
│   │   ├── SessionMonitor.swift
│   │   ├── ClaudeSessionDiscovery.swift
│   │   └── StartupAutomationCoordinator.swift
│   └── Infrastructure/
│       └── PTY/
│           └── PTYSession.swift
├── ClaudeLauncherTests/
│   └── ClaudeLauncherTests.swift
├── project.yml
└── README.md
```

---

## 如何本地生成工程

```bash
cd /Users/dashan/Documents/dev/claude-launcher
xcodegen generate
```

---

## 如何本地编译

```bash
cd /Users/dashan/Documents/dev/claude-launcher
xcodebuild -project claude-launcher.xcodeproj -scheme ClaudeLauncher -configuration Debug build
```

---

## 如何本地跑测试

```bash
cd /Users/dashan/Documents/dev/claude-launcher
xcodebuild -project claude-launcher.xcodeproj -scheme ClaudeLauncher -configuration Debug test
```

---

## 如何生成 DMG 安装包

```bash
cd /Users/dashan/Documents/dev/claude-launcher
xcodegen generate
bash scripts/package-dmg.sh
```

生成完成后，安装包会输出到：

```bash
dist/*.dmg
```

当前默认生成的是**未签名、未公证**的 DMG。

这意味着：
- 别人下载后可以看到并拖拽安装
- 但第一次打开时，macOS 可能会提示“无法验证开发者”
- 这时可以通过右键打开，或在系统设置中允许继续打开

如果后续你配置了 `Developer ID Application` 证书和 notarization，也可以通过环境变量启用：

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-notary-profile" \
bash scripts/package-dmg.sh
```

---

## 这个项目当前最适合谁用

这个工具适合：
- 经常同时运行多个 Claude Code 会话的人
- 需要批量启动不同任务上下文的人
- 希望把 CLI 会话提升成桌面“工作台”体验的人
- 需要统一查看本机当前所有 live Claude Code 会话的人

---

## 下一步可能继续做的方向

- 更稳定的外部会话控制（特别是 rename）
- 更强的会话历史与归档视图
- 更完善的摘要能力
- 更细的终端来源识别（Terminal / iTerm / tmux）
- 更稳的“编辑保护”，避免自动刷新打断当前操作

---

## 当前一句话总结

**ClaudeLauncher = 一个原生 macOS 的 Claude Code 多会话工作台。**

它的重点不是“帮你执行命令”，而是：

**帮你看见、识别、启动、命名、同步和关闭这台设备上的 Claude Code 会话。**
