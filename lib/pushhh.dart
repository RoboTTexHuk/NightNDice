import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as n1diceMath;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle, SystemChrome;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as n1diceTimezoneData;
import 'package:timezone/timezone.dart' as n1diceTimezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// n1dice инфраструктура (бывшая Dress Retro инфраструктура)
// ============================================================================

class n1diceLogger {
  const n1diceLogger();

  void n1diceLogInfo(Object n1diceMessage) =>
      debugPrint('[DressRetroLogger] $n1diceMessage');

  void n1diceLogWarn(Object n1diceMessage) =>
      debugPrint('[DressRetroLogger/WARN] $n1diceMessage');

  void n1diceLogError(Object n1diceMessage) =>
      debugPrint('[DressRetroLogger/ERR] $n1diceMessage');
}

class n1diceVault {
  static final n1diceVault sharedInstance = n1diceVault._internalConstructor();
  n1diceVault._internalConstructor();
  factory n1diceVault() => sharedInstance;

  final n1diceLogger n1diceLoggerInstance = const n1diceLogger();
}

// ============================================================================
// Константы (статистика/кеш) — строки в кавычках не меняем
// ============================================================================

const String metrLoadedOnceKey = 'wheel_loaded_once';
const String metrStatEndpoint = 'https://getgame.portalroullete.bar/stat';
const String metrCachedFcmKey = 'wheel_cached_fcm';

// НОВОЕ: ключи для сохранения SafeArea в SharedPreferences
const String n1diceSafeAreaEnabledKey = 'safearea_enabled';
const String n1diceSafeAreaColorKey = 'safearea_color';

// ---------------- Bank constants (из первого main.dart) ----------------

const Set<String> kBankSchemes = {
  'td',
  'rbc',
  'cibc',
  'scotiabank',
  'bmo',
  'bmodigitalbanking',
  'desjardins',
  'tangerine',
  'nationalbank',
  'simplii',
  'dominotoronto',
};

const Set<String> kBankDomains = {
  'td.com',
  'tdcanadatrust.com',
  'easyweb.td.com',
  'rbc.com',
  'royalbank.com',
  'online.royalbank.com',
  'cibc.com',
  'cibc.ca',
  'online.cibc.com',
  'scotiabank.com',
  'scotiaonline.scotiabank.com',
  'bmo.com',
  'bmo.ca',
  'bmodigitalbanking.com',
  'desjardins.com',
  'tangerine.ca',
  'nbc.ca',
  'nationalbank.ca',
  'simplii.com',
  'simplii.ca',
  'dominotoronto.com',
  'dominobank.com',
};

// ============================================================================
// Утилиты: n1diceKit (бывший DressRetroKit)
// ============================================================================

class n1diceKit {
  static bool n1diceLooksLikeBareMail(Uri n1diceUri) {
    final String n1diceScheme = n1diceUri.scheme;
    if (n1diceScheme.isNotEmpty) return false;
    final String n1diceRaw = n1diceUri.toString();
    return n1diceRaw.contains('@') && !n1diceRaw.contains(' ');
  }

  static Uri n1diceToMailto(Uri n1diceUri) {
    final String n1diceFull = n1diceUri.toString();
    final List<String> n1diceBits = n1diceFull.split('?');
    final String n1diceWho = n1diceBits.first;
    final Map<String, String> n1diceQuery =
    n1diceBits.length > 1 ? Uri.splitQueryString(n1diceBits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: n1diceWho,
      queryParameters: n1diceQuery.isEmpty ? null : n1diceQuery,
    );
  }

  static Uri n1diceGmailize(Uri n1diceMailUri) {
    final Map<String, String> n1diceQp = n1diceMailUri.queryParameters;
    final Map<String, String> n1diceParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (n1diceMailUri.path.isNotEmpty) 'to': n1diceMailUri.path,
      if ((n1diceQp['subject'] ?? '').isNotEmpty) 'su': n1diceQp['subject']!,
      if ((n1diceQp['body'] ?? '').isNotEmpty) 'body': n1diceQp['body']!,
      if ((n1diceQp['cc'] ?? '').isNotEmpty) 'cc': n1diceQp['cc']!,
      if ((n1diceQp['bcc'] ?? '').isNotEmpty) 'bcc': n1diceQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', n1diceParams);
  }

