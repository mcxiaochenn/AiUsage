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
}
