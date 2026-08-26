# AiUsage Design System

本目录是 AiUsage UI / UX 规范的唯一权威入口。它用于约束后续 Theme、页面和组件实现，目标是在保留当前 Material 3 设计语言的前提下逐步提高一致性，而不是重新设计产品。

## 适用范围

本规范适用于 Flutter 应用中的：

- Theme、Typography、颜色、间距、Shape 与图标。
- 页面框架、导航、卡片、表单、状态反馈和数据可视化。
- Android、iOS 以及后续桌面平台的响应式行为。
- 中英文、大字体、触摸、鼠标、键盘和读屏体验。

本规范不定义 Provider API、业务模型、缓存、凭据或 Rust/Flutter 职责边界。UI 调整不得借 Design System 之名改变这些行为。

## 规范基础与优先级

AiUsage 以 Material 3 为基础。Flutter 的 `ThemeData`、`ColorScheme`、`TextTheme` 和标准组件提供基础行为，本目录只定义 AiUsage 的语义、使用边界和受控扩展。

遇到冲突时按以下顺序判断：

1. 用户任务中的明确需求和产品安全边界。
2. 本目录中的长期原则和规范。
3. Material 3 与平台无障碍约定。
4. 当前代码中的既有实现。

当前代码可能包含尚未迁移的临时样式。代码与规范不一致时，应先确认该实现是否记录在[现状审计](current-audit.md)或[迁移计划](migration.md)中，不得直接把旧写法复制到新页面。

## 按任务阅读

| 任务 | 必读文档 |
| --- | --- |
| 修改 Theme、颜色、字体、间距或 Shape | [设计原则](principles.md)、[基础规范](foundations.md) |
| 新增或修改通用组件 | [基础规范](foundations.md)、[组件规范](components.md)、[交互规范](interaction.md) |
| 新增页面或调整页面布局 | 本页、[设计原则](principles.md)、[组件规范](components.md)、[交互规范](interaction.md)、[响应式与可访问性](responsive-accessibility.md) |
| 修复局部 UI 一致性问题 | [现状审计](current-audit.md)、相关规范章节、[迁移计划](migration.md) |
| 迁移现有页面 | [迁移计划](migration.md)及该页面涉及的全部规范 |
| Review UI 变更 | [设计原则](principles.md)、[响应式与可访问性](responsive-accessibility.md)、[迁移计划](migration.md)中的 Definition of Done |

## 规范用语

- **必须**：不可省略的产品、安全或可访问性约束。
- **应该**：默认做法；偏离时必须有明确理由。
- **可以**：在不破坏上层原则时允许采用的方案。

## 新模式如何进入系统

新增视觉值、组件或交互模式前，先检查现有语义能否覆盖需求。只有出现明确的新职责时才增加模式，并同步更新对应文档。品牌资源和数据可视化可以保留必要例外，但必须记录用途、适用范围和回退方式。

不要为了单个页面预先建立通用抽象，也不要在业务组件中散落未命名的视觉规则。实现阶段应让 Theme、语义 token 和共享组件逐步成为代码层的真实来源。

## 文档维护

- 长期稳定规则写入 `principles.md` 至 `responsive-accessibility.md`。
- 当前代码问题只写入 `current-audit.md`，解决后同步更新状态。
- 实施顺序、迁移状态和验收门槛写入 `migration.md`。
- 新模式进入代码时，文档应与实现处于同一提交。
- 具体数值只有在完成现状统计、跨主题验证和可访问性验证后才写入规范。

## 快速自检

开始 UI 工作前，确认能够回答：

- 这次改动使用的是哪个语义角色，而不是哪个临时颜色或数值？
- 是否已有同职责组件可以复用？
- 加载、空、错误、缓存、禁用和危险状态是否适用？
- 中英文、亮暗主题、动态取色、窄屏和大字体会怎样呈现？
- 触摸、鼠标、键盘和读屏用户能否完成同一任务？
