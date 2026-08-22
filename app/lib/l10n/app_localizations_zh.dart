// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AiUsage';

  @override
  String get dashboard => '概览';

  @override
  String get accounts => '账户';

  @override
  String get history => '历史';

  @override
  String get settings => '设置';

  @override
  String get account => '账户';

  @override
  String get unknownAccount => '未知账户';

  @override
  String get unknownPlan => '未知套餐';

  @override
  String get refresh => '刷新';

  @override
  String get addAccount => '添加账户';

  @override
  String get addCodexAccount => '添加 Codex 账户';

  @override
  String get addCodexAccountMessage => '使用 OpenAI 官方设备登录流程，Token 仅保存在系统安全存储中。';

  @override
  String get noUsageSnapshot => '暂无用量快照';

  @override
  String get noUsageSnapshotMessage => '下拉或点击刷新以获取最新额度。';

  @override
  String get noQuotaWindows => 'OpenAI 未返回该账户的额度周期。';

  @override
  String get resetCredits => '重置额度';

  @override
  String get resetCreditsReadOnly => '仅供查看，本应用不会消耗重置额度。';

  @override
  String availableCount(int count) {
    return '可用 $count 次';
  }

  @override
  String updatedAt(String relative, String absolute) {
    return '更新于 $relative · $absolute';
  }

  @override
  String usedPercent(int percent) {
    return '已使用 $percent%';
  }

  @override
  String remainingPercent(int percent) {
    return '剩余 $percent%';
  }

  @override
  String resetIn(String duration) {
    return '$duration 后重置';
  }

  @override
  String resetsAt(String time) {
    return '重置时间 $time';
  }

  @override
  String get noAccounts => '暂无账户';

  @override
  String get noAccountsMessage => '添加账户后即可开始监控用量。';

  @override
  String lastSuccessfulRefresh(String time) {
    return '上次成功刷新：$time';
  }

  @override
  String credentialStatus(String status) {
    return '凭据：$status';
  }

  @override
  String get credentialCleared => '已清除';

  @override
  String get credentialAvailable => '已保存至系统安全存储';

  @override
  String get never => '从未';

  @override
  String get logout => '退出登录';

  @override
  String get removeAccount => '移除账户';

  @override
  String get removeAccountQuestion => '移除账户？';

  @override
  String get removeAccountExplanation =>
      '这会清除本地凭据和该账户的全部本地用量历史，不会修改 OpenAI 上的数据。';

  @override
  String get cancel => '取消';

  @override
  String get remove => '移除';

  @override
  String get hours24 => '24 小时';

  @override
  String get days7 => '7 天';

  @override
  String get noHistory => '该时段暂无历史';

  @override
  String get noHistoryMessage => '成功刷新后会记录历史，并保留 7 天。';

  @override
  String get customLimit => '自定义额度周期';

  @override
  String weekLimit(int count) {
    return '$count 周额度';
  }

  @override
  String dayLimit(int count) {
    return '$count 天额度';
  }

  @override
  String hourLimit(int count) {
    return '$count 小时额度';
  }

  @override
  String minuteLimit(int count) {
    return '$count 分钟额度';
  }

  @override
  String get theme => '主题';

  @override
  String get language => '语言';

  @override
  String get system => '跟随系统';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get followSystem => '跟随系统';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get refreshDescription => '前台按此间隔刷新，移动端后台刷新由系统尽力执行。';

  @override
  String get manual => '手动';

  @override
  String minutesShort(int count) {
    return '$count 分钟';
  }

  @override
  String get showResetCredits => '显示重置额度';

  @override
  String get showResetCreditsDescription => '仅显示可用情况，不会消耗或兑换。';

  @override
  String get notifications => '通知';

  @override
  String get notificationsDescription => '在使用率达到 80%、95% 及额度重置时提醒；后台通知由系统尽力送达。';

  @override
  String get privacy => '隐私：无分析、遥测、云同步或自建后端；凭据与历史只保留在本设备。';

  @override
  String showingCachedData(String message) {
    return '$message 当前显示缓存数据。';
  }

  @override
  String get details => '技术详情';

  @override
  String get signInToCodex => '登录 Codex';

  @override
  String get signInFailed => '登录失败。';

  @override
  String get completeBrowserSignIn => '请在浏览器中完成登录，并在需要时输入以下验证码：';

  @override
  String codeExpiresIn(String duration) {
    return '验证码将在 $duration 后过期';
  }

  @override
  String get browserPasteHint => '如果浏览器禁止粘贴，请手动输入验证码；应用会自动持续检查授权状态。';

  @override
  String get lastCheckFailed => '上次检查失败。';

  @override
  String get copyCode => '复制验证码';

  @override
  String get codeCopied => '验证码已复制。';

  @override
  String get openBrowser => '打开浏览器';

  @override
  String get newCode => '获取新验证码';

  @override
  String get codeExpired => '该登录验证码已过期。';

  @override
  String get browserOpenFailed => '无法打开浏览器。';

  @override
  String get signInWithBrowser => '使用浏览器登录';

  @override
  String get deviceCodeRecommended => '推荐 · OpenAI Device Code 流程';

  @override
  String get importAuthJson => '导入 auth.json';

  @override
  String get authJsonAdvanced => '高级方式 · Token 将安全保存';

  @override
  String get authFileLabel => 'Codex auth.json';

  @override
  String get accountImported => '账户已导入。';

  @override
  String get authImportInvalid => '所选 auth.json 无效或缺少必要字段。';

  @override
  String get authImportApiKeyOnly => '不支持仅含 API Key 的 auth.json。';

  @override
  String get authImportTooLarge => '所选 auth.json 超过 1 MiB 限制。';

  @override
  String get authImportFailed => '无法导入 auth.json。';

  @override
  String get now => '现在';

  @override
  String daysHours(int days, int hours) {
    return '$days 天 $hours 小时';
  }

  @override
  String hoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String minutesOnly(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get unavailable => '不可用';

  @override
  String get signedIn => '已登录';

  @override
  String get signedOut => '已退出';

  @override
  String get expired => '已过期';

  @override
  String get stateStale => '无法刷新。';

  @override
  String get stateAuthExpired => '登录已过期，请重新添加账户。';

  @override
  String get stateOffline => '当前似乎处于离线状态。';

  @override
  String get stateRateLimited => 'OpenAI 要求稍后再试。';

  @override
  String get stateServerError => 'OpenAI 返回了服务错误。';

  @override
  String get stateParseError => 'OpenAI 返回了暂不支持的用量格式。';

  @override
  String get storageInitFailed => '无法初始化本地存储。';

  @override
  String get demoData => '演示数据';

  @override
  String get extraCredits => '额外额度';

  @override
  String get unlimited => '无限额度';

  @override
  String get balanceUnavailable => '余额不可用';

  @override
  String get creditsAvailable => '额度可用';

  @override
  String get noCredits => '暂无额外额度';

  @override
  String earliestExpiry(String time) {
    return '最早到期时间：$time';
  }

  @override
  String get expiryUnavailable => '到期时间不可用';

  @override
  String get accountDetails => '账户详情';

  @override
  String get back => '返回';

  @override
  String get email => '邮箱';

  @override
  String get plan => '套餐';

  @override
  String get loginStatus => '登录状态';

  @override
  String get credential => '凭据';

  @override
  String get lastRefresh => '上次刷新';

  @override
  String get fedramp => 'FedRAMP';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get registrationTime => '注册时间';

  @override
  String get registeredDays => '已注册天数';

  @override
  String daysCount(int count) {
    return '$count 天';
  }

  @override
  String get accountDetailsUnavailable => '暂时无法获取账户注册资料';

  @override
  String get retry => '重试';

  @override
  String get tokenActivity => 'Token 使用统计';

  @override
  String get profileMayLag => '账号侧 Profile 统计可能滞后于当天活动，不能作为实时计费数据。';

  @override
  String get profileUnavailable => 'Profile 统计不可用';

  @override
  String profileUpdatedAt(String time) {
    return 'Profile 更新于 $time';
  }

  @override
  String get showingCachedProfile => '最新请求失败，当前显示缓存的 Profile 数据。';

  @override
  String get lifetimeTokens => '累计 Token';

  @override
  String get peakDailyTokens => '单日峰值 Token';

  @override
  String get longestTask => '最长任务';

  @override
  String get currentStreak => '当前连续使用';

  @override
  String get longestStreak => '最长连续使用';

  @override
  String get dailyTokenHeatmap => '每日 Token 热力图';

  @override
  String get noTokenBuckets => 'Profile API 未返回每日统计。';

  @override
  String get heatmapLegend => '颜色由浅到深表示每日 Token 用量由低到高。';

  @override
  String get dynamicColor => '动态取色';

  @override
  String get dynamicColorDescription => '支持时使用系统壁纸配色，默认关闭。';

  @override
  String get demoMode => '体验演示';

  @override
  String get demoModeDescription => '使用合成账户、额度、Profile 与历史数据展示功能，不发起网络请求。';

  @override
  String get backgroundRefresh => '后台自动刷新';

  @override
  String get backgroundRefreshDescription => '默认关闭，与前台刷新间隔相互独立。';

  @override
  String get backgroundWarningTitle => '允许后台刷新？';

  @override
  String get backgroundWarningMessage =>
      '后台任务可能增加耗电。请在系统设置中允许 AiUsage 后台运行并取消电池限制。当前版本无法自动检测各厂商的自启动设置。';

  @override
  String get appSettings => '应用设置';

  @override
  String get batterySettings => '电池设置';

  @override
  String get backgroundConfirmed => '我已检查并允许所需的系统设置。';

  @override
  String get enable => '启用';

  @override
  String get diagnostics => '诊断';

  @override
  String get diagnosticsDescription => '查看最近 200 条已脱敏同步记录。';

  @override
  String get diagnosticsPrivacy =>
      '不会记录 Authorization、OAuth Token 或原始账户 ID。原始响应可能包含账户资料，默认保持折叠。';

  @override
  String get noDiagnostics => '暂无同步记录';

  @override
  String get noDiagnosticsDescription => '请求额度、Profile 或账户详情后会产生记录。';

  @override
  String get emptyResponse => '未记录响应正文。';

  @override
  String get responseTruncated => '响应已按 64 KiB 隐私与存储上限截断。';

  @override
  String get syncManual => '手动';

  @override
  String get syncResume => '返回前台';

  @override
  String get syncForeground => '前台定时';

  @override
  String get syncBackground => '后台';

  @override
  String get syncPageLoad => '页面加载';
}
