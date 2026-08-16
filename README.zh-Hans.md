<p align="center">
  <img src="Assets/AppIcon/AppIcon.png" width="144" alt="md2png 应用图标">
</p>

<h1 align="center">md2png for Mac</h1>

<p align="center">
  在 Mac 上将剪贴板中的 Markdown 转为精美 PNG——全程本地，保护隐私。
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://md2png.wbxsh.com/zh/"><strong>官方网站</strong></a>
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
| 恢复上次的 Markdown | — | 将最近一次成功的源 Markdown 恢复到剪贴板 |
| 显示上次渲染 | `Control-Command-Z`（全局） | 打开最近结果，可用 `Command-W` 关闭 |
| 输出宽度 | — | 为后续渲染选择紧凑、标准或宽幅，并在本地记住选择 |
| 示例 | — | 复制并渲染选中的内置 Sample，然后自动打开预览 |
| 显示欢迎指南 | — | 重新打开复制、渲染和粘贴指南，并显示当前快捷键状态 |
| 关于 md2png | — | 显示版本、发布说明、项目链接、更新状态与操作，以及可复制的诊断信息 |

菜单顶部会显示紧凑的剪贴板预览。“标准”保持原有输出尺寸，“紧凑”会更早换行，
“宽幅”则为大型表格和图表留出更多空间。正在渲染时，新的渲染命令、宽度切换和
Sample 会暂时禁用，避免重复渲染。只有成功渲染后才会启用“恢复上次的 Markdown”；
如果其他应用已经修改剪贴板，覆盖前会要求确认。“上次渲染”窗口会在当前屏幕范围内
按输出宽度打开，并在标题中标明所用预设和实际尺寸。
欢迎指南只会在首次启动时自动打开，之后可从菜单重新查看；其中的示例按钮会在菜单栏图标下
先展示主菜单，再展开“示例”；只有用户再次选择一个示例后才会开始渲染。指南打开期间，md2png 会出现在
Command-Tab 中，关闭指南后会恢复为纯菜单栏模式。
实际尺寸和同源渲染对比见[宽度预设功能说明](docs/PRODUCT.md#width-presets)。

## Sample

菜单中包含短示例、长示例、排版、代码块、Checklist、GFM 表格、流程图、时序图和
Gantt 时间线。源文件位于 [Examples](Examples)，完整效果可查看
[long-project-update.png](docs/images/long-project-update.png)。

## 隐私

- 使用内置资源在非持久化本地 `WKWebView` 中渲染。
- Markdown 和生成的图片永远不会上传。
- 最近一次成功渲染的源 Markdown 仅保存在内存中，退出 md2png 后立即丢弃。
- 外部 Markdown 图片会被替换为文本占位符，不会发起网络请求。
- 不包含分析、遥测、广告、账号集成、Bot 或特定服务 API。
- 打开“关于 md2png”时，仅当上次成功结果已超过 24 小时才静默刷新公开的
  GitHub Release 元数据；仍可手动“再次检查”。请求中不包含 Markdown、
  剪贴板数据或 GitHub 凭据。
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
make verify-dist \
  PROJECT_URL=https://github.com/OWNER/REPOSITORY \
  UPDATE_CHANNEL=stable \
  BUNDLE_IDENTIFIER=io.github.OWNER.md2png
make run CONFIGURATION=debug \
  PROJECT_URL=https://github.com/OWNER/REPOSITORY \
  BUNDLE_IDENTIFIER=io.github.OWNER.md2png
```

即使打包了 `PROJECT_URL`，Debug 构建也绝不会使用稳定生产更新渠道。需要测试
About 更新状态时，请使用显式的本地 fixture；它不会发送 Release 元数据请求：

```sh
make run CONFIGURATION=debug \
  PROJECT_URL=https://github.com/guangyya/md2png \
  TEST_UPDATE_VERSION=0.0.0 \
  TEST_UPDATE_STATE=up-to-date       # 也可使用 check-failed / download-failed / ready-to-install
```

`TEST_UPDATE_STATE` 仅允许用于本地 Debug app/run 构建，发布流程会拒绝它。
`TEST_UPDATE_VERSION` 只修改打包后的测试 App 版本，`publish-release` 同样会拒绝它；
公开发布始终使用 `Info.plist` 中的 `CFBundleShortVersionString`。下载相关 mock
使用不可路由的 fixture 元数据；Debug 更新渠道禁用时，它无法发起更新或资产请求。
如果 fixture 文件不存在，`ready-to-install` 会先显示仅供界面测试的可恢复下载失败
状态，而不会提供一个指向缺失文件的“打开”操作。

`PROJECT_URL` 只在打包时写入 App；省略时 About 会隐藏项目与更新控件。Debug
构建会保留已配置的项目链接，但隐藏生产更新控件。只有显式打包了
`UPDATE_CHANNEL=stable` 且带有效 GitHub 项目地址的构建才使用稳定 GitHub Releases
渠道；缺失、未知和未来新增的渠道值默认禁用。源码不包含固定仓库地址。
`BUNDLE_IDENTIFIER` 默认读取 `Info.plist` 中的个人标识，也可在构建时覆盖。
`make verify-dist` 会重新构建 App，检查签名和 arm64 架构，再通过内置
Markdown、GFM 表格、高亮 Swift 代码和 Mermaid 图执行离线渲染自测；
该过程不会读取或修改剪贴板。

发布、Developer ID 签名和 Apple 公证流程见 [Releasing](docs/RELEASING.md)。

## 贡献与许可证

欢迎聚焦的 Bug 报告和改进。新功能请使用
[Feature Request 模板](../../issues/new?template=feature_request.yml)，
已筛选的方向记录在
[公开 GitHub Issues](https://github.com/guangyya/md2png/issues)；带 `backlog`
标签不代表承诺版本或时间。
提交 PR 前请阅读 [Contributing](CONTRIBUTING.md)；安全问题请按
[Security policy](SECURITY.md) 处理。

md2png 使用 [MIT License](LICENSE)；内置依赖保留各自许可证，见
[Third-party notices](THIRD_PARTY_NOTICES.md)。
