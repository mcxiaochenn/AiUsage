# Agent UI 入口

- 新增或修改 Flutter UI 前，必须先阅读 [`docs/design-system/README.md`](docs/design-system/README.md) 及其指向的相关章节。
- 修改前先检查相似页面和现有公共组件，保持同组页面的排版层级、Typography、Spacing、组件尺寸和交互方式一致。
- 延续 Material 3 和现有 AiUsage 设计语言，优先复用已定义的语义、Theme 与组件。
- 页面 Typography 必须通过 `context.aiTypography` 获取语义角色；UI 实现层禁止视觉裸值，新的语义必须先扩展 Design System。
- 禁止创建页面专属 Token，或用只使用一次的公共包装组件隐藏硬编码；品牌或数据可视化例外必须符合登记规则。
- UI 改动必须检查中英文、亮暗/动态主题、响应式布局和可访问性。
- 引入新的 UI 模式时，必须在同一改动中更新对应 Design System 文档。