  static String n1diceDigitsOnly(String n1diceSource) =>
      n1diceSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: n1diceLinker (бывший DressRetroLinker)
// ============================================================================

class n1diceLinker {
  static Future<bool> n1diceOpen(Uri n1diceUri) async {
    try {
      if (await launchUrl(
        n1diceUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        n1diceUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (n1diceError) {
      debugPrint('DressRetroLinker error: $n1diceError; url=$n1diceUri');
      try {
        return await launchUrl(
          n1diceUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// Bank helpers (из первого main.dart)
// ============================================================================

bool n1diceIsBankScheme(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  return kBankSchemes.contains(scheme);
}

bool n1diceIsBankDomain(Uri uri) {
  final String host = uri.host.toLowerCase();
  if (host.isEmpty) return false;

  for (final String bank in kBankDomains) {
    final String bankHost = bank.toLowerCase();
    if (host == bankHost || host.endsWith('.$bankHost')) {
      return true;
    }
  }
  return false;
}

Future<bool> n1diceOpenBank(Uri uri) async {
  try {
    if (n1diceIsBankScheme(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        n1diceIsBankDomain(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }
  } catch (e) {
    debugPrint('n1diceOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// FCM Background Handler
// ============================================================================

@pragma('vm:entry-point')
Future<void> n1diceFcmBackgroundHandler(RemoteMessage n1diceMessage) async {
  debugPrint("Spin ID: ${n1diceMessage.messageId}");
  debugPrint("Spin Data: ${n1diceMessage.data}");
}

// ============================================================================
// n1diceDeviceProfile (бывший DressRetroDeviceProfile)
// ============================================================================

class n1diceDeviceProfile {
  String? n1diceDeviceId;
  String? n1diceSessionId = 'wheel-one-off';
  String? n1dicePlatformKind;
  String? n1diceOsBuild;
  String? n1diceAppVersion;
  String? n1diceLocaleCode;
  String? n1diceTimezoneName;
  bool n1dicePushEnabled = true;

  // Новый UA из WebView
  String? n1diceBaseUserAgent;

  // Для SafeArea (поддержка, аналогичная первому main.dart)
  bool n1diceSafeAreaEnabled = false;
  String? n1diceSafeAreaColor;

  Future<void> n1diceInitialize() async {
    // Инициализация таймзон (если еще не)
    try {
      n1diceTimezoneData.initializeTimeZones();
    } catch (_) {
      // игнор, если уже инициализировано
    }

    final DeviceInfoPlugin n1diceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo n1diceAndroidInfo =
      await n1diceInfoPlugin.androidInfo;
      n1diceDeviceId = n1diceAndroidInfo.id;
      n1dicePlatformKind = 'android';
      n1diceOsBuild = n1diceAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo n1diceIosInfo = await n1diceInfoPlugin.iosInfo;
      n1diceDeviceId = n1diceIosInfo.identifierForVendor;
      n1dicePlatformKind = 'ios';
      n1diceOsBuild = n1diceIosInfo.systemVersion;
    }

    final PackageInfo n1dicePackageInfo = await PackageInfo.fromPlatform();
    n1diceAppVersion = n1dicePackageInfo.version;
    n1diceLocaleCode = Platform.localeName.split('_').first;
    n1diceTimezoneName = n1diceTimezone.local.name;
    n1diceSessionId = 'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> n1diceAsMap({String? n1diceFcmToken}) =>
      <String, dynamic>{
        'fcm_token': n1diceFcmToken ?? 'missing_token',
        'device_id': n1diceDeviceId ?? 'missing_id',
        'app_name': 'joiler',
        'instance_id': n1diceSessionId ?? 'missing_session',
        'platform': n1dicePlatformKind ?? 'missing_system',
        'os_version': n1diceOsBuild ?? 'missing_build',
        'app_version': n1diceAppVersion ?? 'missing_app',
        'language': n1diceLocaleCode ?? 'en',
        'timezone': n1diceTimezoneName ?? 'UTC',
        'push_enabled': n1dicePushEnabled,
        "fthcashier": "true",
        'safearea': n1diceSafeAreaEnabled,
        'safearea_color': n1diceSafeAreaColor ?? '',
        'base_ua': n1diceBaseUserAgent ?? '',
      };
}

// ============================================================================
// AppsFlyer шпион: n1diceSpy (бывший DressRetroSpy)
// ============================================================================

class n1diceSpy {
  AppsFlyerOptions? n1diceOptions;
  AppsflyerSdk? n1diceSdk;

  String n1diceAppsFlyerUid = '';
  String n1diceAppsFlyerData = '';

  void n1diceStart({VoidCallback? n1diceOnUpdate}) {
    final AppsFlyerOptions n1diceOpts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    n1diceOptions = n1diceOpts;
    n1diceSdk = AppsflyerSdk(n1diceOpts);

    n1diceSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    n1diceSdk?.startSDK(
      onSuccess: () => n1diceVault()
          .n1diceLoggerInstance
          .n1diceLogInfo('WheelSpy started'),
      onError: (n1diceCode, n1diceMsg) => n1diceVault()
          .n1diceLoggerInstance
          .n1diceLogError('WheelSpy error $n1diceCode: $n1diceMsg'),
    );

    n1diceSdk?.onInstallConversionData((n1diceValue) {
      n1diceAppsFlyerData = n1diceValue.toString();
      n1diceOnUpdate?.call();
    });

    n1diceSdk?.getAppsFlyerUID().then((n1diceValue) {
      n1diceAppsFlyerUid = n1diceValue.toString();
      n1diceOnUpdate?.call();
    });
  }
}

// ============================================================================
// Мост для FCM токена: n1diceFcmBridge (бывший DressRetroFcmBridge)
// ============================================================================

class n1diceFcmBridge {
  final n1diceLogger n1diceLog = const n1diceLogger();
  String? n1diceToken;
  final List<void Function(String)> n1diceWaiters = <void Function(String)>[];

  String? get n1diceCurrentToken => n1diceToken;

  n1diceFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall n1diceCall) async {
      if (n1diceCall.method == 'setToken') {
        final String n1diceTokenString = n1diceCall.arguments as String;
        if (n1diceTokenString.isNotEmpty) {
          n1diceSetToken(n1diceTokenString);
        }
      }
    });

    n1diceRestoreToken();
  }

  Future<void> n1diceRestoreToken() async {
    try {
      final SharedPreferences n1dicePrefs =
      await SharedPreferences.getInstance();
      final String? n1diceCached = n1dicePrefs.getString(metrCachedFcmKey);
      if (n1diceCached != null && n1diceCached.isNotEmpty) {
        n1diceSetToken(n1diceCached, n1diceNotify: false);
      }
    } catch (_) {}
  }

  Future<void> n1dicePersistToken(String n1diceNewToken) async {
    try {
      final SharedPreferences n1dicePrefs =
      await SharedPreferences.getInstance();
      await n1dicePrefs.setString(metrCachedFcmKey, n1diceNewToken);
    } catch (_) {}
  }

  void n1diceSetToken(
      String n1diceNewToken, {
        bool n1diceNotify = true,
      }) {
    n1diceToken = n1diceNewToken;
    n1dicePersistToken(n1diceNewToken);
    if (n1diceNotify) {
      for (final void Function(String) n1diceCallback
      in List<void Function(String)>.from(n1diceWaiters)) {
        try {
          n1diceCallback(n1diceNewToken);
        } catch (n1diceErr) {
          n1diceLog.n1diceLogWarn('fcm waiter error: $n1diceErr');
        }
      }
      n1diceWaiters.clear();
    }
  }

  Future<void> n1diceWaitForToken(
      Function(String n1diceTokenValue) n1diceOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((n1diceToken ?? '').isNotEmpty) {
        n1diceOnToken(n1diceToken!);
        return;
      }

      n1diceWaiters.add(n1diceOnToken);
    } catch (n1diceErr) {
      n1diceLog.n1diceLogError('wheelWaitToken error: $n1diceErr');
    }
  }
}

// ============================================================================
// n1diceLoader (новый лоадер)
// ============================================================================

class n1diceLoader extends StatefulWidget {
  const n1diceLoader({Key? key}) : super(key: key);

  @override
  State<n1diceLoader> createState() => _n1diceLoaderState();
}

class _n1diceLoaderState extends State<n1diceLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController n1diceController;

  static const Color n1diceBackgroundColor = Color(0xFF05071B);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    n1diceController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    n1diceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: n1diceBackgroundColor,
      child: AnimatedBuilder(
        animation: n1diceController,
        builder: (BuildContext context, Widget? child) {
          final double n1dicePhase =
              n1diceController.value * 2 * n1diceMath.pi;
          return CustomPaint(
            painter: n1diceLoaderPainter(
              n1dicePhase: n1dicePhase,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class n1diceLoaderPainter extends CustomPainter {
  final double n1dicePhase;

  n1diceLoaderPainter({
    required this.n1dicePhase,
  });

  @override
  void paint(Canvas n1diceCanvas, Size n1diceSize) {
    final double n1diceWidth = n1diceSize.width;
    final double n1diceHeight = n1diceSize.height;

    final Paint n1diceBackgroundPaint = Paint()
      ..color = const Color(0xFF05071B)
      ..style = PaintingStyle.fill;
    n1diceCanvas.drawRect(Offset.zero & n1diceSize, n1diceBackgroundPaint);

    final double n1dicePulse = (n1diceMath.sin(n1dicePhase) + 1) / 2;

    final Paint n1diceCirclePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.red.withOpacity(0.14 + 0.16 * n1dicePulse),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(n1diceWidth * 0.5, n1diceHeight * 0.45),
          radius: n1diceHeight * (0.4 + 0.15 * n1dicePulse),
        ),
      );

    n1diceCanvas.drawCircle(
      Offset(n1diceWidth * 0.5, n1diceHeight * 0.45),
      n1diceHeight * (0.4 + 0.15 * n1dicePulse),
      n1diceCirclePaint,
    );

    final Paint n1diceOuterPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.redAccent.withOpacity(0.10 + 0.10 * (1 - n1dicePulse)),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(n1diceWidth * 0.5, n1diceHeight * 0.45),
          radius: n1diceHeight * (0.55 + 0.10 * (1 - n1dicePulse)),
        ),
      );
    n1diceCanvas.drawCircle(
      Offset(n1diceWidth * 0.5, n1diceHeight * 0.45),
      n1diceHeight * (0.55 + 0.10 * (1 - n1dicePulse)),
      n1diceOuterPaint,
    );

    final double n1diceBaseSize = n1diceWidth * 0.35;
    final double n1diceFontSize =
        n1diceBaseSize + n1dicePulse * (n1diceBaseSize * 0.15);

    const String n1diceLetter = 'N';
    const String n1diceWord = 'CUP';

    final TextPainter n1diceLetterPainter = TextPainter(
      text: TextSpan(
        text: n1diceLetter,
        style: TextStyle(
          fontSize: n1diceFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.red.shade600,
          letterSpacing: 4,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.8),
              blurRadius: 22 + 18 * n1dicePulse,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: n1diceWidth);

    final double n1diceLetterX =
        (n1diceWidth - n1diceLetterPainter.width) / 2;
    final double n1diceLetterY =
        (n1diceHeight - n1diceLetterPainter.height) / 2;

    final Offset n1diceLetterOffset =
    Offset(n1diceLetterX, n1diceLetterY);

    final Rect n1diceLetterRect = Rect.fromCenter(
      center: Offset(n1diceWidth / 2, n1diceHeight / 2),
      width: n1diceLetterPainter.width * 1.4,
      height: n1diceLetterPainter.height * 1.6,
    );

    final Paint n1diceGlowPaint = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        28 + 24 * n1dicePulse,
      )
      ..color = Colors.red.withOpacity(0.7 + 0.2 * n1dicePulse);

    n1diceCanvas.saveLayer(n1diceLetterRect, n1diceGlowPaint);
    n1diceLetterPainter.paint(n1diceCanvas, n1diceLetterOffset);
    n1diceCanvas.restore();

    n1diceLetterPainter.paint(n1diceCanvas, n1diceLetterOffset);

    final double n1diceCupFontSize = n1diceWidth * 0.11;

    final TextPainter n1diceCupPainterReal = TextPainter(
      text: TextSpan(
        text: n1diceWord,
        style: TextStyle(
          fontSize: n1diceCupFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red.shade100.withOpacity(0.95),
          letterSpacing: 5,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.7),
              blurRadius: 12 + 10 * n1dicePulse,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: n1diceWidth);

    final double n1diceCupX =
        (n1diceWidth - n1diceCupPainterReal.width) / 2;
    final double n1diceCupY =
        n1diceLetterY + n1diceLetterPainter.height + n1diceHeight * 0.03;

    final Offset n1diceCupOffset = Offset(n1diceCupX, n1diceCupY);
    n1diceCupPainterReal.paint(n1diceCanvas, n1diceCupOffset);
  }

  @override
  bool shouldRepaint(covariant n1diceLoaderPainter n1diceOldDelegate) =>
      n1diceOldDelegate.n1dicePhase != n1dicePhase;
}

// ============================================================================
// Статистика (n1diceFinalUrl / n1dicePostStat) — строки не меняем
// ============================================================================

Future<String> n1diceFinalUrl(
    String n1diceStartUrl, {
      int n1diceMaxHops = 10,
    }) async {
  final HttpClient n1diceClient = HttpClient();

  try {
    Uri n1diceCurrentUri = Uri.parse(n1diceStartUrl);

    for (int n1diceI = 0; n1diceI < n1diceMaxHops; n1diceI++) {
      final HttpClientRequest n1diceRequest =
      await n1diceClient.getUrl(n1diceCurrentUri);
      n1diceRequest.followRedirects = false;
      final HttpClientResponse n1diceResponse =
      await n1diceRequest.close();

      if (n1diceResponse.isRedirect) {
        final String? n1diceLoc =
        n1diceResponse.headers.value(HttpHeaders.locationHeader);
        if (n1diceLoc == null || n1diceLoc.isEmpty) break;

        final Uri n1diceNextUri = Uri.parse(n1diceLoc);
        n1diceCurrentUri = n1diceNextUri.hasScheme
            ? n1diceNextUri
            : n1diceCurrentUri.resolveUri(n1diceNextUri);
        continue;
      }

      return n1diceCurrentUri.toString();
    }

    return n1diceCurrentUri.toString();
  } catch (n1diceError) {
    debugPrint('wheelFinalUrl error: $n1diceError');
    return n1diceStartUrl;
  } finally {
    n1diceClient.close(force: true);
  }
}

Future<void> n1dicePostStat({
  required String n1diceEvent,
  required int n1diceTimeStart,
  required String n1diceUrl,
  required int n1diceTimeFinish,
  required String n1diceAppSid,
  int? n1diceFirstPageTs,
}) async {
  try {
    final String n1diceResolvedUrl = await n1diceFinalUrl(n1diceUrl);
    final Map<String, dynamic> n1dicePayload = <String, dynamic>{
      'event': n1diceEvent,
      'timestart': n1diceTimeStart,
      'timefinsh': n1diceTimeFinish,
      'url': n1diceResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$n1diceAppSid/$n1diceTimeStart',
    };

    debugPrint('wheelStat $n1dicePayload');

    final http.Response n1diceResp = await http.post(
      Uri.parse('$metrStatEndpoint/$n1diceAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(n1dicePayload),
    );

    debugPrint(
        'wheelStat resp=${n1diceResp.statusCode} body=${n1diceResp.body}');
  } catch (n1diceError) {
    debugPrint('wheelPostStat error: $n1diceError');
  }
}

// ============================================================================
// WebView-экран: n1diceTableView (бывший DressRetroTableView)
// С ДОБАВЛЕННЫМ функционалом: соцсети, банки, UserAgent, SafeArea, localStorage, popup.
// ============================================================================

class n1diceTableView extends StatefulWidget with WidgetsBindingObserver {
  String n1diceStartingUrl;
  n1diceTableView(this.n1diceStartingUrl, {super.key});

  @override
  State<n1diceTableView> createState() =>
      _n1diceTableViewState(n1diceStartingUrl);
}

class _n1diceTableViewState extends State<n1diceTableView>
    with WidgetsBindingObserver {
  _n1diceTableViewState(this.n1diceCurrentUrl);

  final n1diceVault n1diceVaultInstance = n1diceVault();

  late InAppWebViewController n1diceWebViewController;
  String? n1dicePushToken;
  final n1diceDeviceProfile n1diceDeviceProfileInstance =
  n1diceDeviceProfile();
  final n1diceSpy n1diceSpyInstance = n1diceSpy();

  bool n1diceOverlayBusy = false;
  String n1diceCurrentUrl;
  DateTime? n1diceLastPausedAt;

  bool n1diceLoadedOnceSent = false;
  int? n1diceFirstPageTimestamp;
  int n1diceStartLoadTimestamp = 0;

  // --------- Социальные / внешние хосты / схемы ---------

  final Set<String> n1diceExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> n1diceExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  // расширенный набор "специальных схем" как в первом main.dart
  final Set<String> n1diceSpecialSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  // --------- UserAgent + SafeArea ---------

  String? _baseUserAgent;
  String _currentUserAgent = '';
  String? _serverUserAgent;
  bool _isInGoogleAuth = false;

  bool _safeAreaEnabled = false;
  Color _safeAreaBackgroundColor = Colors.black;

  // --------- POPUP (window.open) ---------

  InAppWebViewController? _popupWebViewController;
  bool _isPopupVisible = false;
  String? _popupUrl;
  CreateWindowAction? _popupCreateAction;
  bool _popupCanGoBack = false;
  String? _popupCurrentUrl;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(n1diceFcmBackgroundHandler);

    n1diceFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    // НОВОЕ: загружаем сохранённые SafeArea/цвет из SharedPreferences
    _loadSafeAreaFromPrefs();

    n1diceInitPushAndGetToken();

    // Инициализируем профиль устройства и после этого пишем в localStorage
    n1diceDeviceProfileInstance.n1diceInitialize().then((_) async {
      if (!mounted) return;
      await _updateLocalStorage();
    });

    n1diceWireForegroundPushHandlers();
    n1diceBindPlatformNotificationTap();
    n1diceSpyInstance.n1diceStart(n1diceOnUpdate: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState n1diceState) {
    if (n1diceState == AppLifecycleState.paused) {
      n1diceLastPausedAt = DateTime.now();
    }
    if (n1diceState == AppLifecycleState.resumed) {
      if (Platform.isIOS && n1diceLastPausedAt != null) {
        final DateTime n1diceNow = DateTime.now();
        final Duration n1diceDrift =
        n1diceNow.difference(n1diceLastPausedAt!);
        if (n1diceDrift > const Duration(minutes: 25)) {
          n1diceForceReloadToLobby();
        }
      }
      n1diceLastPausedAt = null;
    }
  }

  void n1diceForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration n1diceDuration) {
      if (!mounted) return;
      // здесь можно вернуть в MafiaHarbor/CaptainHarbor/BillHarbor при необходимости
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void n1diceWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage n1diceMsg) {
      if (n1diceMsg.data['uri'] != null) {
        n1diceNavigateTo(n1diceMsg.data['uri'].toString());
      } else {
        n1diceReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage n1diceMsg) {
      if (n1diceMsg.data['uri'] != null) {
        n1diceNavigateTo(n1diceMsg.data['uri'].toString());
      } else {
        n1diceReturnToCurrentUrl();
      }
    });
  }

  void n1diceNavigateTo(String n1diceNewUrl) async {
    await n1diceWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(n1diceNewUrl)),
    );
  }

  void n1diceReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      n1diceWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(n1diceCurrentUrl)),
      );
    });
  }

  Future<void> n1diceInitPushAndGetToken() async {
    final FirebaseMessaging n1diceFm = FirebaseMessaging.instance;
    await n1diceFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    n1dicePushToken = await n1diceFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------

  void n1diceBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall n1diceCall) async {
      if (n1diceCall.method == "onNotificationTap") {
        final Map<String, dynamic> n1dicePayload =
        Map<String, dynamic>.from(n1diceCall.arguments);
        debugPrint("URI from platform tap: ${n1dicePayload['uri']}");
        final String? n1diceUriString =
        n1dicePayload["uri"]?.toString();
        if (n1diceUriString != null &&
            !n1diceUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext n1diceContext) =>
                  n1diceTableView(n1diceUriString),
            ),
                (Route<dynamic> n1diceRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // localStorage: запись профиля устройства
  // --------------------------------------------------------------------------

  Future<void> _updateLocalStorage() async {
    try {
      final Map<String, dynamic> data =
      n1diceDeviceProfileInstance.n1diceAsMap(
        n1diceFcmToken: n1dicePushToken,
      );

      final String json = jsonEncode(data);

      await n1diceWebViewController.evaluateJavascript(
        source:
        "localStorage.setItem('app_data', JSON.stringify($json));",
      );

      n1diceVaultInstance.n1diceLoggerInstance
          .n1diceLogInfo('app_data saved to localStorage: $json');
    } catch (e, st) {
      n1diceVaultInstance.n1diceLoggerInstance
          .n1diceLogError('updateLocalStorage error: $e\n$st');
    }
  }

  // === НОВОЕ: восстановление app_data из SharedPreferences в localStorage ===
  Future<void> _restoreAppDataFromPrefsToLocalStorage() async {
    try {
      final SharedPreferences prefs =
      await SharedPreferences.getInstance();
      final String? savedJson = prefs.getString('app_data');
      if (savedJson == null || savedJson.isEmpty) {
        return;
      }

      // savedJson — это JSON-строка; кладём её в JS как объект через JSON.stringify(...)
      final String js =
          "localStorage.setItem('app_data', JSON.stringify($savedJson));";

      await n1diceWebViewController.evaluateJavascript(source: js);

      n1diceVaultInstance.n1diceLoggerInstance.n1diceLogInfo(
          'app_data restored from SharedPreferences to localStorage: $savedJson');
    } catch (e, st) {
      n1diceVaultInstance.n1diceLoggerInstance.n1diceLogError(
          '_restoreAppDataFromPrefsToLocalStorage error: $e\n$st');
    }
  }

  // --------------------------------------------------------------------------
  // UserAgent / SafeArea helpers (адаптировано из первого main.dart)
  // --------------------------------------------------------------------------

  bool _isGoogleUrl(Uri uri) {
    final String full = uri.toString().toLowerCase();
    return full.contains('google');
  }

  Future<void> _applyUserAgent({String? fullua, String? uatail}) async {
    // Берём базовый UA из WebView, если ещё не взяли
    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      try {
        final ua = await n1diceWebViewController.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _baseUserAgent = ua.trim();
          _currentUserAgent = _baseUserAgent!;
          n1diceDeviceProfileInstance.n1diceBaseUserAgent =
              _baseUserAgent;
          n1diceVaultInstance.n1diceLoggerInstance.n1diceLogInfo(
              'Base User-Agent detected: $_baseUserAgent');
        }
      } catch (e) {
        n1diceVaultInstance.n1diceLoggerInstance
            .n1diceLogWarn('Failed to get base userAgent from JS: $e');
      }
    }

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      n1diceVaultInstance.n1diceLoggerInstance
          .n1diceLogWarn('Base User-Agent is null, skip UA update');
      return;
    }

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_baseUserAgent!}/${uatail.trim()}";
    } else {
      newUa = _baseUserAgent!;
    }

