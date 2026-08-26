# 基础规范

本页定义 AiUsage 的视觉基础方向和当前实现入口。数值只在 Design System 定义层维护，页面和业务组件只消费语义角色。

## 代码入口

实现位于 `app/lib/src/design_system/`：

- `tokens/typography_tokens.dart`：语义文字角色。
- `tokens/spacing_tokens.dart`、`shape_tokens.dart`：页面、卡片、控件间距与形状。
- `tokens/layout_tokens.dart`、`component_size_tokens.dart`：断点、内容宽度和固定元素尺寸。
- `tokens/brand_tokens.dart`、`data_visualization_tokens.dart`：受控品牌与图表例外。
- `theme/ai_usage_theme.dart`、`theme/semantic_colors.dart`：亮暗主题、动态色和状态色。
- `context_extensions.dart`：`context.aiTypography`、`context.aiColors`、`context.aiSemanticColors`、`context.aiSpacing`、`context.aiShapes`。

新增视觉语义时，先在上述 Token/Theme 层补充角色并更新本页，再迁移页面；禁止用页面名称创建 Token。

## Token 分层

实现阶段应按以下层级组织视觉值：

1. **Material 基础值**：`ColorScheme`、`TextTheme` 和标准组件默认行为。
2. **AiUsage 语义 token**：状态、页面密度、内容宽度和数据呈现等跨组件角色。
3. **组件 token**：只有特定组件确实需要时，才基于语义 token 定义局部规则。
4. **受控例外**：Provider 品牌和数据可视化色阶，必须说明范围和回退。

业务页面不应直接跳过语义层读取或创建零散视觉值。

## Typography

### 文本角色

- **页面标题**：表达当前一级页面的任务；二级页面标题由 AppBar 承担时不在正文重复。
- **区块标题**：划分页面内部的信息组，不与页面标题竞争。
- **卡片标题**：描述单张卡片的主题，例如额度窗口、余额类型或账户名称。
- **关键指标**：强调 Token、余额、百分比或可用次数等核心值。
- **正文**：解释内容、设置说明和一般数据。
- **辅助文本**：采集时间、来源、缓存状态和次要标识。
- **标签文本**：Chip、状态和短分类，不承载长句。
- **诊断文本**：原始响应、标识或技术详情；需要时使用等宽字体，但不能扩散到普通 UI。

实现时由 `AiUsageTypographyTokens` 映射到 Material `TextTheme` 角色，通过主题统一字号、字重和行高。页面必须使用 `context.aiTypography`，不得直接访问 `.textTheme`、构造 `TextStyle`、设置 `fontSize`、`fontFamily` 或 `FontWeight`。品牌字样和数据可视化仍通过已登记 Token 表达。

### 内容规则

- 金额、Token 和次数使用本地化数字格式；准确值不得因缩写而丢失。
- 日期和时间由统一格式化方法输出，相关页面保持时区和“相对/绝对时间”语义一致。
- Provider 原始字段不擅自翻译；UI 标签和说明必须本地化。
- 邮箱、别名、API Key 指纹、URL 和账号标识按信息用途选择换行或省略，完整敏感值永不因排版需求显示。
- 大字体下优先增加高度；只有辅助标识或重复信息才使用省略。

## Spacing

间距应形成少量可命名的节奏，而不是记录每个页面的像素值。当前 `AiUsageSpacingTokens` 至少区分：

- 页面安全边距与页面内容边距。
- 区块之间的分隔距离。
- 卡片内部边距。
- 同一内容组内的紧密、常规和宽松间距。
- 图标与文字、标签与标签、操作与操作之间的间距。
- compact 与 expanded 布局的密度调整。

页面可用的语义字段包括 `pageInsets`、`cardInsets`、`featuredCardInsets`、`stateInsets`、`emptyStateInsets`、`tightGap`、`contentGap`、`controlGap`、`sectionGap`、`majorSectionGap`、`inlineGap`、`inlineWideGap`、`actionGap`、`formFieldGap` 和 `wrapGap`。页面不得直接构造带视觉数字的 `EdgeInsets`。

选择间距时先判断语义关系：同组内容应比不同区块更接近。不得通过连续堆叠多个 `SizedBox` 临时修复层级，也不得为了卡片表面对齐压缩大字体内容。

## Color / Theme

### 基础角色

- 主操作、选中和重点强调来自 `primary` 系列。
- 次级选中或较弱强调来自 `secondary`/`tertiary` 系列。
- 页面、容器和分层表面来自 `surface` 系列。
- 错误和不可逆危险操作来自 `error` 系列。
- 所有前景色必须使用对应的 `on*` 角色。

### AiUsage 语义角色方向

后续 Theme 扩展应覆盖成功、警告、信息、缓存/陈旧、部分成功和数据可视化等级。业务组件只消费这些角色，不自行使用固定橙色、绿色或透明度表达状态。

状态必须同时提供文字、图标或结构提示，颜色仅用于增强辨认。

### 动态取色

- 动态色开启且平台支持时使用系统色板。
- 不支持或关闭时使用现有 Indigo 种子色回退。
- 明暗主题与动态色必须保持相同的状态层级和可读性。
- 动态色不能影响 Provider 身份、额度含义或危险操作级别。

### 受控颜色例外

- Provider 品牌色仅用于品牌图标的必要背景或前景。
- Token 热力图使用主题派生的连续色阶，并保留图例和准确数值入口。
- 例外不得用于普通按钮、状态或装饰背景。

## Shape / Elevation

Shape 应表达组件类别和交互层级，而不是制造视觉变化。当前 `AiUsageShapeTokens` 至少区分：

- 页面容器与普通信息卡。
- 可点击卡片和选中卡片。
- Button、输入框、Dialog、Bottom Sheet 与 Chip。
- 头像、品牌图标和热力图小单元。

普通 Card、Button、Input、Dialog 和 Chip 优先由 Theme 提供 Shape；热力图几何只使用 `AiUsageDataVisualizationTokens`。

同类组件必须共享 Shape。Elevation 仅用于表达覆盖关系或交互层级；普通信息分组优先使用表面层级和边界，不为每张卡片增加独立阴影。

## Iconography / Imagery

- 通用操作和状态优先使用 Material 图标，并在相同语义下保持同一图标。
- 图标按钮必须提供 Tooltip 或等价可访问名称。
- Provider、应用和开发者资源使用随包本地文件，不在运行时依赖第三方图标服务。
- ChatGPT 账户优先用户头像，失败时回退 Provider 图标；其他 Provider 按当前品牌规则处理。
- 装饰图片从 Semantics 中排除；传达身份或操作的图片必须有文本等价物。
- 不因平台不同替换为语义不同的图标。

## 未来数值收敛方式

具体字号、间距、Shape、内容宽度和断点只在后续实施阶段确定，并应：

1. 统计当前实现中的高频值和实际职责。
2. 删除纯粹为局部修补产生的重复值。
3. 在亮暗主题、中英文、窄屏、大字体和 expanded 布局中验证。
4. 以语义名称进入 Theme 或 token，而不是以页面名称进入。
5. 在本页补充经过验证的最小值集，不建立过度精细的刻度。
