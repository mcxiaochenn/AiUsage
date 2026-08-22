// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AiUsage';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get accounts => 'Accounts';

  @override
  String get history => 'History';

  @override
  String get settings => 'Settings';

  @override
  String get account => 'Account';

  @override
  String get unknownAccount => 'Unknown account';

  @override
  String get unknownPlan => 'Unknown plan';

  @override
  String get refresh => 'Refresh';

  @override
  String get addAccount => 'Add account';

  @override
  String get addCodexAccount => 'Add a Codex account';

  @override
  String get addCodexAccountMessage =>
      'Use the official OpenAI device sign-in flow. Tokens stay in your system keychain.';

  @override
  String get noUsageSnapshot => 'No usage snapshot yet';

  @override
  String get noUsageSnapshotMessage =>
      'Pull down or use Refresh to request the latest quota.';

  @override
  String get noQuotaWindows =>
      'OpenAI did not return any quota windows for this account.';

  @override
  String get resetCredits => 'Reset Credits';

  @override
  String get resetCreditsReadOnly =>
      'Read-only. This app never consumes credits.';

  @override
  String availableCount(int count) {
    return '$count available';
  }

  @override
  String updatedAt(String relative, String absolute) {
    return 'Updated $relative · $absolute';
  }

  @override
  String usedPercent(int percent) {
    return '$percent% used';
  }

  @override
  String remainingPercent(int percent) {
    return '$percent% remaining';
  }

  @override
  String resetIn(String duration) {
    return 'Reset in $duration';
  }

  @override
  String resetsAt(String time) {
    return 'Resets $time';
  }

  @override
  String get noAccounts => 'No accounts';

  @override
  String get noAccountsMessage => 'Add an account to start monitoring usage.';

  @override
  String lastSuccessfulRefresh(String time) {
    return 'Last successful refresh: $time';
  }

  @override
  String credentialStatus(String status) {
    return 'Credential: $status';
  }

  @override
  String get credentialCleared => 'Cleared';

  @override
  String get credentialAvailable => 'Available in system secure storage';

  @override
  String get never => 'Never';

  @override
  String get logout => 'Logout';

  @override
  String get removeAccount => 'Remove account';

  @override
  String get removeAccountQuestion => 'Remove account?';

  @override
  String get removeAccountExplanation =>
      'This clears its locally stored credential and all local usage history. OpenAI data is not changed.';

  @override
  String get cancel => 'Cancel';

  @override
  String get remove => 'Remove';

  @override
  String get hours24 => '24 hours';

  @override
  String get days7 => '7 days';

  @override
  String get noHistory => 'No history in this period';

  @override
  String get noHistoryMessage =>
      'History is recorded after successful usage refreshes and is retained for 7 days.';

  @override
  String get customLimit => 'Custom limit';

  @override
  String weekLimit(int count) {
    return '$count-week limit';
  }

  @override
  String dayLimit(int count) {
    return '$count-day limit';
  }

  @override
  String hourLimit(int count) {
    return '$count-hour limit';
  }

  @override
  String minuteLimit(int count) {
    return '$count-minute limit';
  }

  @override
  String get theme => 'Theme';

  @override
  String get language => 'Language';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get followSystem => 'Follow system';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => 'Simplified Chinese';

  @override
  String get refreshDescription =>
      'Foreground refresh follows this interval. Mobile background refresh is best effort.';

  @override
  String get manual => 'Manual';

  @override
  String minutesShort(int count) {
    return '$count min';
  }

  @override
  String get showResetCredits => 'Show reset credits';

  @override
  String get showResetCreditsDescription =>
      'Read-only availability, never consume or redeem.';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsDescription =>
      '80%, 95%, and reset alerts. Background delivery is best effort.';

  @override
  String get privacy =>
      'Privacy: no analytics, telemetry, cloud sync, or backend. Credentials and history remain on this device.';

  @override
  String showingCachedData(String message) {
    return '$message Showing cached data.';
  }

  @override
  String get details => 'Technical details';

  @override
  String get signInToCodex => 'Sign in to Codex';

  @override
  String get signInFailed => 'Sign-in failed.';

  @override
  String get completeBrowserSignIn =>
      'Complete sign-in in your browser, then enter this code if requested:';

  @override
  String codeExpiresIn(String duration) {
    return 'Code expires in $duration';
  }

  @override
  String get browserPasteHint =>
      'If your browser blocks paste, enter the code manually. The app will continue checking automatically.';

  @override
  String get lastCheckFailed => 'Last check failed.';

  @override
  String get copyCode => 'Copy code';

  @override
  String get codeCopied => 'Code copied.';

  @override
  String get openBrowser => 'Open browser';

  @override
  String get newCode => 'Get a new code';

  @override
  String get codeExpired => 'This sign-in code has expired.';

  @override
  String get browserOpenFailed => 'Unable to open the browser.';

  @override
  String get signInWithBrowser => 'Sign in with browser';

  @override
  String get deviceCodeRecommended => 'Recommended · OpenAI Device Code flow';

  @override
  String get importAuthJson => 'Import auth.json';

  @override
  String get authJsonAdvanced => 'Advanced · Tokens are stored securely';

  @override
  String get authFileLabel => 'Codex auth.json';

  @override
  String get accountImported => 'Account imported.';

  @override
  String get authImportInvalid =>
      'The selected auth.json is invalid or incomplete.';

  @override
  String get authImportApiKeyOnly =>
      'API Key-only auth.json files are not supported.';

  @override
  String get authImportTooLarge =>
      'The selected auth.json exceeds the 1 MiB limit.';

  @override
  String get authImportFailed => 'Unable to import auth.json.';

  @override
  String get now => 'now';

  @override
  String daysHours(int days, int hours) {
    return '${days}d ${hours}h';
  }

  @override
  String hoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String minutesOnly(int minutes) {
    return '${minutes}m';
  }

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get unavailable => 'Unavailable';

  @override
  String get signedIn => 'Signed in';

  @override
  String get signedOut => 'Signed out';

  @override
  String get expired => 'Expired';

  @override
  String get stateStale => 'Unable to refresh.';

  @override
  String get stateAuthExpired => 'Sign-in expired. Add the account again.';

  @override
  String get stateOffline => 'You appear to be offline.';

  @override
  String get stateRateLimited =>
      'OpenAI asked the app to wait before retrying.';

  @override
  String get stateServerError => 'OpenAI returned a server error.';

  @override
  String get stateParseError =>
      'OpenAI returned an unsupported usage response.';

  @override
  String get storageInitFailed => 'Unable to initialize local storage.';

  @override
  String get demoData => 'Demo data';

  @override
  String get extraCredits => 'Extra credits';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get balanceUnavailable => 'Balance unavailable';

  @override
  String get creditsAvailable => 'Credits available';

  @override
  String get noCredits => 'No credits available';

  @override
  String earliestExpiry(String time) {
    return 'Earliest expiry: $time';
  }

  @override
  String get expiryUnavailable => 'Expiry time unavailable';

  @override
  String get accountDetails => 'Account details';

  @override
  String get back => 'Back';

  @override
  String get email => 'Email';

  @override
  String get plan => 'Plan';

  @override
  String get loginStatus => 'Login status';

  @override
  String get credential => 'Credential';

  @override
  String get lastRefresh => 'Last refresh';

  @override
  String get fedramp => 'FedRAMP';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get registrationTime => 'Registration time';

  @override
  String get registeredDays => 'Registered days';

  @override
  String daysCount(int count) {
    return '$count days';
  }

  @override
  String get accountDetailsUnavailable =>
      'Account registration details are unavailable';

  @override
  String get retry => 'Retry';

  @override
  String get tokenActivity => 'Token activity';

  @override
  String get profileMayLag =>
      'Account-side Profile statistics can lag behind current-day activity and are not real-time billing data.';

  @override
  String get profileUnavailable => 'Profile statistics unavailable';

  @override
  String profileUpdatedAt(String time) {
    return 'Profile updated $time';
  }

  @override
  String get showingCachedProfile =>
      'The latest request failed; showing cached Profile data.';

  @override
  String get lifetimeTokens => 'Lifetime tokens';

  @override
  String get peakDailyTokens => 'Peak daily tokens';

  @override
  String get longestTask => 'Longest task';

  @override
  String get currentStreak => 'Current streak';

  @override
  String get longestStreak => 'Longest streak';

  @override
  String get dailyTokenHeatmap => 'Daily token heatmap';

  @override
  String get noTokenBuckets => 'The Profile API returned no daily buckets.';

  @override
  String get heatmapLegend =>
      'Lighter to darker cells represent lower to higher daily token usage.';

  @override
  String get dynamicColor => 'Dynamic color';

  @override
  String get dynamicColorDescription =>
      'Use system wallpaper colors when supported. Off by default.';

  @override
  String get demoMode => 'Experience demo';

  @override
  String get demoModeDescription =>
      'Show synthetic account, quota, profile, and history data without network requests.';

  @override
  String get backgroundRefresh => 'Background automatic refresh';

  @override
  String get backgroundRefreshDescription =>
      'Off by default. Foreground refresh interval remains independent.';

  @override
  String get backgroundWarningTitle => 'Allow background refresh?';

  @override
  String get backgroundWarningMessage =>
      'Background work may increase battery use. Allow AiUsage to run in the background and remove battery restrictions in system settings. Android vendor settings cannot yet be detected automatically.';

  @override
  String get appSettings => 'App settings';

  @override
  String get batterySettings => 'Battery settings';

  @override
  String get backgroundConfirmed =>
      'I have reviewed and allowed the required system settings.';

  @override
  String get enable => 'Enable';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get diagnosticsDescription =>
      'View the latest 200 redacted synchronization records.';

  @override
  String get diagnosticsPrivacy =>
      'Authorization, OAuth tokens, and raw account IDs are never recorded. Raw responses may contain account profile information and are collapsed by default.';

  @override
  String get noDiagnostics => 'No synchronization records';

  @override
  String get noDiagnosticsDescription =>
      'Records appear after usage, Profile, or account-detail requests.';

  @override
  String get emptyResponse => 'No response body was recorded.';

  @override
  String get responseTruncated =>
      'Response truncated at the 64 KiB privacy and storage limit.';

  @override
  String get syncManual => 'Manual';

  @override
  String get syncResume => 'App resume';

  @override
  String get syncForeground => 'Foreground timer';

  @override
  String get syncBackground => 'Background';

  @override
  String get syncPageLoad => 'Page load';
}