    _serverUserAgent = newUa;
    n1diceVaultInstance.n1diceLoggerInstance
        .n1diceLogInfo('Server UA calculated: $_serverUserAgent');
  }

  Future<void> _updateUserAgentFromServerPayload(
      Map<dynamic, dynamic> root) async {
    String? fullua;
    String? uatail;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['fullua'] != null &&
          content['fullua'].toString().trim().isNotEmpty) {
        fullua = content['fullua'].toString().trim();
      }
      if (content['uatail'] != null &&
          content['uatail'].toString().trim().isNotEmpty) {
        uatail = content['uatail'].toString().trim();
      }
    }

    if (fullua == null &&
        root['fullua'] != null &&
        root['fullua'].toString().trim().isNotEmpty) {
      fullua = root['fullua'].toString().trim();
    }
    if (uatail == null &&
        root['uatail'] != null &&
        root['uatail'].toString().trim().isNotEmpty) {
      uatail = root['uatail'].toString().trim();
    }

    if (uatail == null) {
      final dynamic adata = root['adata'];
      if (adata is Map &&
          adata['uatail'] != null &&
          adata['uatail'].toString().trim().isNotEmpty) {
        uatail = adata['uatail'].toString().trim();
      }
    }

    await _applyUserAgent(fullua: fullua, uatail: uatail);
  }

  Future<void> _applyNormalUserAgentIfNeeded() async {
    if (_isInGoogleAuth) {
      n1diceVaultInstance.n1diceLoggerInstance.n1diceLogInfo(
          'Skip normal UA apply because we are in Google auth');
      return;
    }

    final String targetUa = _serverUserAgent ?? _baseUserAgent ?? 'random';

    if (targetUa == _currentUserAgent) return;

    try {
      await n1diceWebViewController.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      debugPrint('[UA] NORMAL WEBVIEW USER AGENT: $_currentUserAgent');
    } catch (e) {
      n1diceVaultInstance.n1diceLoggerInstance
          .n1diceLogError('Error while setting UA "$targetUa": $e');
    }
  }

  Future<void> _addRandomToUserAgentForGoogle() async {
    const String targetUa = 'random';
    if (_currentUserAgent == targetUa && _isInGoogleAuth) return;

    try {
      await n1diceWebViewController.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      _isInGoogleAuth = true;
      debugPrint('[UA] GOOGLE RANDOM USER AGENT: $_currentUserAgent');
    } catch (e) {
      n1diceVaultInstance.n1diceLoggerInstance
          .n1diceLogError('Error setting RANDOM UA for Google: $e');
    }
  }

  Future<void> _restoreUserAgentAfterGoogleIfNeeded() async {
    if (!_isInGoogleAuth) return;
    _isInGoogleAuth = false;
    await _applyNormalUserAgentIfNeeded();
  }

  // Хелпер для парсинга HEX‑цвета (общий для SafeArea и prefs)
  Color _parseHexColor(String hex,
      {Color fallback = const Color(0xFF1A1A22)}) {
    String value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) value = 'FF$value';
    final intColor = int.tryParse(value, radix: 16);
    if (intColor == null) return fallback;
    return Color(intColor);
  }

  // НОВОЕ: загрузка SafeArea из SharedPreferences при старте
  Future<void> _loadSafeAreaFromPrefs() async {
    try {
      final SharedPreferences prefs =
      await SharedPreferences.getInstance();
      final bool enabled =
          prefs.getBool(n1diceSafeAreaEnabledKey) ?? false;
      final String colorHex =
          prefs.getString(n1diceSafeAreaColorKey) ?? '';

      Color bg = Colors.black;
      if (enabled) {
        if (colorHex.isNotEmpty) {
          bg = _parseHexColor(colorHex,
              fallback: const Color(0xFF1A1A22));
        } else {
          bg = const Color(0xFF1A1A22);
        }
      }

      if (!mounted) return;

      setState(() {
        _safeAreaEnabled = enabled;
        _safeAreaBackgroundColor = bg;
        n1diceDeviceProfileInstance.n1diceSafeAreaEnabled = enabled;
        n1diceDeviceProfileInstance.n1diceSafeAreaColor =
        enabled ? (colorHex.isNotEmpty ? colorHex : '#1A1A22') : '';
      });

      n1diceVaultInstance.n1diceLoggerInstance.n1diceLogInfo(
          'SafeArea loaded from prefs: enabled=$enabled, color="$colorHex"');
    } catch (e, st) {
      n1diceVaultInstance.n1diceLoggerInstance.n1diceLogError(
          '_loadSafeAreaFromPrefs error: $e\n$st');
    }
  }

  void _updateSafeAreaFromServerPayload(Map<dynamic, dynamic> root) {
    bool? safearea;
    String? bgLightHex;
    String? bgDarkHex;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['safearea'] != null) {
        final dynamic raw = content['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (content['safearea_color'] != null &&
          content['safearea_color'].toString().trim().isNotEmpty) {
        bgLightHex = content['safearea_color'].toString().trim();
        bgDarkHex = bgLightHex;
      }
    }

    final dynamic adata = root['adata'];
    if (adata is Map) {
      if (safearea == null && adata['safearea'] != null) {
        final dynamic raw = adata['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (adata['bgsareaw'] != null &&
          adata['bgsareaw'].toString().trim().isNotEmpty) {
        bgLightHex = adata['bgsareaw'].toString().trim();
      }
      if (adata['bgsareab'] != null &&
          adata['bgsareab'].toString().trim().isNotEmpty) {
        bgDarkHex = adata['bgsareab'].toString().trim();
      }
    }

    if (safearea == null && root['safearea'] != null) {
      final dynamic raw = root['safearea'];
      if (raw is bool) {
        safearea = raw;
      } else if (raw is String) {
        final String v = raw.toLowerCase().trim();
        if (v == 'true' || v == '1' || v == 'yes') safearea = true;
        if (v == 'false' || v == '0' || v == 'no') safearea = false;
      } else if (raw is num) {
        safearea = raw != 0;
      }
    }

    if (safearea == null) return;

    final Brightness platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHex;
    if (platformBrightness == Brightness.light) {
      chosenHex = bgLightHex ?? bgDarkHex;
    } else {
      chosenHex = bgDarkHex ?? bgLightHex;
    }

    Color background =
    safearea ? const Color(0xFF1A1A22) : Colors.black;

    if (safearea && chosenHex != null && chosenHex.isNotEmpty) {
      background =
          _parseHexColor(chosenHex, fallback: const Color(0xFF1A1A22));
    }

    setState(() {
      _safeAreaEnabled = safearea!;
      _safeAreaBackgroundColor = background;
      n1diceDeviceProfileInstance.n1diceSafeAreaEnabled = safearea;
      n1diceDeviceProfileInstance.n1diceSafeAreaColor =
      safearea ? (chosenHex ?? '#1A1A22') : '';
    });

    // НОВОЕ: сохраняем SafeArea в SharedPreferences при каждом обновлении
    () async {
      try {
        final SharedPreferences prefs =
            await SharedPreferences.getInstance();
        await prefs.setBool(n1diceSafeAreaEnabledKey, safearea!);
        await prefs.setString(
          n1diceSafeAreaColorKey,
          n1diceDeviceProfileInstance.n1diceSafeAreaColor ?? '',
        );
        n1diceVaultInstance.n1diceLoggerInstance.n1diceLogInfo(
          'SafeArea saved to prefs: enabled=$safearea, color="${n1diceDeviceProfileInstance.n1diceSafeAreaColor}"',
        );
      } catch (e, st) {
        n1diceVaultInstance.n1diceLoggerInstance.n1diceLogError(
            'Error saving SafeArea to prefs: $e\n$st');
      }
    }();
  }

  // --------------------------------------------------------------------------
  // POPUP helpers
  // --------------------------------------------------------------------------

  InAppWebViewSettings _popupSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: false,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  void _openPopup(CreateWindowAction req, {String? urlString}) {
    setState(() {
      _popupCreateAction = req;
      _popupUrl = (urlString != null && urlString.isNotEmpty)
          ? urlString
          : req.request.url?.toString();
      _popupCurrentUrl = _popupUrl;
      _isPopupVisible = true;
      _popupCanGoBack = false;
    });
  }

  void _closePopup() {
    setState(() {
      _isPopupVisible = false;
      _popupUrl = null;
      _popupCurrentUrl = null;
      _popupCreateAction = null;
      _popupCanGoBack = false;
      _popupWebViewController = null;
    });
  }

  Future<void> _refreshPopupCanGoBack() async {
    final InAppWebViewController? c = _popupWebViewController;
    if (c == null) {
      if (_popupCanGoBack && mounted) {
        setState(() {
          _popupCanGoBack = false;
        });
      }
      return;
    }
    try {
      final bool can = await c.canGoBack();
      if (!mounted) return;
      if (can != _popupCanGoBack) {
        setState(() {
          _popupCanGoBack = can;
        });
      }
    } catch (_) {}
  }

  Future<void> _handlePopupBackPressed() async {
    final InAppWebViewController? c = _popupWebViewController;
    if (c == null) {
      _closePopup();
      return;
    }
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          _refreshPopupCanGoBack();
        });
      } else {
        _closePopup();
      }
    } catch (_) {
      _closePopup();
    }
  }

  Widget _buildPopupOverlay() {
    if (!_isPopupVisible || (_popupUrl == null && _popupCreateAction == null)) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                color: Colors.black,
                height: 48,
                child: Row(
                  children: [
                    if (_popupCanGoBack)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _handlePopupBackPressed,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _closePopup,
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: InAppWebView(
                windowId: _popupCreateAction?.windowId,
                initialUrlRequest:
                (_popupCreateAction?.windowId == null && _popupUrl != null)
                    ? URLRequest(url: WebUri(_popupUrl!))
                    : null,
                initialSettings: _popupSettings(),
                onWebViewCreated:
                    (InAppWebViewController controller) async {
                  _popupWebViewController = controller;
                },
                onLoadStart: (controller, uri) async {
                  if (uri != null) {
                    setState(() {
                      _popupCurrentUrl = uri.toString();
                    });
                  }
                  await _refreshPopupCanGoBack();
                },
                onLoadStop: (controller, uri) async {
                  if (uri != null) {
                    setState(() {
                      _popupCurrentUrl = uri.toString();
                    });
                  }
                  await _refreshPopupCanGoBack();
                },
                onUpdateVisitedHistory:
                    (controller, url, isReload) async {
                  if (url != null) {
                    setState(() {
                      _popupCurrentUrl = url.toString();
                    });
                  }
                  await _refreshPopupCanGoBack();
                },
                shouldOverrideUrlLoading: (
                    InAppWebViewController controller,
                    NavigationAction nav,
                    ) async {
                  final Uri? uri = nav.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  final String scheme = uri.scheme.toLowerCase();

                  if (n1diceKit.n1diceLooksLikeBareMail(uri)) {
                    final Uri mailto = n1diceKit.n1diceToMailto(uri);
                    await n1diceLinker.n1diceOpen(
                        n1diceKit.n1diceGmailize(mailto));
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'mailto') {
                    await n1diceLinker.n1diceOpen(
                        n1diceKit.n1diceGmailize(uri));
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'tel') {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (n1diceIsBankScheme(uri) ||
                      ((scheme == 'http' || scheme == 'https') &&
                          n1diceIsBankDomain(uri))) {
                    await n1diceOpenBank(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme != 'http' && scheme != 'https') {
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCloseWindow: (controller) {
                  _closePopup();
                },
                onDownloadStartRequest: (controller, req) async {
                  await n1diceLinker.n1diceOpen(req.url);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    n1diceBindPlatformNotificationTap();

    final bool n1diceIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    final Color bgColor = _safeAreaEnabled
        ? _safeAreaBackgroundColor
        : (n1diceIsDark ? Colors.black : Colors.white);

    final Widget webView = InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        disableDefaultErrorPage: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsPictureInPictureMediaPlayback: true,
        useOnDownloadStart: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useShouldOverrideUrlLoading: true,
        supportMultipleWindows: true,
      ),
      initialUrlRequest: URLRequest(
        url: WebUri(n1diceCurrentUrl),
      ),
      onWebViewCreated:
          (InAppWebViewController n1diceController) async {
        n1diceWebViewController = n1diceController;

        // Инициализация UA
        try {
          final ua = await n1diceController.evaluateJavascript(
            source: "navigator.userAgent",
          );
          if (ua is String && ua.trim().isNotEmpty) {
            _baseUserAgent = ua.trim();
            _currentUserAgent = _baseUserAgent!;
            n1diceDeviceProfileInstance.n1diceBaseUserAgent =
                _baseUserAgent;
            debugPrint('[UA] INITIAL: $_baseUserAgent');
          }
        } catch (e) {
          n1diceVaultInstance.n1diceLoggerInstance
              .n1diceLogWarn('Failed to read navigator.userAgent: $e');
        }

        await _applyNormalUserAgentIfNeeded();

        // После создания WebView — актуализируем localStorage
        await _updateLocalStorage();

        // НОВОЕ: через 6 секунд после открытия экрана — восстановление app_data из SharedPreferences
        Future<void>.delayed(const Duration(seconds: 6), () async {
          if (!mounted) return;
          await _restoreAppDataFromPrefsToLocalStorage();
        });

        n1diceWebViewController.addJavaScriptHandler(
          handlerName: 'onServerResponse',
          callback: (List<dynamic> n1diceArgs) {
            n1diceVaultInstance.n1diceLoggerInstance
                .n1diceLogInfo("JS Args: $n1diceArgs");

            try {
              dynamic first =
              n1diceArgs.isNotEmpty ? n1diceArgs[0] : null;

              if (first is List && first.isNotEmpty) {
                first = first.first;
              }

              if (first is Map) {
                final Map<dynamic, dynamic> root = first;

                // safearea + userAgent из сервера
                _updateSafeAreaFromServerPayload(root);
                _updateUserAgentFromServerPayload(root);
                _applyNormalUserAgentIfNeeded();

                // При каждом ответе сервера можно обновлять localStorage
                _updateLocalStorage();
              }

              try {
                return n1diceArgs.reduce((dynamic n1diceV, dynamic n1diceE) =>
                n1diceV + n1diceE);
              } catch (_) {
                return n1diceArgs.toString();
              }
            } catch (e) {
              return n1diceArgs.toString();
            }
          },
        );
      },
      onLoadStart: (
          InAppWebViewController n1diceController,
          Uri? n1diceUri,
          ) async {
        n1diceStartLoadTimestamp =
            DateTime.now().millisecondsSinceEpoch;

        if (n1diceUri != null) {
          if (_isGoogleUrl(n1diceUri)) {
            await _addRandomToUserAgentForGoogle();
          } else {
            await _restoreUserAgentAfterGoogleIfNeeded();
            await _applyNormalUserAgentIfNeeded();
          }

          if (n1diceKit.n1diceLooksLikeBareMail(n1diceUri)) {
            try {
              await n1diceController.stopLoading();
            } catch (_) {}
            final Uri n1diceMailto =
            n1diceKit.n1diceToMailto(n1diceUri);
            await n1diceLinker.n1diceOpen(
              n1diceKit.n1diceGmailize(n1diceMailto),
            );
            return;
          }

          // банки
          if (n1diceIsBankScheme(n1diceUri) ||
              ((n1diceUri.scheme == 'http' ||
                  n1diceUri.scheme == 'https') &&
                  n1diceIsBankDomain(n1diceUri))) {
            try {
              await n1diceController.stopLoading();
            } catch (_) {}
            await n1diceOpenBank(n1diceUri);
            return;
          }

          final String n1diceScheme =
          n1diceUri.scheme.toLowerCase();
          if (n1diceScheme != 'http' && n1diceScheme != 'https') {
            try {
              await n1diceController.stopLoading();
            } catch (_) {}
          }
        }
      },
      onLoadStop: (
          InAppWebViewController n1diceController,
          Uri? n1diceUri,
          ) async {
        await n1diceController.evaluateJavascript(
          source: "console.log('Hello from Roulette JS!');",
        );

        setState(() {
          n1diceCurrentUrl = n1diceUri?.toString() ?? n1diceCurrentUrl;
        });

        await _restoreUserAgentAfterGoogleIfNeeded();
        await _applyNormalUserAgentIfNeeded();

        // После полной загрузки страницы обновляем localStorage
        await _updateLocalStorage();

        // И НОВОЕ: сразу тянем app_data из SharedPreferences в localStorage
        await _restoreAppDataFromPrefsToLocalStorage();

        Future<void>.delayed(const Duration(seconds: 20), () {
          n1diceSendLoadedOnce();
        });
      },
      shouldOverrideUrlLoading: (
          InAppWebViewController n1diceController,
          NavigationAction n1diceNav,
          ) async {
        final Uri? n1diceUri = n1diceNav.request.url;
        if (n1diceUri == null) {
          return NavigationActionPolicy.ALLOW;
        }

        if (_isGoogleUrl(n1diceUri)) {
          await _addRandomToUserAgentForGoogle();
        } else {
          await _restoreUserAgentAfterGoogleIfNeeded();
          await _applyNormalUserAgentIfNeeded();
        }

        if (n1diceKit.n1diceLooksLikeBareMail(n1diceUri)) {
          final Uri n1diceMailto =
          n1diceKit.n1diceToMailto(n1diceUri);
          await n1diceLinker.n1diceOpen(
            n1diceKit.n1diceGmailize(n1diceMailto),
          );
          return NavigationActionPolicy.CANCEL;
        }

        final String n1diceScheme =
        n1diceUri.scheme.toLowerCase();

        if (n1diceScheme == 'mailto') {
          await n1diceLinker.n1diceOpen(
            n1diceKit.n1diceGmailize(n1diceUri),
          );
          return NavigationActionPolicy.CANCEL;
        }

        if (n1diceIsBankScheme(n1diceUri) ||
            ((n1diceScheme == 'http' || n1diceScheme == 'https') &&
                n1diceIsBankDomain(n1diceUri))) {
          await n1diceOpenBank(n1diceUri);
          return NavigationActionPolicy.CANCEL;
        }

        if (n1diceScheme == 'tel') {
          await launchUrl(
            n1diceUri,
            mode: LaunchMode.externalApplication,
          );
          return NavigationActionPolicy.CANCEL;
        }

        final String n1diceHost = n1diceUri.host.toLowerCase();
        final bool n1diceIsSocial =
            n1diceHost.endsWith('facebook.com') ||
                n1diceHost.endsWith('instagram.com') ||
                n1diceHost.endsWith('twitter.com') ||
                n1diceHost.endsWith('x.com');

        if (n1diceIsSocial) {
          await n1diceLinker.n1diceOpen(n1diceUri);
          return NavigationActionPolicy.CANCEL;
        }

        if (n1diceIsExternalDestination(n1diceUri)) {
          final Uri n1diceMapped =
          n1diceMapExternalToHttp(n1diceUri);
          await n1diceLinker.n1diceOpen(n1diceMapped);
          return NavigationActionPolicy.CANCEL;
        }

        if (n1diceScheme != 'http' && n1diceScheme != 'https') {
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (
          InAppWebViewController n1diceController,
          CreateWindowAction n1diceReq,
          ) async {
        final Uri? n1diceUrl = n1diceReq.request.url;
        if (n1diceUrl == null) return false;

        if (_isGoogleUrl(n1diceUrl)) {
          await _addRandomToUserAgentForGoogle();
        } else {
          await _restoreUserAgentAfterGoogleIfNeeded();
          await _applyNormalUserAgentIfNeeded();
        }

        if (n1diceKit.n1diceLooksLikeBareMail(n1diceUrl)) {
          final Uri n1diceMail =
          n1diceKit.n1diceToMailto(n1diceUrl);
          await n1diceLinker.n1diceOpen(
            n1diceKit.n1diceGmailize(n1diceMail),
          );
          return false;
        }

        final String n1diceScheme =
        n1diceUrl.scheme.toLowerCase();

        if (n1diceScheme == 'mailto') {
          await n1diceLinker.n1diceOpen(
            n1diceKit.n1diceGmailize(n1diceUrl),
          );
          return false;
        }

        if (n1diceIsBankScheme(n1diceUrl) ||
            ((n1diceScheme == 'http' || n1diceScheme == 'https') &&
                n1diceIsBankDomain(n1diceUrl))) {
          await n1diceOpenBank(n1diceUrl);
          return false;
        }

        if (n1diceScheme == 'tel') {
          await launchUrl(
            n1diceUrl,
            mode: LaunchMode.externalApplication,
          );
          return false;
        }

        final String n1diceHost = n1diceUrl.host.toLowerCase();
        final bool n1diceIsSocial =
            n1diceHost.endsWith('facebook.com') ||
                n1diceHost.endsWith('instagram.com') ||
                n1diceHost.endsWith('twitter.com') ||
                n1diceHost.endsWith('x.com');

        if (n1diceIsSocial) {
          await n1diceLinker.n1diceOpen(n1diceUrl);
          return false;
        }

        if (n1diceIsExternalDestination(n1diceUrl)) {
          final Uri n1diceMapped =
          n1diceMapExternalToHttp(n1diceUrl);
          await n1diceLinker.n1diceOpen(n1diceMapped);
          return false;
        }

        // ---- popup‑логика: всё, что осталось http/https — открываем во всплывающем WebView ----
        if (n1diceScheme == 'http' || n1diceScheme == 'https') {
          _openPopup(n1diceReq, urlString: n1diceUrl.toString());
          return true; // говорим WebView, что создаём окно сами
        }

        return false;
      },
    );

    final Widget body = Stack(
      children: <Widget>[
        webView,
        if (n1diceOverlayBusy)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black87,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        _buildPopupOverlay(),
      ],
    );

    final Widget wrapped =
    _safeAreaEnabled ? SafeArea(child: body) : body;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Обычно на тёмном фоне нужен светлый текст статус-бара
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // или твой цвет
        statusBarIconBrightness:
        Brightness.light, // ANDROID: светлые иконки
        statusBarBrightness:
        Brightness.dark, // iOS: светлые иконки
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        body: wrapped,
      ),
    );
  }

  // ========================================================================
  // Внешние “столы” (протоколы/мессенджеры/соцсети)
  // ========================================================================

  bool n1diceIsExternalDestination(Uri n1diceUri) {
    final String n1diceScheme =
    n1diceUri.scheme.toLowerCase();
    if (n1diceExternalSchemes.contains(n1diceScheme)) {
      return true;
    }

    if (n1diceScheme == 'http' || n1diceScheme == 'https') {
      final String n1diceHost = n1diceUri.host.toLowerCase();
      if (n1diceExternalHosts.contains(n1diceHost)) {
        return true;
      }
      if (n1diceHost.endsWith('t.me')) return true;
      if (n1diceHost.endsWith('wa.me')) return true;
      if (n1diceHost.endsWith('m.me')) return true;
      if (n1diceHost.endsWith('signal.me')) return true;
      if (n1diceHost.endsWith('facebook.com')) return true;
      if (n1diceHost.endsWith('instagram.com')) return true;
      if (n1diceHost.endsWith('twitter.com')) return true;
      if (n1diceHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri n1diceMapExternalToHttp(Uri n1diceUri) {
    final String n1diceScheme =
    n1diceUri.scheme.toLowerCase();

    if (n1diceScheme == 'tg' || n1diceScheme == 'telegram') {
      final Map<String, String> n1diceQp =
          n1diceUri.queryParameters;
      final String? n1diceDomain = n1diceQp['domain'];
      if (n1diceDomain != null && n1diceDomain.isNotEmpty) {
        return Uri.https('t.me', '/$n1diceDomain', <String, String>{
          if (n1diceQp['start'] != null) 'start': n1diceQp['start']!,
        });
      }
      final String n1dicePath =
      n1diceUri.path.isNotEmpty ? n1diceUri.path : '';
      return Uri.https(
        't.me',
        '/$n1dicePath',
        n1diceUri.queryParameters.isEmpty
            ? null
            : n1diceUri.queryParameters,
      );
    }

    if (n1diceScheme == 'whatsapp') {
      final Map<String, String> n1diceQp =
          n1diceUri.queryParameters;
      final String? n1dicePhone = n1diceQp['phone'];
      final String? n1diceText = n1diceQp['text'];
      if (n1dicePhone != null && n1dicePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${n1diceKit.n1diceDigitsOnly(n1dicePhone)}',
          <String, String>{
            if (n1diceText != null && n1diceText.isNotEmpty)
              'text': n1diceText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (n1diceText != null && n1diceText.isNotEmpty)
            'text': n1diceText,
        },
      );
    }

    if (n1diceScheme == 'bnl') {
      final String n1diceNewPath =
      n1diceUri.path.isNotEmpty ? n1diceUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$n1diceNewPath',
        n1diceUri.queryParameters.isEmpty
            ? null
            : n1diceUri.queryParameters,
      );
    }

    return n1diceUri;
  }

  Future<void> n1diceSendLoadedOnce() async {
    if (n1diceLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int n1diceNow =
        DateTime.now().millisecondsSinceEpoch;

    await n1dicePostStat(
      n1diceEvent: 'Loaded',
      n1diceTimeStart: n1diceStartLoadTimestamp,
      n1diceTimeFinish: n1diceNow,
      n1diceUrl: n1diceCurrentUrl,
      n1diceAppSid: n1diceSpyInstance.n1diceAppsFlyerUid,
      n1diceFirstPageTs: n1diceFirstPageTimestamp,
    );

    n1diceLoadedOnceSent = true;
  }
}