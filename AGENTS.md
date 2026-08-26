# Agent UI 入口

- 新增或修改 Flutter UI 前，先阅读 [`docs/design-system/README.md`](docs/design-system/README.md)；普通 UI 任务通常只需该 Quick Start，触及 Theme、公共组件、复杂交互、响应式或迁移时再按需读取细分文档。
- 修改前先检查相似页面和现有公共组件，保持同组页面的排版层级、Typography、Spacing、组件尺寸和交互方式一致。
- 延续 Material 3 和现有 AiUsage 设计语言，优先复用已定义的语义、Theme 与组件。
- Typography 和颜色必须使用 Design System；Spacing、尺寸、Shape 与特殊布局仅可按 Quick Start 使用紧邻代码且带理由的受控例外。
- 不得创建页面专属 Token，或用只使用一次的公共包装组件隐藏视觉值；新的可复用语义应先扩展 Design System。
- UI 改动必须检查中英文、亮暗/动态主题、响应式布局和可访问性。
- 引入新的可复用视觉语义、公共组件职责或交互模式时，必须在同一改动中更新对应 Design System 文档。
