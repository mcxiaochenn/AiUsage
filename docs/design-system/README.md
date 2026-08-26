# AiUsage Design System Quick Start

本页是普通 Flutter UI 任务的默认入口。新增页面、调整布局或修复常规 UI 时，先读完本页并检查相似页面，通常即可开始实现；只有触及 Theme、公共组件、复杂交互、响应式边界或迁移治理时，才按文末索引继续读取细分文档。

AiUsage 延续现有 Material 3、动态取色、卡片式信息结构和移动端优先方向。Design System 用于保持语义与交互一致，不用于重新设计产品，也不得改变 Provider、缓存、凭据或业务行为。

## 常规 UI 工作流

1. 在现有页面和 `app/lib/src/design_system/components/` 中查找相同职责的实现。
2. 使用已有 Theme、语义 Token 和 Material 组件完成布局，不按页面另造一套视觉规则。
3. 检查 English、简体中文、亮暗主题、360dp、expanded 布局和大字体。
4. 运行 Design Token Audit、Analyze 和相关 Widget 测试。

## 默认规则

- **Typography 严格统一**：页面文字样式必须来自 `context.aiTypography`。不得直接访问 `.textTheme`、创建 `TextStyle` 或设置字号、字体、字重。
- **颜色严格统一**：使用 `context.aiColors`、`context.aiSemanticColors` 或已登记的品牌/图表 Token。页面不得声明命名颜色、十六进制颜色或自行计算透明度。
- **Spacing、尺寸与 Shape 优先复用**：优先使用 `context.aiSpacing`、`context.aiShapes`、`AiUsageLayoutTokens`、`AiUsageComponentSizeTokens` 和图表 Token。
- **避免伪抽象**：不得为单个页面创建页面专属 Token，也不得用只使用一次的公共 Widget 隐藏视觉值。
- **同职责保持一致**：修改前对照相似页面，保持排版层级、组件尺寸、状态反馈和交互方式一致。
- **可访问性是默认要求**：大字体下允许内容自然增高；操作不能只靠颜色表达，图标按钮需要可访问名称。

## 视觉值决策

遇到现有 Token 无法直接表达的值时，按以下顺序判断：

1. **已有相同职责**：复用现有 Token 或公共组件。
2. **会跨页面复用，或代表稳定产品语义**：先扩展 Design System 和对应文档，再在页面使用。
3. **仅服务当前局部结构，复用没有语义价值**：Spacing、尺寸、Shape 或特殊布局可以使用受控例外，不要制造假的公共 Token。

Typography 和颜色始终属于高漂移风险项，不适用第 3 条。

## 受控局部例外

例外只能放在违规代码的紧邻上一行，必须写明局部原因：

```dart
// design-token-audit: allow spacing.literal -- Aligns the embedded platform control.
padding: const EdgeInsets.only(top: 3),
```

允许的规则只有：

- `spacing.literal`
- `shape.literal`
- `visual-number.literal`
- `responsive.literal`
- `visual-constant.literal`

约束：

- 不允许豁免 `typography.*` 或 `color.literal`。
- 不支持文件级、目录级或永久 Ignore。
- 注释与目标代码之间不能有空行；一个注释只允许一个规则。
- 例外只用于没有跨页面语义价值的局部实现；一旦重复出现，应收敛为 Token 或公共组件。
- 无效、禁止、未命中的例外注释会使 CI 失败。

审查仓库中的全部例外：

```powershell
rg -n "design-token-audit: allow" app/lib
```

## 代码入口

- Theme 与语义颜色：`app/lib/src/design_system/theme/`
- Typography、Spacing、Shape、Layout、尺寸、品牌和图表 Token：`app/lib/src/design_system/tokens/`
- 公共 UI 结构：`app/lib/src/design_system/components/`
- Context 访问入口：`app/lib/src/design_system/context_extensions.dart`

常用访问方式：

```dart
context.aiTypography
context.aiColors
context.aiSemanticColors
context.aiSpacing
context.aiShapes
```

## 什么时候继续阅读

| 任务 | 按需文档 |
| --- | --- |
| 修改 Theme、Typography、颜色、Spacing 或 Shape Token | [基础规范](foundations.md) |
| 新增或改变公共组件职责 | [组件规范](components.md) |
| 修改导航、加载、反馈、Dialog 或危险操作 | [交互规范](interaction.md) |
| 修改断点、宽屏布局、大字体、键盘或 Semantics | [响应式与可访问性](responsive-accessibility.md) |
| 了解长期产品原则 | [设计原则](principles.md) |
| 审计现有问题 | [现状审计](current-audit.md) |
| 继续迁移或调整治理门禁 | [迁移计划](migration.md) |

普通页面新增和简单 UI 修改无需预读全部文档。发现任务确实触及表中职责时，再加载对应章节。

## 提交前验证

```powershell
cd app
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/check_design_tokens.dart
flutter analyze --no-pub
flutter test --no-pub
```

新视觉语义、公共组件职责或交互模式进入代码时，应在同一改动中更新对应细分文档；普通页面复用现有规范时无需重复修改文档。
