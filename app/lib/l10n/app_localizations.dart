import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AiUsage'**
  String get appTitle;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @unknownAccount.
  ///
  /// In en, this message translates to:
  /// **'Unknown account'**
  String get unknownAccount;

  /// No description provided for @unknownPlan.
  ///
  /// In en, this message translates to:
  /// **'Unknown plan'**
  String get unknownPlan;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccount;

  /// No description provided for @addCodexAccount.
  ///
  /// In en, this message translates to:
  /// **'Add a Codex account'**
  String get addCodexAccount;

  /// No description provided for @addCodexAccountMessage.
  ///
  /// In en, this message translates to:
  /// **'Use the official OpenAI device sign-in flow. Tokens stay in your system keychain.'**
  String get addCodexAccountMessage;

  /// No description provided for @noUsageSnapshot.
  ///
  /// In en, this message translates to:
  /// **'No usage snapshot yet'**
  String get noUsageSnapshot;

  /// No description provided for @noUsageSnapshotMessage.
  ///
  /// In en, this message translates to:
  /// **'Pull down or use Refresh to request the latest quota.'**
  String get noUsageSnapshotMessage;

  /// No description provided for @noQuotaWindows.
  ///
  /// In en, this message translates to:
  /// **'OpenAI did not return any quota windows for this account.'**
  String get noQuotaWindows;

  /// No description provided for @resetCredits.
  ///
  /// In en, this message translates to:
  /// **'Reset Credits'**
  String get resetCredits;

  /// No description provided for @resetCreditsReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read-only. This app never consumes credits.'**
  String get resetCreditsReadOnly;

  /// No description provided for @availableCount.
  ///
  /// In en, this message translates to:
  /// **'{count} available'**
  String availableCount(int count);

  /// No description provided for @updatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {relative} · {absolute}'**
  String updatedAt(String relative, String absolute);

  /// No description provided for @usedPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% used'**
  String usedPercent(int percent);

  /// No description provided for @remainingPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% remaining'**
  String remainingPercent(int percent);

  /// No description provided for @resetIn.
  ///
  /// In en, this message translates to:
  /// **'Reset in {duration}'**
  String resetIn(String duration);

  /// No description provided for @resetsAt.
  ///
  /// In en, this message translates to:
  /// **'Resets {time}'**
  String resetsAt(String time);

  /// No description provided for @noAccounts.
  ///
  /// In en, this message translates to:
  /// **'No accounts'**
  String get noAccounts;

  /// No description provided for @noAccountsMessage.
  ///
  /// In en, this message translates to:
  /// **'Add an account to start monitoring usage.'**
  String get noAccountsMessage;

  /// No description provided for @lastSuccessfulRefresh.
  ///
  /// In en, this message translates to:
  /// **'Last successful refresh: {time}'**
  String lastSuccessfulRefresh(String time);

  /// No description provided for @credentialStatus.
  ///
  /// In en, this message translates to:
  /// **'Credential: {status}'**
  String credentialStatus(String status);

  /// No description provided for @credentialCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get credentialCleared;

  /// No description provided for @credentialAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available in system secure storage'**
  String get credentialAvailable;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get removeAccount;

  /// No description provided for @removeAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove account?'**
  String get removeAccountQuestion;

  /// No description provided for @removeAccountExplanation.
  ///
  /// In en, this message translates to:
  /// **'This clears its locally stored credential and all local usage history. OpenAI data is not changed.'**
  String get removeAccountExplanation;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @hours24.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get hours24;

  /// No description provided for @days7.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get days7;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No history in this period'**
  String get noHistory;

  /// No description provided for @noHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'History is recorded after successful usage refreshes and is retained for 7 days.'**
  String get noHistoryMessage;

  /// No description provided for @customLimit.
  ///
  /// In en, this message translates to:
  /// **'Custom limit'**
  String get customLimit;

  /// No description provided for @weekLimit.
  ///
  /// In en, this message translates to:
  /// **'{count}-week limit'**
  String weekLimit(int count);

  /// No description provided for @dayLimit.
  ///
  /// In en, this message translates to:
  /// **'{count}-day limit'**
  String dayLimit(int count);

  /// No description provided for @hourLimit.
  ///
  /// In en, this message translates to:
  /// **'{count}-hour limit'**
  String hourLimit(int count);

  /// No description provided for @minuteLimit.
  ///
  /// In en, this message translates to:
  /// **'{count}-minute limit'**
  String minuteLimit(int count);

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get simplifiedChinese;

  /// No description provided for @refreshDescription.
  ///
  /// In en, this message translates to:
  /// **'Foreground refresh follows this interval. Mobile background refresh is best effort.'**
  String get refreshDescription;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesShort(int count);

  /// No description provided for @showResetCredits.
  ///
  /// In en, this message translates to:
  /// **'Show reset credits'**
  String get showResetCredits;

  /// No description provided for @showResetCreditsDescription.
  ///
  /// In en, this message translates to:
  /// **'Read-only availability, never consume or redeem.'**
  String get showResetCreditsDescription;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'80%, 95%, and reset alerts. Background delivery is best effort.'**
  String get notificationsDescription;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy: no analytics, telemetry, cloud sync, or backend. Credentials and history remain on this device.'**
  String get privacy;

  /// No description provided for @showingCachedData.
  ///
  /// In en, this message translates to:
  /// **'{message} Showing cached data.'**
  String showingCachedData(String message);

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get details;

  /// No description provided for @signInToCodex.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Codex'**
  String get signInToCodex;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed.'**
  String get signInFailed;

  /// No description provided for @completeBrowserSignIn.
  ///
  /// In en, this message translates to:
  /// **'Complete sign-in in your browser, then enter this code if requested:'**
  String get completeBrowserSignIn;

  /// No description provided for @codeExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Code expires in {duration}'**
  String codeExpiresIn(String duration);

  /// No description provided for @browserPasteHint.
  ///
  /// In en, this message translates to:
  /// **'If your browser blocks paste, enter the code manually. The app will continue checking automatically.'**
  String get browserPasteHint;

  /// No description provided for @lastCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Last check failed.'**
  String get lastCheckFailed;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied.'**
  String get codeCopied;

  /// No description provided for @openBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open browser'**
  String get openBrowser;

  /// No description provided for @newCode.
  ///
  /// In en, this message translates to:
  /// **'Get a new code'**
  String get newCode;

  /// No description provided for @codeExpired.
  ///
  /// In en, this message translates to:
  /// **'This sign-in code has expired.'**
  String get codeExpired;

  /// No description provided for @browserOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the browser.'**
  String get browserOpenFailed;

  /// No description provided for @signInWithBrowser.
  ///
  /// In en, this message translates to:
  /// **'Sign in with browser'**
  String get signInWithBrowser;

  /// No description provided for @deviceCodeRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended · OpenAI Device Code flow'**
  String get deviceCodeRecommended;

  /// No description provided for @importAuthJson.
  ///
  /// In en, this message translates to:
  /// **'Import auth.json'**
  String get importAuthJson;

  /// No description provided for @authJsonAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced · Tokens are stored securely'**
  String get authJsonAdvanced;

  /// No description provided for @authFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Codex auth.json'**
  String get authFileLabel;

  /// No description provided for @accountImported.
  ///
  /// In en, this message translates to:
  /// **'Account imported.'**
  String get accountImported;

  /// No description provided for @authImportInvalid.
  ///
  /// In en, this message translates to:
  /// **'The selected auth.json is invalid or incomplete.'**
  String get authImportInvalid;

  /// No description provided for @authImportApiKeyOnly.
  ///
  /// In en, this message translates to:
  /// **'API Key-only auth.json files are not supported.'**
  String get authImportApiKeyOnly;

  /// No description provided for @authImportTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The selected auth.json exceeds the 1 MiB limit.'**
  String get authImportTooLarge;

  /// No description provided for @authImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to import auth.json.'**
  String get authImportFailed;

  /// No description provided for @now.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get now;

  /// No description provided for @daysHours.
  ///
  /// In en, this message translates to:
  /// **'{days}d {hours}h'**
  String daysHours(int days, int hours);

  /// No description provided for @hoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String hoursMinutes(int hours, int minutes);

  /// No description provided for @minutesOnly.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String minutesOnly(int minutes);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String daysAgo(int count);

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get signedIn;

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get signedOut;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @stateStale.
  ///
  /// In en, this message translates to:
  /// **'Unable to refresh.'**
  String get stateStale;

  /// No description provided for @stateAuthExpired.
  ///
  /// In en, this message translates to:
  /// **'Sign-in expired. Add the account again.'**
  String get stateAuthExpired;

  /// No description provided for @stateOffline.
  ///
  /// In en, this message translates to:
  /// **'You appear to be offline.'**
  String get stateOffline;

  /// No description provided for @stateRateLimited.
  ///
  /// In en, this message translates to:
  /// **'OpenAI asked the app to wait before retrying.'**
  String get stateRateLimited;

  /// No description provided for @stateServerError.
  ///
  /// In en, this message translates to:
  /// **'OpenAI returned a server error.'**
  String get stateServerError;

  /// No description provided for @stateParseError.
  ///
  /// In en, this message translates to:
  /// **'OpenAI returned an unsupported usage response.'**
  String get stateParseError;

  /// No description provided for @storageInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to initialize local storage.'**
  String get storageInitFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
