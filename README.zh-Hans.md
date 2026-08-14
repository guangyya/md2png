<p align="center">
  <img src="Assets/AppIcon/AppIcon.png" width="144" alt="md2png 应用图标">
</p>

<h1 align="center">md2png for Mac</h1>

<p align="center">
  在 Mac 上将剪贴板中的 Markdown 本地渲染为精美 PNG，不上传，也绝不自动发送。
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://guangyya.github.io/md2png/"><strong>官方网站</strong></a>
  ·
  <a href="#从源码构建"><strong>从源码构建</strong></a>
  ·
  <a href="docs/PRIVACY.md">隐私说明</a>
</p>

md2png 是一个原生 macOS 菜单栏小工具，适合在无法完整显示 GFM 表格、
代码高亮或 Mermaid 图表的聊天应用中使用。它不修改或注入其它应用，
不会自动粘贴，也不会自动发送消息。

![Markdown 渲染后的表格和 Mermaid 流程图](docs/images/example-render.png)

## 系统要求

- macOS 14 或更高版本
- Apple 芯片（`arm64`）；不支持 Intel Mac

## 使用方式

1. 在任意应用中用 `Command-C` 复制 Markdown。
2. 在任意应用中按 `Control-Command-X`，或从菜单栏选择“将剪贴板渲染为图片”。
3. 等待底部 HUD 提示成功。
4. 按 `Command-V` 粘贴 PNG。
5. 检查附件后由你自己发送。

渲染命令不会激活其它应用、不会自动粘贴，也不会发送。如果渲染失败，
剪贴板中的源 Markdown 会保留。

## 支持的内容

| 类型 | 说明 |
|---|---|
| Markdown | 标题、列表、链接、引用、强调、行内代码和代码块 |
| GFM 风格 | 表格、删除线和 checklist 源文本 |
| 代码块 | Swift、JavaScript、TypeScript、JSON、Shell、Python、Java、Kotlin、C/C++、Go、Rust、SQL、YAML、HTML/XML 和 CSS 等离线高亮 |
| Mermaid | 流程图、时序图、Gantt 图以及内置 Mermaid 版本支持的其它语法 |

Mermaid 必须使用 `mermaid` 代码 fence，且 fence 内第一行要声明图表类型：

````markdown
```mermaid
flowchart LR
    Draft --> Review
    Review --> Ship
```
````

`A->>B: Hello` 这类消息箭头属于 `sequenceDiagram`，不是 `flowchart`。渲染失败时
可查看 [故障排查](docs/TROUBLESHOOTING.md)。

## 菜单栏命令

| 命令 | 快捷键 | 行为 |
|---|---|---|
| 将剪贴板渲染为图片 | `Control-Command-X`（全局） | 成功后用 PNG/TIFF 替换剪贴板 |
| 显示上次渲染 | `Control-Command-Z`（全局） | 打开最近结果，可用 `Command-W` 关闭 |
| 示例 | — | 复制并立即渲染选中的内置 Sample |
| 关于 md2png | — | 显示版本、Debug/Release、发布说明、项目与 Releases 链接和可复制的诊断信息 |

菜单顶部会显示紧凑的剪贴板预览。正在渲染时，新的渲染命令和 Sample
会暂时禁用，避免重复渲染。

## Sample

菜单中包含短示例、长示例、排版、代码块、Checklist、GFM 表格、流程图、时序图和
Gantt 时间线。源文件位于 [Examples](Examples)，完整效果可查看
[long-project-update.png](docs/images/long-project-update.png)。

## 隐私

- 使用内置资源在非持久化本地 `WKWebView` 中渲染。
- Markdown 和生成的图片永远不会上传。
- 外部 Markdown 图片会被替换为文本占位符，不会发起网络请求。
- 不包含分析、遥测、广告、账号集成、Bot 或特定服务 API。
- 基础的复制/渲染/粘贴流程不需要 Accessibility 权限。
- 绝不自动粘贴或发送。

详情见 [隐私说明](docs/PRIVACY.md) 和 [安全策略](SECURITY.md)。

## 从源码构建

需要 macOS 14+、Apple 芯片、Xcode 26+ / Swift 6.2、Node.js 和 pnpm。

```sh
make bootstrap
make test
make app CONFIGURATION=debug \
  PROJECT_URL=https://github.com/OWNER/REPOSITORY \
  BUNDLE_IDENTIFIER=io.github.OWNER.md2png
make run CONFIGURATION=debug \
  PROJECT_URL=https://github.com/OWNER/REPOSITORY \
  BUNDLE_IDENTIFIER=io.github.OWNER.md2png
```

`PROJECT_URL` 只在打包时写入 App；省略时 About 会隐藏项目与 Releases 链接。
源码不包含固定仓库地址。`BUNDLE_IDENTIFIER`
默认读取 `Info.plist` 中的个人标识，也可在构建时覆盖。

发布、Developer ID 签名和 Apple 公证流程见 [Releasing](docs/RELEASING.md)。

## 贡献与许可证

欢迎聚焦的 Bug 报告和改进。新功能请使用
[Feature Request 模板](../../issues/new?template=feature_request.yml)，
已筛选的方向记录在 [Product Backlog](BACKLOG.md)；进入 Backlog 不代表承诺版本或时间。
提交 PR 前请阅读 [Contributing](CONTRIBUTING.md)；安全问题请按
[Security policy](SECURITY.md) 处理。

md2png 使用 [MIT License](LICENSE)；内置依赖保留各自许可证，见
[Third-party notices](THIRD_PARTY_NOTICES.md)。
