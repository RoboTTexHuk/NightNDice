import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
    MethodChannel,
    SystemChrome,
    SystemUiOverlayStyle,
    MethodCall,
    VoidCallback;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:nightndicenightnight/pushhh.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'gameVIEW.dart';

// ============================================================================
// Константы
// ============================================================================

const String n1diceLoadedOnceKey = 'loaded_once';
const String n1diceStatEndpoint = 'https://appres.nndice.club/stat';
const String n1diceCachedFcmKey = 'cached_fcm';
const String n1diceCachedDeepKey = 'cached_deep_push_uri';

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
// Лёгкие сервисы
// ============================================================================

class n1diceLoggerService {
  static final n1diceLoggerService sharedInstance =
  n1diceLoggerService._internalConstructor();

  n1diceLoggerService._internalConstructor();

  factory n1diceLoggerService() => sharedInstance;

  final Connectivity n1diceConnectivity = Connectivity();

  void n1diceLogInfo(Object message) => print('[I] $message');
  void n1diceLogWarn(Object message) => print('[W] $message');
  void n1diceLogError(Object message) => print('[E] $message');
}

class n1diceNetworkService {
  final n1diceLoggerService n1diceLogger = n1diceLoggerService();

  Future<void> n1dicePostJson(
      String url,
      Map<String, dynamic> data,
      ) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (error) {
      n1diceLogger.n1diceLogError('postJson error: $error');
    }
  }
}

// ============================================================================
// Утилита: одновременное сохранение JSON в localStorage и SharedPreferences
// ============================================================================

Future<void> n1diceSaveJsonToLocalStorageAndPrefs({
  required InAppWebViewController? controller,
  required String key,
  required Map<String, dynamic> data,
}) async {
  final String jsonString = jsonEncode(data);

  // 1) localStorage в WebView
  if (controller != null) {
    try {
      await controller.evaluateJavascript(
        source: "localStorage.setItem('$key', JSON.stringify($jsonString));",
      );
    } catch (e, st) {
      n1diceLoggerService().n1diceLogError(
          'n1diceSaveJsonToLocalStorageAndPrefs localStorage error: $e\n$st');
    }
  }

  // 2) SharedPreferences на native-стороне
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonString);
  } catch (e, st) {
    n1diceLoggerService().n1diceLogError(
        'n1diceSaveJsonToLocalStorageAndPrefs prefs error: $e\n$st');
  }
}

// ============================================================================
// Профиль устройства
// ============================================================================

class n1diceDeviceProfile {
  String? n1diceDeviceId;
  String? n1diceSessionId = '';
  String? n1dicePlatformName;
  String? n1diceOsVersion;
  String? n1diceAppVersion;
  String? n1diceLanguageCode;
  String? n1diceTimezoneName;
  bool n1dicePushEnabled = false;

  bool n1diceSafeAreaEnabled = false;
  String? n1diceSafeAreaColor;
  bool safecasher = true;
  String? n1diceBaseUserAgent;

  Map<String, dynamic>? n1diceLastPushData;

  Map<String, dynamic>? n1diceSavels;

  Future<void> n1diceInitialize() async {
    final DeviceInfoPlugin n1diceDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo n1diceAndroidInfo =
      await n1diceDeviceInfoPlugin.androidInfo;
      n1diceDeviceId = n1diceAndroidInfo.id;
      n1dicePlatformName = 'android';
      n1diceOsVersion = n1diceAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo n1diceIosInfo =
      await n1diceDeviceInfoPlugin.iosInfo;
      n1diceDeviceId = n1diceIosInfo.identifierForVendor;
      n1dicePlatformName = 'ios';
      n1diceOsVersion = n1diceIosInfo.systemVersion;
    }

    final PackageInfo n1dicePackageInfo = await PackageInfo.fromPlatform();
    n1diceAppVersion = n1dicePackageInfo.version;
    n1diceLanguageCode = Platform.localeName.split('_').first;
    n1diceTimezoneName = tz_zone.local.name;
    n1diceSessionId = '${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> n1diceToMap({String? fcmToken}) => <String, dynamic>{
    'fcm_token': fcmToken ?? 'missing_token',
    'device_id': n1diceDeviceId ?? 'missing_id',
    'app_name': 'nndice',
    'instance_id': n1diceSessionId ?? 'missing_session',
    'platform': n1dicePlatformName ?? 'missing_system',
    'os_version': n1diceOsVersion ?? 'missing_build',
    'app_version': "1.4.1" ?? 'missing_app',
    'language': n1diceLanguageCode ?? 'en',
    'timezone': n1diceTimezoneName ?? 'UTC',
    'push_enabled': n1dicePushEnabled,
    'safe_area_native': n1diceSafeAreaEnabled,
    'useragent': n1diceBaseUserAgent ?? 'unknown_useragent',
    'savels': n1diceSavels ?? <String, dynamic>{},
    'fpscashier': safecasher,
  };
}

// ============================================================================
// AppsFlyer Spy
// ============================================================================

class n1diceAnalyticsSpyService {
  appsflyer_core.AppsFlyerOptions? n1diceAppsFlyerOptions;
  appsflyer_core.AppsflyerSdk? n1diceAppsFlyerSdk;

  String n1diceAppsFlyerUid = '';
  String n1diceAppsFlyerData = '';

  Map<String, dynamic>? n1diceAppsFlyerOneLinkData;

  void n1diceStartTracking({VoidCallback? onUpdate}) {
    final appsflyer_core.AppsFlyerOptions n1diceConfig =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6768618190',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    n1diceAppsFlyerOptions = n1diceConfig;
    n1diceAppsFlyerSdk = appsflyer_core.AppsflyerSdk(n1diceConfig);

    n1diceAppsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    n1diceAppsFlyerSdk?.startSDK(
      onSuccess: () =>
          n1diceLoggerService().n1diceLogInfo('RetroCarAnalyticsSpy started'),
      onError: (int code, String msg) => n1diceLoggerService()
          .n1diceLogError('RetroCarAnalyticsSpy error $code: $msg'),
    );

    n1diceAppsFlyerSdk?.onInstallConversionData((dynamic value) {
      n1diceAppsFlyerData = value.toString();
      onUpdate?.call();
    });

    n1diceAppsFlyerSdk?.getAppsFlyerUID().then((dynamic value) {
      n1diceAppsFlyerUid = value.toString();
      onUpdate?.call();
    });
  }

  void n1diceSetOneLinkData(Map<String, dynamic> data) {
    n1diceAppsFlyerOneLinkData = data;
    n1diceLoggerService()
        .n1diceLogInfo('n1diceAnalyticsSpyService: OneLink data updated: $data');
  }
}

// ============================================================================
// FCM фон
// ============================================================================

@pragma('vm:entry-point')
Future<void> n1diceFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  n1diceLoggerService().n1diceLogInfo('bg-fcm: ${message.messageId}');
  n1diceLoggerService().n1diceLogInfo('bg-data: ${message.data}');

  final dynamic n1diceLink = message.data['uri'];
  if (n1diceLink != null) {
    try {
      final SharedPreferences n1dicePrefs =
      await SharedPreferences.getInstance();
      await n1dicePrefs.setString(
        n1diceCachedDeepKey,
        n1diceLink.toString(),
      );
    } catch (e) {
      n1diceLoggerService()
          .n1diceLogError('bg-fcm save deep failed: $e');
    }
  }
}

// ============================================================================
// FCM Bridge — токен
// ============================================================================

class n1diceFcmBridge {
  final n1diceLoggerService n1diceLogger = n1diceLoggerService();

  static const MethodChannel _tokenChannel =
  MethodChannel('com.example.fcm/token');

  String? n1diceToken;
  final List<void Function(String)> n1diceTokenWaiters =
  <void Function(String)>[];

  String? get n1diceFcmToken => n1diceToken;

  Timer? _requestTimer;
  int _requestAttempts = 0;
  final int _maxAttempts = 10;

  n1diceFcmBridge() {
    _tokenChannel.setMethodCallHandler((MethodCall n1diceCall) async {
      if (n1diceCall.method == 'setToken') {
        final String n1diceTokenString = n1diceCall.arguments as String;
        n1diceLogger.n1diceLogInfo(
            'n1diceFcmBridge: got token from native channel = $n1diceTokenString');
        if (n1diceTokenString.isNotEmpty) {
          n1diceSetToken(n1diceTokenString);
        }
      }
    });

    n1diceRestoreToken();
    _requestNativeToken();
    _startRequestTimer();
  }

  Future<void> _requestNativeToken() async {
    try {
      n1diceLogger.n1diceLogInfo('n1diceFcmBridge: request native getToken()');
      final String? token =
      await _tokenChannel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        n1diceLogger.n1diceLogInfo(
            'n1diceFcmBridge: native getToken() returns $token');
        n1diceSetToken(token);
      } else {
        n1diceLogger.n1diceLogWarn(
            'n1diceFcmBridge: native getToken() returned empty');
      }
    } catch (e) {
      n1diceLogger
          .n1diceLogWarn('n1diceFcmBridge: getToken invoke error: $e');
    }
  }

  void _startRequestTimer() {
    _requestTimer?.cancel();
    _requestAttempts = 0;

    _requestTimer =
        Timer.periodic(const Duration(seconds: 5), (Timer t) async {
          if ((n1diceToken ?? '').isNotEmpty) {
            n1diceLogger.n1diceLogInfo(
                'n1diceFcmBridge: token already set, stop request timer');
            t.cancel();
            return;
          }

          if (_requestAttempts >= _maxAttempts) {
            n1diceLogger.n1diceLogWarn(
                'n1diceFcmBridge: max getToken attempts reached, stop timer');
            t.cancel();
            return;
          }

          _requestAttempts++;
          n1diceLogger.n1diceLogInfo(
              'n1diceFcmBridge: retry getToken() attempt #$_requestAttempts');
          await _requestNativeToken();
        });
  }

  Future<void> n1diceRestoreToken() async {
    try {
      final SharedPreferences n1dicePrefs =
      await SharedPreferences.getInstance();
      final String? n1diceCachedToken =
      n1dicePrefs.getString(n1diceCachedFcmKey);
      if (n1diceCachedToken != null && n1diceCachedToken.isNotEmpty) {
        n1diceLogger.n1diceLogInfo(
            'n1diceFcmBridge: restored cached token = $n1diceCachedToken');
        n1diceSetToken(n1diceCachedToken, notify: false);
      }
    } catch (e) {
      n1diceLogger.n1diceLogError('n1diceRestoreToken error: $e');
    }
  }

  Future<void> n1dicePersistToken(String newToken) async {
    try {
      final SharedPreferences n1dicePrefs =
      await SharedPreferences.getInstance();
      await n1dicePrefs.setString(n1diceCachedFcmKey, newToken);
    } catch (e) {
      n1diceLogger.n1diceLogError('n1dicePersistToken error: $e');
    }
  }

  void n1diceSetToken(
      String newToken, {
        bool notify = true,
      }) {
    n1diceToken = newToken;
    n1dicePersistToken(newToken);

    if (notify) {
      for (final void Function(String) n1diceCallback
      in List<void Function(String)>.from(n1diceTokenWaiters)) {
        try {
          n1diceCallback(newToken);
        } catch (error) {
          n1diceLogger.n1diceLogWarn('fcm waiter error: $error');
        }
      }
      n1diceTokenWaiters.clear();
    }
  }

  Future<void> n1diceWaitForToken(
      Function(String token) n1diceOnToken,
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

      n1diceTokenWaiters.add(n1diceOnToken);
    } catch (error) {
      n1diceLogger.n1diceLogError('n1diceWaitForToken error: $error');
    }
  }

  void dispose() {
    _requestTimer?.cancel();
  }
}

// ============================================================================
// Splash / Hall — без visual loader’а
// ============================================================================

class n1diceHall extends StatefulWidget {
  const n1diceHall({Key? key}) : super(key: key);

  @override
  State<n1diceHall> createState() => _n1diceHallState();
}

class _n1diceHallState extends State<n1diceHall> {
  final n1diceFcmBridge n1diceFcmBridgeInstance = n1diceFcmBridge();
  bool n1diceNavigatedOnce = false;
  Timer? n1diceFallbackTimer;

  // Прогресс‑бар (логика оставлена, но визуально больше не отображается)
  double n1diceProgress = 0.0;
  Timer? n1diceProgressTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    // Ждем FCM‑токен
    n1diceFcmBridgeInstance.n1diceWaitForToken((String n1diceToken) {
      n1diceGoToHarbor(n1diceToken);
    });

    // Фолбэк, если токен не пришёл
    n1diceFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => n1diceGoToHarbor(''),
    );

    // Анимация прогресса (для тайминга, но не показываем на экране)
    n1diceProgressTimer =
        Timer.periodic(const Duration(milliseconds: 80), (Timer timer) {
          if (!mounted) return;
          setState(() {
            if (n1diceProgress < 0.98) {
              n1diceProgress += 0.02;
            } else {
              n1diceProgress = 0.98;
            }
          });
        });
  }

  void n1diceGoToHarbor(String n1diceSignal) {
    if (n1diceNavigatedOnce) return;
    n1diceNavigatedOnce = true;

    n1diceFallbackTimer?.cancel();
    n1diceProgressTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) =>
            n1diceHarbor(n1diceSignal: n1diceSignal),
      ),
    );
  }

  @override
  void dispose() {
    n1diceFallbackTimer?.cancel();
    n1diceProgressTimer?.cancel();
    n1diceFcmBridgeInstance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Экран‑заглушка без loader’а: просто фон
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/nightdice_bg.png',
            fit: BoxFit.cover,
          ),
          Container(
            color: Colors.black.withOpacity(0.25),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class n1diceBosunViewModel {
  final n1diceDeviceProfile n1diceDeviceProfileInstance;
  final n1diceAnalyticsSpyService n1diceAnalyticsSpyInstance;

  n1diceBosunViewModel({
    required this.n1diceDeviceProfileInstance,
    required this.n1diceAnalyticsSpyInstance,
  });

  Map<String, dynamic> n1diceDeviceMap(String? fcmToken) =>
      n1diceDeviceProfileInstance.n1diceToMap(fcmToken: fcmToken);

  Map<String, dynamic> n1diceAppsFlyerPayload(
      String? token, {
        String? deepLink,
      }) {
    final Map<String, dynamic> onelinkData =
        n1diceAnalyticsSpyInstance.n1diceAppsFlyerOneLinkData ??
            <String, dynamic>{};

    return <String, dynamic>{
      'content': <String, dynamic>{
        'af_data': n1diceAnalyticsSpyInstance.n1diceAppsFlyerData,
        'af_id': n1diceAnalyticsSpyInstance.n1diceAppsFlyerUid,
        'fb_app_name': 'nndice',
        'app_name': 'nndice',
        'onelink': onelinkData,
        'bundle_identifier': 'com.dicenitg.nightdice.nightndicenightnight',
        'app_version': '1.4.1',
        'apple_id': '6768618190',
        'fcm_token': token ?? 'no_token',
        'device_id': n1diceDeviceProfileInstance.n1diceDeviceId ?? 'no_device',
        'instance_id':
        n1diceDeviceProfileInstance.n1diceSessionId ?? 'no_instance',
        'platform':
        n1diceDeviceProfileInstance.n1dicePlatformName ?? 'no_type',
        'os_version':
        n1diceDeviceProfileInstance.n1diceOsVersion ?? 'no_os',
        'language':
        n1diceDeviceProfileInstance.n1diceLanguageCode ?? 'en',
        'timezone':
        n1diceDeviceProfileInstance.n1diceTimezoneName ?? 'UTC',
        'push_enabled': n1diceDeviceProfileInstance.n1dicePushEnabled,
        'useruid': n1diceAnalyticsSpyInstance.n1diceAppsFlyerUid,
        'safearea': n1diceDeviceProfileInstance.n1diceSafeAreaEnabled,
        'safearea_color':
        n1diceDeviceProfileInstance.n1diceSafeAreaColor ?? '',
        'useragent': n1diceDeviceProfileInstance.n1diceBaseUserAgent ??
            'unknown_useragent',
        'push': n1diceDeviceProfileInstance.n1diceLastPushData ??
            <String, dynamic>{},
        'deep': deepLink,
      },
    };
  }
}

class n1diceCourierService {
  final n1diceBosunViewModel n1diceBosun;
  final InAppWebViewController? Function() n1diceGetWebViewController;

  n1diceCourierService({
    required this.n1diceBosun,
    required this.n1diceGetWebViewController,
  });

  Future<InAppWebViewController?> _waitForController({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    final n1diceLoggerService logger = n1diceLoggerService();
    final DateTime start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      final InAppWebViewController? c = n1diceGetWebViewController();
      if (c != null) {
        return c;
      }
      await Future<void>.delayed(interval);
    }

    logger.n1diceLogWarn(
        '_waitForController: timeout, controller is still null');
    return null;
  }

  Future<void> n1dicePutDeviceToLocalStorage(String? token) async {
    final InAppWebViewController? n1diceController =
    await _waitForController();
    if (n1diceController == null) return;

    final Map<String, dynamic> n1diceMap =
    n1diceBosun.n1diceDeviceMap(token);
    n1diceLoggerService()
        .n1diceLogInfo("applocal (${jsonEncode(n1diceMap)});");

    await n1diceSaveJsonToLocalStorageAndPrefs(
      controller: n1diceController,
      key: 'app_data',
      data: n1diceMap,
    );
  }

  Future<void> n1diceSendRawToPage(
      String? token, {
        String? deepLink,
      }) async {
    final InAppWebViewController? n1diceController =
    await _waitForController();
    if (n1diceController == null) return;

    final Map<String, dynamic> n1dicePayload =
    n1diceBosun.n1diceAppsFlyerPayload(token, deepLink: deepLink);

    final String n1diceJsonString = jsonEncode(n1dicePayload);

    n1diceLoggerService()
        .n1diceLogInfo('SendRawData: $n1diceJsonString');

    final String jsSafeJson = jsonEncode(n1diceJsonString);
    final String jsCode = 'sendRawData($jsSafeJson);';

    try {
      await n1diceController.evaluateJavascript(source: jsCode);
    } catch (e, st) {
      n1diceLoggerService().n1diceLogError(
          'n1diceSendRawToPage evaluateJavascript error: $e\n$st');
    }
  }
}

// ============================================================================
// Статистика
// ============================================================================

Future<String> n1diceResolveFinalUrl(
    String startUrl, {
      int maxHops = 10,
    }) async {
  final HttpClient n1diceHttpClient = HttpClient();

  try {
    Uri n1diceCurrentUri = Uri.parse(startUrl);

    for (int n1diceIndex = 0; n1diceIndex < maxHops; n1diceIndex++) {
      final HttpClientRequest n1diceRequest =
      await n1diceHttpClient.getUrl(n1diceCurrentUri);
      n1diceRequest.followRedirects = false;
      final HttpClientResponse n1diceResponse =
      await n1diceRequest.close();

      if (n1diceResponse.isRedirect) {
        final String? n1diceLocationHeader =
        n1diceResponse.headers.value(HttpHeaders.locationHeader);
        if (n1diceLocationHeader == null ||
            n1diceLocationHeader.isEmpty) {
          break;
        }

        final Uri n1diceNextUri =
        Uri.parse(n1diceLocationHeader);
        n1diceCurrentUri = n1diceNextUri.hasScheme
            ? n1diceNextUri
            : n1diceCurrentUri.resolveUri(n1diceNextUri);
        continue;
      }

      return n1diceCurrentUri.toString();
    }

    return n1diceCurrentUri.toString();
  } catch (error) {
    print('goldenLuxuryResolveFinalUrl error: $error');
    return startUrl;
  } finally {
    n1diceHttpClient.close(force: true);
  }
}

Future<void> n1dicePostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final String n1diceResolvedUrl = await n1diceResolveFinalUrl(url);

    final Map<String, dynamic> n1dicePayload = <String, dynamic>{
      'event': event,
      'timestart': timeStart,
      'timefinsh': timeFinish,
      'url': n1diceResolvedUrl,
      'appleID': '6758657360',
      'open_count': '$appSid/$timeStart',
      if (firstPageLoadTs != null) 'firstPageLoadTs': firstPageLoadTs,
    };

    print('goldenLuxuryStat $n1dicePayload');

    final http.Response n1diceResponse = await http.post(
      Uri.parse('$n1diceStatEndpoint/$appSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(n1dicePayload),
    );

    print(
        'goldenLuxuryStat resp=${n1diceResponse.statusCode} body=${n1diceResponse.body}');
  } catch (error) {
    print('goldenLuxuryPostStat error: $error');
  }
}

// ============================================================================
// Банковские утилиты
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
    print('n1diceOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class n1diceHarbor extends StatefulWidget {
  final String? n1diceSignal;

  const n1diceHarbor({super.key, required this.n1diceSignal});

  @override
  State<n1diceHarbor> createState() => _n1diceHarborState();
}

class _n1diceHarborState extends State<n1diceHarbor>
    with WidgetsBindingObserver {
  InAppWebViewController? n1diceWebViewController;

  InAppWebViewController? n1dicePopupWebViewController;
  bool _isPopupVisible = false;
  String? _popupUrl;
  CreateWindowAction? _popupCreateAction;

  bool _popupCanGoBack = false;
  String? _popupCurrentUrl;

  bool _isOpeningExternalNewTab = false;
  final Set<String> _handledNewTabUrls = <String>{};

  Timer? _parentInstallTimer;
  Timer? _popupInstallTimer;

  final String n1diceHomeUrl =
      'https://appres.nndice.club/';

  int n1diceWebViewKeyCounter = 0;
  DateTime? n1diceSleepAt;
  bool n1diceVeilVisible = false;
  double n1diceWarmProgress = 0.0;
  late Timer n1diceWarmTimer;
  final int n1diceWarmSeconds = 6;
  bool n1diceCoverVisible = true;

  bool n1diceLoadedOnceSent = false;
  int? n1diceFirstPageTimestamp;

  n1diceCourierService? n1diceCourier;
  n1diceBosunViewModel? n1diceBosunInstance;

  String n1diceCurrentUrl = '';
  int n1diceStartLoadTimestamp = 0;

  final n1diceDeviceProfile n1diceDeviceProfileInstance =
  n1diceDeviceProfile();
  final n1diceAnalyticsSpyService n1diceAnalyticsSpyInstance =
  n1diceAnalyticsSpyService();

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

  final Set<String> n1diceExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
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

  String? n1diceDeepLinkFromPush;

  String? _baseUserAgent;
  String _currentUserAgent = "";
  String? _currentUrl;

  String? _serverUserAgent;

  bool _safeAreaEnabled = false;
  Color _safeAreaBackgroundColor = const Color(0xFF000000);

  bool _startupSendRawDone = false;

  String? _pendingLoadedJs;

  bool _loadedJsExecutedOnce = false;

  bool _isInGoogleAuth = false;

  List<String> _buttonWhitelist = <String>[];
  bool _showBackButton = false;

  bool _backButtonHiddenAfterTap = false;

  static const MethodChannel _appsFlyerDeepLinkChannel =
  MethodChannel('appsflyer_deeplink_channel');

  // Изначальный лоадер на 8 секунд при открытии Harbor
  bool _showInitialLoader = true;
  Timer? _initialLoaderTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    n1diceFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;
    _currentUrl = n1diceHomeUrl;

    // Стартуем анимированный прогресс для лоадера
    n1diceStartWarmProgress();

    // Лоадер будет показываться ровно 8 секунд
    _initialLoaderTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() {
        _showInitialLoader = false;
      });
    });

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          n1diceCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        n1diceVeilVisible = true;
      });
    });

    _bindPushChannelFromAppDelegate();
    _bindAppsFlyerDeepLinkChannel();
    n1diceBootHarbor();
  }

  bool _isAboutBlankUrl(String? value) {
    final String u = (value ?? '').trim().toLowerCase();
    return u.isEmpty || u == 'about:blank' || u.startsWith('about:blank');
  }

  bool _isAboutBlankUri(Uri? uri) => _isAboutBlankUrl(uri?.toString());

  void _bindAppsFlyerDeepLinkChannel() {
    _appsFlyerDeepLinkChannel.setMethodCallHandler(
          (MethodCall call) async {
        if (call.method == 'onDeepLink') {
          try {
            final dynamic args = call.arguments;

            Map<String, dynamic> payload;

            print(" Data Deepl link ${args.toString()}");
            if (args is Map) {
              payload = Map<String, dynamic>.from(args as Map);
            } else if (args is String) {
              payload = jsonDecode(args) as Map<String, dynamic>;
            } else {
              payload = <String, dynamic>{'raw': args.toString()};
            }

            n1diceLoggerService().n1diceLogInfo(
              'AppsFlyer onDeepLink from iOS: $payload',
            );

            final dynamic raw = payload['raw'];
            if (raw is Map) {
              final Map<String, dynamic> normalized =
              Map<String, dynamic>.from(raw as Map);

              print("One Link Data $normalized");
              n1diceAnalyticsSpyInstance.n1diceSetOneLinkData(normalized);
            } else {
              n1diceAnalyticsSpyInstance.n1diceSetOneLinkData(payload);
            }
          } catch (e, st) {
            n1diceLoggerService()
                .n1diceLogError('Error in onDeepLink handler: $e\n$st');
          }
        }
      },
    );
  }

  void _bindPushChannelFromAppDelegate() {
    const MethodChannel pushChannel = MethodChannel('com.example.fcm/push');

    pushChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'setPushData') {
        try {
          Map<String, dynamic> pushData;
          if (call.arguments is Map) {
            pushData = Map<String, dynamic>.from(call.arguments);
            print("Get Push Data $pushData");
          } else if (call.arguments is String) {
            pushData =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
          } else {
            pushData =
            <String, dynamic>{'raw': call.arguments.toString()};
          }

          n1diceLoggerService()
              .n1diceLogInfo('Got push data from AppDelegate: $pushData');

          n1diceDeviceProfileInstance.n1diceLastPushData = pushData;

          final dynamic uriRaw = pushData['uri'] ?? pushData['deep_link'];
          if (uriRaw != null && uriRaw.toString().isNotEmpty) {
            final String u = uriRaw.toString();
            n1diceDeepLinkFromPush = u;
            await n1diceSaveCachedDeep(u);
          }
        } catch (e, st) {
          n1diceLoggerService()
              .n1diceLogError('setPushData handler error: $e\n$st');
        }
      }
    });
  }

  bool _isGoogleUrl(Uri uri) {
    final String full = uri.toString().toLowerCase();
    return full.contains('google.com') ||
        full.contains('accounts.google.') ||
        full.contains('googleusercontent.com') ||
        full.contains('gstatic.com');
  }

  // --- Логика Google: User-Agent = "random" и обратно ---

  Future<void> _addRandomToUserAgentForGoogle() async {
    if (n1diceWebViewController == null) return;

    const String targetUa = 'random';

    if (_currentUserAgent == targetUa && _isInGoogleAuth) {
      n1diceLoggerService().n1diceLogInfo(
        'Already in Google flow with random UA, skip reapply',
      );
      return;
    }

    n1diceLoggerService().n1diceLogInfo(
      'Switching User-Agent to RANDOM for Google URL: $targetUa',
    );

    try {
      await n1diceWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      _isInGoogleAuth = true;
      print('[UA] GOOGLE RANDOM USER AGENT: $_currentUserAgent');
    } catch (e) {
      n1diceLoggerService().n1diceLogError(
        'Error while setting RANDOM User-Agent for Google URL: $e',
      );
    }
  }

  Future<void> _restoreUserAgentAfterGoogle() async {
    if (!_isInGoogleAuth) {
      return;
    }
    n1diceLoggerService()
        .n1diceLogInfo('Leaving Google flow, restoring normal User-Agent');
    _isInGoogleAuth = false;
    await _applyNormalUserAgentIfNeeded();
  }

  Future<void> _updateUserAgentForUrl(Uri uri) async {
    if (_isGoogleUrl(uri)) {
      await _addRandomToUserAgentForGoogle();
    } else {
      await _restoreUserAgentAfterGoogle();
    }
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

  Future<void> _applyUserAgent({String? fullua, String? uatail}) async {
    if (n1diceWebViewController == null) return;

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      try {
        final ua = await n1diceWebViewController!.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _baseUserAgent = ua.trim();
          _currentUserAgent = _baseUserAgent!;
          n1diceDeviceProfileInstance.n1diceBaseUserAgent =
              _baseUserAgent;
          n1diceLoggerService().n1diceLogInfo(
              'Base User-Agent detected: $_baseUserAgent');
        }
      } catch (e) {
        n1diceLoggerService()
            .n1diceLogWarn('Failed to get base userAgent from JS: $e');
      }
    }

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      n1diceLoggerService().n1diceLogWarn(
          'Base User-Agent is still null/empty, skip UA update');
      return;
    }

    n1diceLoggerService().n1diceLogInfo(
        'Server UA payload: fullua="$fullua", uatail="$uatail", base="$_baseUserAgent"');

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_baseUserAgent!}/${uatail.trim()}";
    } else {
      newUa = "${_baseUserAgent!}";
    }

    _serverUserAgent = newUa;
    n1diceLoggerService()
        .n1diceLogInfo('Server UA calculated and stored: $_serverUserAgent');
  }

  Future<void> _applyNormalUserAgentIfNeeded() async {
    if (n1diceWebViewController == null) return;

    final String targetUa =
        _serverUserAgent ?? _baseUserAgent ?? 'random';

    if (targetUa == _currentUserAgent) {
      n1diceLoggerService().n1diceLogInfo(
          'Normal UA unchanged, keeping: $_currentUserAgent');
      return;
    }

    n1diceLoggerService()
        .n1diceLogInfo('Applying NORMAL WebView User-Agent: $targetUa');

    try {
      await n1diceWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      print('[UA] NORMAL WEBVIEW USER AGENT: $_currentUserAgent');
    } catch (e) {
      n1diceLoggerService().n1diceLogError(
          'Error while setting normal User-Agent "$targetUa": $e');
    }
  }

  Future<void> printJsUserAgent() async {
    if (n1diceWebViewController == null) return;

    try {
      final ua = await n1diceWebViewController!.evaluateJavascript(
        source: "navigator.userAgent",
      );

      if (ua is String) {
        print('[JS UA] navigator.userAgent = $ua');
      } else {
        print('[JS UA] navigator.userAgent (non-string) = $ua');
      }
    } catch (e, st) {
      print('Error reading navigator.userAgent: $e\n$st');
    }
  }

  Future<void> debugPrintCurrentUserAgent() async {
    n1diceLoggerService()
        .n1diceLogInfo('[STATE UA] _currentUserAgent = $_currentUserAgent');
    await printJsUserAgent();
  }

  Future<void> n1diceLoadLoadedFlag() async {
    final SharedPreferences n1dicePrefs =
    await SharedPreferences.getInstance();
    n1diceLoadedOnceSent =
        n1dicePrefs.getBool(n1diceLoadedOnceKey) ?? false;
  }

  Future<void> n1diceSaveLoadedFlag() async {
    final SharedPreferences n1dicePrefs =
    await SharedPreferences.getInstance();
    await n1dicePrefs.setBool(n1diceLoadedOnceKey, true);
    n1diceLoadedOnceSent = true;
  }

  Future<void> n1diceLoadCachedDeep() async {
    try {
      final SharedPreferences n1dicePrefs =
      await SharedPreferences.getInstance();
      final String? n1diceCached =
      n1dicePrefs.getString(n1diceCachedDeepKey);
      if ((n1diceCached ?? '').isNotEmpty) {
        n1diceDeepLinkFromPush = n1diceCached;
      }
    } catch (_) {}
  }

  Future<void> n1diceSaveCachedDeep(String uri) async {
    try {
      final SharedPreferences n1dicePrefs =
      await SharedPreferences.getInstance();
      await n1dicePrefs.setString(n1diceCachedDeepKey, uri);
    } catch (_) {}
  }

  Future<void> n1diceSendLoadedOnce({
    required String url,
    required int timestart,
  }) async {
    if (n1diceLoadedOnceSent) return;

    final int n1diceNow =
        DateTime.now().millisecondsSinceEpoch;

    await n1dicePostStat(
      event: 'Loaded',
      timeStart: timestart,
      timeFinish: n1diceNow,
      url: url,
      appSid: n1diceAnalyticsSpyInstance.n1diceAppsFlyerUid,
      firstPageLoadTs: n1diceFirstPageTimestamp,
    );

    await n1diceSaveLoadedFlag();
  }

  void n1diceBootHarbor() {
    n1diceWireFcmHandlers();
    n1diceAnalyticsSpyInstance.n1diceStartTracking(
      onUpdate: () => setState(() {}),
    );
    n1diceBindNotificationTap();
    n1dicePrepareDeviceProfile();
  }

  void n1diceWireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage n1diceMessage) async {
      final dynamic n1diceLink = n1diceMessage.data['uri'];
      if (n1diceLink != null) {
        final String n1diceUri = n1diceLink.toString();
        n1diceDeepLinkFromPush = n1diceUri;
        await n1diceSaveCachedDeep(n1diceUri);
      } else {
        n1diceResetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage n1diceMessage) async {
      final dynamic n1diceLink = n1diceMessage.data['uri'];
      if (n1diceLink != null) {
        final String n1diceUri = n1diceLink.toString();
        n1diceDeepLinkFromPush = n1diceUri;
        await n1diceSaveCachedDeep(n1diceUri);

        n1diceNavigateToUri(n1diceUri);

        await n1dicePushDeviceInfo();
        await n1dicePushAppsFlyerData();
      } else {
        n1diceResetHomeAfterDelay();
      }
    });
  }

  void n1diceBindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onNotificationTap') {
        final Map<String, dynamic> n1dicePayload =
        Map<String, dynamic>.from(call.arguments);
        final String? n1diceUriRaw =
        n1dicePayload['uri']?.toString();

        if (n1diceUriRaw != null &&
            n1diceUriRaw.isNotEmpty &&
            !n1diceUriRaw.contains('Нет URI')) {
          final String n1diceUri = n1diceUriRaw;
          n1diceDeepLinkFromPush = n1diceUri;
          await n1diceSaveCachedDeep(n1diceUri);

          if (!context.mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext context) =>
                  n1diceTableView(n1diceUri),
            ),
                (Route<dynamic> route) => false,
          );

          await n1dicePushDeviceInfo();
          await n1dicePushAppsFlyerData();
        }
      }
    });
  }

  Future<void> n1dicePrepareDeviceProfile() async {
    try {
      await n1diceDeviceProfileInstance.n1diceInitialize();

      final FirebaseMessaging n1diceMessaging =
          FirebaseMessaging.instance;
      final NotificationSettings n1diceSettings =
      await n1diceMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      n1diceDeviceProfileInstance.n1dicePushEnabled =
          n1diceSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
              n1diceSettings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      await n1diceLoadLoadedFlag();
      await n1diceLoadCachedDeep();

      n1diceBosunInstance = n1diceBosunViewModel(
        n1diceDeviceProfileInstance: n1diceDeviceProfileInstance,
        n1diceAnalyticsSpyInstance: n1diceAnalyticsSpyInstance,
      );

      n1diceCourier = n1diceCourierService(
        n1diceBosun: n1diceBosunInstance!,
        n1diceGetWebViewController: () => n1diceWebViewController,
      );
    } catch (error) {
      n1diceLoggerService()
          .n1diceLogError('prepareDeviceProfile fail: $error');
    }
  }

  void n1diceNavigateToUri(String link) async {
    try {
      await n1diceWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(link)),
      );
    } catch (error) {
      n1diceLoggerService().n1diceLogError('navigate error: $error');
    }
  }

  void n1diceResetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        n1diceWebViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(n1diceHomeUrl)),
        );
      } catch (_) {}
    });
  }

  String? _resolveTokenForShip() {
    if (widget.n1diceSignal != null &&
        widget.n1diceSignal!.isNotEmpty) {
      return widget.n1diceSignal;
    }
    return null;
  }

  Future<void> _sendAllDataToPageTwice() async {
    await n1dicePushDeviceInfo();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await n1dicePushDeviceInfo();
      await n1dicePushAppsFlyerData();
    });
  }

  Future<void> n1dicePushDeviceInfo() async {
    final String? n1diceToken = _resolveTokenForShip();

    try {
      await n1diceCourier?.n1dicePutDeviceToLocalStorage(n1diceToken);
    } catch (error) {
      n1diceLoggerService()
          .n1diceLogError('pushDeviceInfo error: $error');
    }
  }

  Future<void> n1dicePushAppsFlyerData() async {
    final String? n1diceToken = _resolveTokenForShip();

    try {
      await n1diceCourier?.n1diceSendRawToPage(
        n1diceToken,
        deepLink: n1diceDeepLinkFromPush,
      );
    } catch (error) {
      n1diceLoggerService()
          .n1diceLogError('pushAppsFlyerData error: $error');
    }
  }

  void n1diceStartWarmProgress() {
    int n1diceTick = 0;
    n1diceWarmProgress = 0.0;

    n1diceWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
          if (!mounted) return;

          setState(() {
            n1diceTick++;
            n1diceWarmProgress = n1diceTick / (n1diceWarmSeconds * 10);

            if (n1diceWarmProgress >= 1.0) {
              n1diceWarmProgress = 1.0;
              n1diceWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      n1diceSleepAt = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && n1diceSleepAt != null) {
        final DateTime n1diceNow = DateTime.now();
        final Duration n1diceDrift =
        n1diceNow.difference(n1diceSleepAt!);

        if (n1diceDrift > const Duration(minutes: 25)) {
          n1diceReboardHarbor();
        }
      }
      n1diceSleepAt = null;
    }
  }

  void n1diceReboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              n1diceHarbor(n1diceSignal: widget.n1diceSignal),
        ),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    n1diceWarmTimer.cancel();

    _parentInstallTimer?.cancel();
    _popupInstallTimer?.cancel();

    _initialLoaderTimer?.cancel();

    n1diceWebViewController = null;
    n1dicePopupWebViewController = null;

    super.dispose();
  }

  bool n1diceIsBareEmail(Uri uri) {
    final String n1diceScheme = uri.scheme;
    if (n1diceScheme.isNotEmpty) return false;
    final String n1diceRaw = uri.toString();
    return n1diceRaw.contains('@') && !n1diceRaw.contains(' ');
  }

  Uri n1diceToMailto(Uri uri) {
    final String n1diceFull = uri.toString();
    final List<String> n1diceParts = n1diceFull.split('?');
    final String n1diceEmail = n1diceParts.first;
    final Map<String, String> n1diceQueryParams = n1diceParts.length > 1
        ? Uri.splitQueryString(n1diceParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: n1diceEmail,
      queryParameters: n1diceQueryParams.isEmpty ? null : n1diceQueryParams,
    );
  }

  Future<bool> n1diceOpenMailExternal(Uri mailto) async {
    try {
      final String scheme = mailto.scheme.toLowerCase();
      final String path = mailto.path.toLowerCase();

      n1diceLoggerService().n1diceLogInfo(
          'n1diceOpenMailExternal: scheme=$scheme path=$path uri=$mailto');

      if (scheme != 'mailto') {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        n1diceLoggerService().n1diceLogInfo(
            'n1diceOpenMailExternal: non-mailto result=$ok');
        return ok;
      }

      final bool can = await canLaunchUrl(mailto);
      n1diceLoggerService().n1diceLogInfo(
          'n1diceOpenMailExternal: canLaunchUrl(mailto) = $can');

      if (can) {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        n1diceLoggerService().n1diceLogInfo(
            'n1diceOpenMailExternal: externalApplication result=$ok');
        if (ok) return true;
      }

      n1diceLoggerService().n1diceLogWarn(
          'n1diceOpenMailExternal: no native handler for mailto, fallback to Gmail Web');
      final Uri gmailUri = n1diceGmailizeMailto(mailto);
      final bool webOk = await n1diceOpenWeb(gmailUri);
      n1diceLoggerService().n1diceLogInfo(
          'n1diceOpenMailExternal: Gmail Web fallback result=$webOk');
      return webOk;
    } catch (e, st) {
      n1diceLoggerService().n1diceLogError(
          'n1diceOpenMailExternal error: $e\n$st; url=$mailto');
      return false;
    }
  }

  Future<bool> n1diceOpenMailWeb(Uri mailto) async {
    final Uri n1diceGmailUri = n1diceGmailizeMailto(mailto);
    return n1diceOpenWeb(n1diceGmailUri);
  }

  Uri n1diceGmailizeMailto(Uri mailUri) {
    final Map<String, String> n1diceQueryParams = mailUri.queryParameters;

    final Map<String, String> n1diceParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailUri.path.isNotEmpty) 'to': mailUri.path,
      if ((n1diceQueryParams['subject'] ?? '').isNotEmpty)
        'su': n1diceQueryParams['subject']!,
      if ((n1diceQueryParams['body'] ?? '').isNotEmpty)
        'body': n1diceQueryParams['body']!,
      if ((n1diceQueryParams['cc'] ?? '').isNotEmpty)
        'cc': n1diceQueryParams['cc']!,
      if ((n1diceQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': n1diceQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', n1diceParams);
  }

  bool n1diceIsPlatformLink(Uri uri) {
    final String n1diceScheme = uri.scheme.toLowerCase();
    if (n1diceSpecialSchemes.contains(n1diceScheme)) {
      return true;
    }

    if (n1diceScheme == 'http' || n1diceScheme == 'https') {
      final String n1diceHost = uri.host.toLowerCase();

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

  String n1diceDigitsOnly(String source) =>
      source.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri n1diceHttpizePlatformUri(Uri uri) {
    final String n1diceScheme = uri.scheme.toLowerCase();

    if (n1diceScheme == 'tg' || n1diceScheme == 'telegram') {
      final Map<String, String> n1diceQp = uri.queryParameters;
      final String? n1diceDomain = n1diceQp['domain'];

      if (n1diceDomain != null && n1diceDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$n1diceDomain',
          <String, String>{
            if (n1diceQp['start'] != null)
              'start': n1diceQp['start']!,
          },
        );
      }

      final String n1dicePath =
      uri.path.isNotEmpty ? uri.path : '';

      return Uri.https(
        't.me',
        '/$n1dicePath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if ((n1diceScheme == 'http' || n1diceScheme == 'https') &&
        uri.host.toLowerCase().endsWith('t.me')) {
      return uri;
    }

    if (n1diceScheme == 'viber') {
      return uri;
    }

    if (n1diceScheme == 'whatsapp') {
      final Map<String, String> n1diceQp = uri.queryParameters;
      final String? n1dicePhone = n1diceQp['phone'];
      final String? n1diceText = n1diceQp['text'];

      if (n1dicePhone != null && n1dicePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${n1diceDigitsOnly(n1dicePhone)}',
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

    if ((n1diceScheme == 'http' || n1diceScheme == 'https') &&
        (uri.host.toLowerCase().endsWith('wa.me') ||
            uri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return uri;
    }

    if (n1diceScheme == 'skype') {
      return uri;
    }

    if (n1diceScheme == 'fb-messenger') {
      final String n1dicePath = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.join('/')
          : '';
      final Map<String, String> n1diceQp = uri.queryParameters;

      final String n1diceId =
          n1diceQp['id'] ?? n1diceQp['user'] ?? n1dicePath;

      if (n1diceId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$n1diceId',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if (n1diceScheme == 'sgnl') {
      final Map<String, String> n1diceQp = uri.queryParameters;
      final String? n1dicePhone = n1diceQp['phone'];
      final String? n1diceUsername = n1diceQp['username'];

      if (n1dicePhone != null && n1dicePhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${n1diceDigitsOnly(n1dicePhone)}',
        );
      }

      if (n1diceUsername != null && n1diceUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$n1diceUsername',
        );
      }

      final String n1dicePath = uri.pathSegments.join('/');
      if (n1dicePath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$n1dicePath',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return uri;
    }

    if (n1diceScheme == 'tel') {
      return Uri.parse('tel:${n1diceDigitsOnly(uri.path)}');
    }

    if (n1diceScheme == 'mailto') {
      return uri;
    }

    if (n1diceScheme == 'bnl') {
      final String n1diceNewPath =
      uri.path.isNotEmpty ? uri.path : '';
      return Uri.https(
        'bnl.com',
        '/$n1diceNewPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    return uri;
  }

  Future<bool> n1diceOpenWeb(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      try {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> n1diceOpenExternal(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      return false;
    }
  }

  void n1diceHandleServerSavedata(String savedata) {
    print('onServerResponse savedata: $savedata');
    if(savedata=='false'){
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
          SimpleFullInAppWebViewPage(),
        ),
            (Route<dynamic> route) => false,
      );
    }



  }

  Color _parseHexColor(String hex) {
    String value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) {
      value = 'FF$value';
    }
    final intColor = int.tryParse(value, radix: 16) ?? 0xFF000000;
    return Color(intColor);
  }

  Future<void> _updateAppDataInLocalStorageFromProfile() async {
    final InAppWebViewController? controller = n1diceWebViewController;
    if (controller == null) return;

    final String? token = _resolveTokenForShip();
    final Map<String, dynamic> map =
    n1diceDeviceProfileInstance.n1diceToMap(fcmToken: token);

    n1diceLoggerService()
        .n1diceLogInfo('updateAppDataFromProfile: ${jsonEncode(map)}');

    await n1diceSaveJsonToLocalStorageAndPrefs(
      controller: controller,
      key: 'app_data',
      data: map,
    );
  }

  void _updateExtraDataFromServerPayload(Map<dynamic, dynamic> root) {
    try {
      final dynamic adataRaw = root['adata'];
      if (adataRaw is Map) {
        final Map adata = adataRaw;

        final dynamic buttonswlRaw = adata['buttonswl'];
        if (buttonswlRaw is List) {
          final List<String> list = buttonswlRaw
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          setState(() {
            _buttonWhitelist = list;
          });
          n1diceLoggerService()
              .n1diceLogInfo('buttonswl updated: $_buttonWhitelist');
          _updateBackButtonVisibility();
        }

        final dynamic savelsRaw = adata['savels'];
        if (savelsRaw is Map) {
          n1diceDeviceProfileInstance.n1diceSavels =
          Map<String, dynamic>.from(savelsRaw);
          n1diceLoggerService().n1diceLogInfo(
              'savels stored in profile: ${n1diceDeviceProfileInstance.n1diceSavels}');
          _updateAppDataInLocalStorageFromProfile();
        }
      }
    } catch (e, st) {
      n1diceLoggerService().n1diceLogError(
          'Error in _updateExtraDataFromServerPayload: $e\n$st');
    }
  }

  void _updateSafeAreaFromServerPayload(Map<dynamic, dynamic> root) {
    n1diceLoggerService()
        .n1diceLogInfo('SAFEAREA RAW PAYLOAD: ${jsonEncode(root)}');

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

    n1diceLoggerService().n1diceLogInfo(
        'SAFEAREA PARSED: enabled=$safearea, light=$bgLightHex, dark=$bgDarkHex');

    if (safearea == null) {
      return;
    }

    final Brightness platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHex;
    if (platformBrightness == Brightness.light) {
      chosenHex = bgLightHex ?? bgDarkHex;
    } else {
      chosenHex = bgDarkHex ?? bgLightHex;
    }

    final bool enabled = safearea;
    Color background =
    enabled ? const Color(0xFF1A1A22) : const Color(0xFF000000);

    if (enabled && chosenHex != null && chosenHex.isNotEmpty) {
      background = _parseHexColor(chosenHex);
    }

    setState(() {
      _safeAreaEnabled = enabled;
      _safeAreaBackgroundColor = background;
      n1diceDeviceProfileInstance.n1diceSafeAreaEnabled = enabled;
      n1diceDeviceProfileInstance.n1diceSafeAreaColor =
      enabled ? (chosenHex ?? '#1A1A22') : '';
    });

    n1diceLoggerService().n1diceLogInfo(
        'SAFEAREA STATE UPDATED: enabled=$_safeAreaEnabled, color=$_safeAreaBackgroundColor (brightness=$platformBrightness)');
  }

  bool _matchesButtonWhitelist(String url) {
    if (url.isEmpty) return false;
    if (_buttonWhitelist.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }

    final String host = uri.host.toLowerCase();
    final String full = uri.toString();

    for (final String item in _buttonWhitelist) {
      final String trimmed = item.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('http://') ||
          trimmed.startsWith('https://')) {
        if (full.startsWith(trimmed)) return true;
      } else {
        final String domain = trimmed.toLowerCase();
        if (host == domain || host.endsWith('.$domain')) return true;
      }
    }

    return false;
  }

  Future<void> _updateBackButtonVisibility() async {
    final String current = _currentUrl ?? n1diceCurrentUrl;
    final bool shouldShow = _matchesButtonWhitelist(current);

    if (_backButtonHiddenAfterTap) {
      _backButtonHiddenAfterTap = false;
    }

    if (shouldShow != _showBackButton) {
      if (mounted) {
        setState(() {
          _showBackButton = shouldShow;
        });
      } else {
        _showBackButton = shouldShow;
      }
    }
  }

  Future<void> _handleBackButtonPressed() async {
    if (mounted) {
      setState(() {
        _backButtonHiddenAfterTap = true;
        _showBackButton = false;
      });
    } else {
      _backButtonHiddenAfterTap = true;
      _showBackButton = false;
    }

    if (_isPopupVisible) {
      await _handlePopupBackPressed();
      return;
    }

    if (n1diceWebViewController == null) return;
    try {
      if (await n1diceWebViewController!.canGoBack()) {
        await n1diceWebViewController!.goBack();
      } else {
        await n1diceWebViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(n1diceHomeUrl)),
        );
      }
    } catch (e, st) {
      n1diceLoggerService()
          .n1diceLogError('Error on back button pressed: $e\n$st');
    }
  }

  InAppWebViewSettings _mainWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  InAppWebViewSettings _popupWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
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

  Future<void> _safeEvaluateJavascript(
      InAppWebViewController? controller, {
        required String source,
        String debugName = 'js',
      }) async {
    if (controller == null) return;
    if (!mounted) return;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      await controller.evaluateJavascript(source: source);
    } catch (e) {
      print('WERLOG: safeEvaluateJavascript error [$debugName]: $e');
    }
  }

  Future<void> _installJsErrorLogger(
      InAppWebViewController controller) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installJsErrorLogger',
      source: r'''
        (function() {
          if (window.__ncupJsLoggerInstalled) return;
          window.__ncupJsLoggerInstalled = true;

          function serializeError(err) {
            try {
              if (!err) return null;
              var plain = {};
              Object.getOwnPropertyNames(err).forEach(function(key) {
                plain[key] = err[key];
              });
              return plain;
            } catch (_) {
              return { message: String(err) };
            }
          }

          window.onerror = function(message, source, lineno, colno, error) {
            try {
              var payload = {
                type: 'onerror',
                message: String(message || ''),
                source: String(source || ''),
                lineno: lineno || 0,
                colno: colno || 0,
                error: serializeError(error)
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger onerror inner fail', e);
            }
          };

          window.addEventListener('unhandledrejection', function(event) {
            try {
              var reason = event.reason;
              var payload = {
                type: 'unhandledrejection',
                reason: serializeError(reason) || { message: String(reason || '') }
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger unhandledrejection inner fail', e);
            }
          });
        })();
      ''',
    );
  }

  Future<void> _installPostMessageBridge(
      InAppWebViewController controller, {
        required String label,
      }) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installPostMessageBridge-$label',
      source: '''
        (function() {
          if (window.__ncupPostMessageBridgeInstalled_$label) return;
          window.__ncupPostMessageBridgeInstalled_$label = true;

          window.addEventListener('message', function(event) {
            try {
              var dataRaw = event.data;
              var dataString;
              try {
                dataString = JSON.stringify(dataRaw);
              } catch (e) {
                dataString = String(dataRaw);
              }

              var payload = {
                label: '$label',
                origin: String(event.origin || ''),
                data: dataString,
                href: String(window.location.href || '')
              };

              console.log('[NCUP postMessage $label]', payload);

              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupPostMessage', payload);
              }

              try {
                var parsed = dataRaw;
                if (typeof parsed === 'string') {
                  parsed = JSON.parse(parsed);
                }
                if (parsed && parsed.type === 'newTab' && parsed.url) {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('NcupCheckoutAction', parsed);
                  }
                }
              } catch (_) {}
            } catch (e) {
              console.log('NcupPostMessage bridge error', e);
            }
          });
        })();
      ''',
    );
  }

  Future<void> _installCheckoutInterceptor(
      InAppWebViewController controller) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installCheckoutInterceptor',
      source: r'''
        (function() {
          if (window.__ncupCheckoutInterceptorInstalled) return;
          window.__ncupCheckoutInterceptorInstalled = true;

          function sendToFlutter(data) {
            try {
              if (!data || typeof data !== 'object') return;
              if (data.type === 'newTab' && data.url) {
                console.log('[NCUP checkout interceptor] newTab:', data.url);
                if (
                  window.flutter_inappwebview &&
                  window.flutter_inappwebview.callHandler
                ) {
                  window.flutter_inappwebview.callHandler(
                    'NcupCheckoutAction',
                    data
                  );
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] send error', e);
            }
          }

          function tryParseMaybeJson(value) {
            try {
              if (!value) return null;
              if (typeof value === 'object') {
                return value;
              }
              if (typeof value === 'string') {
                return JSON.parse(value);
              }
              return null;
            } catch (e) {
              return null;
            }
          }

          function tryHandlePayload(payload) {
            try {
              var data = tryParseMaybeJson(payload);
              if (!data) return;

              if (Array.isArray(data)) {
                data.forEach(function(item) {
                  if (item && item.type === 'newTab' && item.url) {
                    sendToFlutter(item);
                  }
                });
                return;
              }

              if (data.type === 'newTab' && data.url) {
                sendToFlutter(data);
                return;
              }

              if (data.savedata) {
                var saved = tryParseMaybeJson(data.savedata);
                if (saved && saved.type === 'newTab' && saved.url) {
                  sendToFlutter(saved);
                  return;
                }
              }

              if (data.data) {
                var nested = tryParseMaybeJson(data.data);
                if (nested && nested.type === 'newTab' && nested.url) {
                  sendToFlutter(nested);
                  return;
                }
              }

              if (data.content) {
                var content = tryParseMaybeJson(data.content);
                if (content && content.type === 'newTab' && content.url) {
                  sendToFlutter(content);
                  return;
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] handle error', e);
            }
          }

          var originalFetch = window.fetch;
          if (originalFetch) {
            window.fetch = function() {
              return originalFetch.apply(this, arguments).then(function(response) {
                try {
                  var cloned = response.clone();
                  cloned.text().then(function(text) {
                    tryHandlePayload(text);
                  }).catch(function() {});
                } catch (e) {}
                return response;
              });
            };
          }

          var OriginalXHR = window.XMLHttpRequest;
          if (OriginalXHR) {
            window.XMLHttpRequest = function() {
              var xhr = new OriginalXHR();
              var originalOpen = xhr.open;
              var originalSend = xhr.send;

              xhr.open = function() {
                return originalOpen.apply(xhr, arguments);
              };

              xhr.send = function() {
                xhr.addEventListener('load', function() {
                  try {
                    tryHandlePayload(xhr.responseText);
                  } catch (e) {}
                });
                return originalSend.apply(xhr, arguments);
              };

              return xhr;
            };
          }

          var originalOpen = window.open;
          window.open = function(url, target, features) {
            try {
              console.log('[NCUP window.open intercepted]', url, target, features);
            } catch (e) {}

            if (originalOpen) {
              return originalOpen.apply(window, arguments);
            }
            return null;
          };
        })();
      ''',
    );
  }

  Future<void> _installLocalStorageHook(
      InAppWebViewController controller) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installLocalStorageHook',
      source: r'''
        (function() {
          if (window.__ncupLocalStorageHookInstalled) return;
          window.__ncupLocalStorageHookInstalled = true;

          try {
            var originalSetItem = window.localStorage.setItem;
            window.localStorage.setItem = function(key, value) {
              try {
                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                  window.flutter_inappwebview.callHandler('NcupLocalStorageSetItem', {
                    key: String(key),
                    value: String(value)
                  });
                }
              } catch (e) {
                console.log('Ncup localStorage hook error', e);
              }
              return originalSetItem.apply(this, arguments);
            };
          } catch (e) {
            console.log('Ncup localStorage hook init error', e);
          }
        })();
      ''',
    );
  }

  Future<void> _safeInstallAll(
      InAppWebViewController? controller, {
        required String label,
      }) async {
    if (controller == null) return;
    if (!mounted) return;

    try {
      await Future<void>.delayed(
        label == 'popup'
            ? const Duration(milliseconds: 550)
            : const Duration(milliseconds: 250),
      );
      if (!mounted) return;
      await _installJsErrorLogger(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installPostMessageBridge(controller, label: label);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installCheckoutInterceptor(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installLocalStorageHook(controller);
    } catch (e) {
      print('WERLOG: safeInstallAll error label=$label error=$e');
    }
  }

  void _scheduleSafeInstall(
      InAppWebViewController controller, {
        required String label,
      }) {
    if (label == 'popup') {
      _popupInstallTimer?.cancel();
      _popupInstallTimer =
          Timer(const Duration(milliseconds: 450), () async {
            if (!mounted) return;
            await _safeInstallAll(controller, label: label);
          });
    } else {
      _parentInstallTimer?.cancel();
      _parentInstallTimer =
          Timer(const Duration(milliseconds: 250), () async {
            if (!mounted) return;
            await _safeInstallAll(controller, label: label);
          });
    }
  }

  Map<String, dynamic>? _tryDecodeMap(dynamic value) {
    try {
      if (value == null) return null;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      if (value is String) {
        final String trimmed = value.trim();
        if (trimmed.isEmpty) return null;
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _openExternalForJsonNewTab(Uri uri) async {
    if (_isAboutBlankUri(uri)) return false;

    final String url = uri.toString();

    if (_handledNewTabUrls.contains(url)) {
      print('WERLOG: duplicate JSON newTab ignored url=$url');
      return true;
    }

    _handledNewTabUrls.add(url);

    if (_isOpeningExternalNewTab) {
      print('WERLOG: external newTab already opening, ignored url=$url');
      return false;
    }

    _isOpeningExternalNewTab = true;

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      print('WERLOG: JSON newTab external launched=$launched url=$url');
      return launched;
    } catch (e) {
      print('WERLOG: JSON newTab external error=$e url=$url');
      return false;
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _isOpeningExternalNewTab = false;
      });
    }
  }

  Future<bool> _handleCheckoutAction(dynamic rawPayload) async {
    try {
      Map<String, dynamic>? data = _tryDecodeMap(rawPayload);
      if (data == null) return false;

      if (data.containsKey('savedata')) {
        final Map<String, dynamic>? savedataMap =
        _tryDecodeMap(data['savedata']);
        if (savedataMap != null) {
          data = savedataMap;
        }
      }

      if (data.containsKey('data')) {
        final Map<String, dynamic>? dataMap = _tryDecodeMap(data['data']);
        if (dataMap != null &&
            dataMap['type']?.toString() == 'newTab' &&
            (dataMap['url']?.toString() ?? '').isNotEmpty) {
          data = dataMap;
        }
      }

      if (data.containsKey('content')) {
        final Map<String, dynamic>? contentMap =
        _tryDecodeMap(data['content']);
        if (contentMap != null &&
            contentMap['type']?.toString() == 'newTab' &&
            (contentMap['url']?.toString() ?? '').isNotEmpty) {
          data = contentMap;
        }
      }

      final String type = data['type']?.toString() ?? '';
      final String url = data['url']?.toString() ?? '';

      if (type == 'newTab' && url.isNotEmpty) {
        final Uri? uri = Uri.tryParse(url);
        if (uri == null || _isAboutBlankUri(uri)) {
          print('WERLOG: invalid JSON newTab uri=$url');
          return false;
        }

        print('WERLOG: handle JSON newTab url=$url');
        await _openExternalForJsonNewTab(uri);
        return true;
      }

      return false;
    } catch (e) {
      print('WERLOG: handleCheckoutAction error: $e');
      return false;
    }
  }

  Future<bool> _onCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction request,
      ) async {
    final Uri? n1diceUri = request.request.url;
    final String urlString = n1diceUri?.toString() ?? '';

    print(
      'WERLOG: MAIN onCreateWindow '
          'windowId=${request.windowId} '
          'url=$urlString '
          'isDialog=${request.isDialog} '
          'hasGesture=${request.hasGesture}',
    );

    if (n1diceUri != null) {
      _currentUrl = n1diceUri.toString();
      await _updateBackButtonVisibility();

      // Google – остаёмся в WebView, просто включаем random UA
      await _updateUserAgentForUrl(n1diceUri);

      if (n1diceIsBankScheme(n1diceUri) ||
          ((n1diceUri.scheme == 'http' || n1diceUri.scheme == 'https') &&
              n1diceIsBankDomain(n1diceUri))) {
        await n1diceOpenBank(n1diceUri);
        return false;
      }

      if (n1diceIsBareEmail(n1diceUri)) {
        final Uri n1diceMailto = n1diceToMailto(n1diceUri);
        await n1diceOpenMailExternal(n1diceMailto);
        return false;
      }

      final String n1diceScheme = n1diceUri.scheme.toLowerCase();

      if (n1diceScheme == 'mailto') {
        await n1diceOpenMailExternal(n1diceUri);
        return false;
      }

      if (n1diceScheme == 'tel') {
        await launchUrl(n1diceUri,
            mode: LaunchMode.externalApplication);
        return false;
      }

      final String host = n1diceUri.host.toLowerCase();
      final bool n1diceIsSocial = host.endsWith('facebook.com') ||
          host.endsWith('instagram.com') ||
          host.endsWith('twitter.com') ||
          host.endsWith('x.com');

      if (n1diceIsSocial) {
        await n1diceOpenExternal(n1diceUri);
        return false;
      }

      if (n1diceIsPlatformLink(n1diceUri)) {
        final Uri n1diceWebUri = n1diceHttpizePlatformUri(n1diceUri);
        await n1diceOpenExternal(n1diceWebUri);
        return false;
      }
    }

    if (!mounted) return false;

    setState(() {
      _popupCreateAction = request;
      _popupUrl = urlString.isNotEmpty && !_isAboutBlankUrl(urlString)
          ? urlString
          : null;
      _popupCurrentUrl = _popupUrl;
      _isPopupVisible = true;
      _popupCanGoBack = false;
    });

    return true;
  }

  Future<bool> _onPopupCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction createWindowAction,
      ) async {
    final Uri? uri = createWindowAction.request.url;
    final String urlString = uri?.toString() ?? '';

    print(
      'WERLOG: POPUP onCreateWindow '
          'windowId=${createWindowAction.windowId} '
          'url=$urlString',
    );

    if (!mounted) return false;

    if (uri != null) {
      // Google в попапе — тоже внутри, просто UA
      await _updateUserAgentForUrl(uri);
    }

    if (createWindowAction.windowId != null) {
      setState(() {
        _popupCreateAction = createWindowAction;
        _popupUrl = urlString.isNotEmpty && !_isAboutBlankUrl(urlString)
            ? urlString
            : _popupUrl;
        _popupCurrentUrl = _popupUrl;
        _isPopupVisible = true;
      });
      return true;
    }

    if (urlString.isNotEmpty && !_isAboutBlankUrl(urlString)) {
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(urlString)),
        );
      } catch (e) {
        print('WERLOG: popup inner window.open load error: $e url=$urlString');
      }
    }

    return false;
  }

  void _closePopup() {
    setState(() {
      _isPopupVisible = false;
      _popupUrl = null;
      _popupCurrentUrl = null;
      _popupCreateAction = null;
      _popupCanGoBack = false;
      n1dicePopupWebViewController = null;
    });
  }

  Future<void> _closePopupAndNotifyParent({
    String reason = 'closed_by_user',
  }) async {
    try {
      await n1diceWebViewController?.evaluateJavascript(
        source: '''
          try {
            window.dispatchEvent(new MessageEvent('message', {
              data: ${jsonEncode({
          'type': 'ncup_popup_closed',
          'reason': reason,
        })},
              origin: window.location.origin
            }));
          } catch(e) {
            console.log('ncup popup close notify failed', e);
          }
        ''',
      );
    } catch (e) {
      print('WERLOG: closePopup notify parent error: $e');
    }
    _closePopup();
  }

  Future<void> _refreshPopupCanGoBack() async {
    final InAppWebViewController? c = n1dicePopupWebViewController;
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
    } catch (e) {
      print('WERLOG: _refreshPopupCanGoBack error: $e');
    }
  }

  Future<void> _handlePopupBackPressed() async {
    final InAppWebViewController? c = n1dicePopupWebViewController;
    if (c == null) {
      _closePopup();
      return;
    }
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _refreshPopupCanGoBack();
        });
      } else {
        await _closePopupAndNotifyParent(
            reason: 'popup_back_no_history');
      }
    } catch (e) {
      print('WERLOG: _handlePopupBackPressed error: $e');
      _closePopup();
    }
  }

  bool _isCurrentPopupInWhitelist() {
    if (!_isPopupVisible) return false;
    final String popupUrlForCheck =
        _popupCurrentUrl ?? _popupUrl ?? '';
    return _matchesButtonWhitelist(popupUrlForCheck);
  }

  Widget _buildPopupWebView() {
    final bool popupInWhitelist = _isCurrentPopupInWhitelist();

    final bool showBackArrow = !popupInWhitelist && _popupCanGoBack;
    final bool showCloseButton =
        !popupInWhitelist && !_popupCanGoBack;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: Column(
          children: [
            if (!popupInWhitelist) ...[
              SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black,
                  child: Row(
                    children: [
                      if (showBackArrow)
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: _handlePopupBackPressed,
                        )
                      else if (showCloseButton)
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white),
                          onPressed: () {
                            _closePopupAndNotifyParent(
                                reason: 'close_button');
                          },
                        ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
            ],
            Expanded(
              child: InAppWebView(
                windowId: _popupCreateAction?.windowId,
                initialUrlRequest:
                (_popupCreateAction?.windowId == null) &&
                    _popupUrl != null
                    ? URLRequest(url: WebUri(_popupUrl!))
                    : null,
                initialSettings: _popupWebViewSettings(),
                onWebViewCreated:
                    (InAppWebViewController popupController) async {
                  n1dicePopupWebViewController = popupController;

                  print(
                    'WERLOG: popup created '
                        'windowId=${_popupCreateAction?.windowId} '
                        'initialUrl=${_popupUrl ?? _popupCreateAction?.request.url}',
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupLocalStorageSetItem',
                    callback: (List<dynamic> args) async {
                      try {
                        if (args.isEmpty) return null;
                        final dynamic raw = args.first;
                        if (raw is Map) {
                          final String key =
                              raw['key']?.toString() ?? '';
                          final String value =
                              raw['value']?.toString() ?? '';
                          if (key.isNotEmpty) {
                            final SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                            await prefs.setString(key, value);
                            n1diceLoggerService().n1diceLogInfo(
                                'NcupLocalStorageSetItem (popup): saved key="$key" len=${value.length}');
                          }
                        }
                      } catch (e, st) {
                        n1diceLoggerService().n1diceLogError(
                            'NcupLocalStorageSetItem popup handler error: $e\n$st');
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupCheckoutAction',
                    callback: (List<dynamic> args) async {
                      print('WERLOG: POPUP NcupCheckoutAction args=$args');
                      if (args.isNotEmpty) {
                        await _handleCheckoutAction(args.first);
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupPostMessage',
                    callback: (List<dynamic> args) async {
                      print('WERLOG: POPUP NcupPostMessage args=$args');
                      if (args.isNotEmpty) {
                        final dynamic first = args.first;
                        if (first is Map && first['data'] != null) {
                          await _handleCheckoutAction(first['data']);
                        } else {
                          await _handleCheckoutAction(first);
                        }
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupJSLogger',
                    callback: (List<dynamic> args) {
                      print('WERLOG: POPUP JS error payload: $args');
                      return null;
                    },
                  );
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                onLoadStart: (controller, uri) async {
                  print('WERLOG: popup onLoadStart url=$uri');
                  if (uri != null && !_isAboutBlankUri(uri)) {
                    // Google / не-Google — обновляем UA, остаёмся в WebView
                    await _updateUserAgentForUrl(uri);

                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = uri.toString();
                        if (_backButtonHiddenAfterTap) {
                          _backButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _refreshPopupCanGoBack();
                },
                onLoadStop: (controller, uri) async {
                  print('WERLOG: popup onLoadStop url=$uri');
                  if (uri != null && !_isAboutBlankUri(uri)) {
                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = uri.toString();
                      });
                    }
                  }
                  if (!_isAboutBlankUri(uri)) {
                    _scheduleSafeInstall(controller, label: 'popup');
                  }
                  _refreshPopupCanGoBack();
                },
                onUpdateVisitedHistory:
                    (controller, url, isReload) async {
                  if (url != null && !_isAboutBlankUri(url)) {
                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = url.toString();
                        if (_backButtonHiddenAfterTap) {
                          _backButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _refreshPopupCanGoBack();
                },
                onCreateWindow: _onPopupCreateWindowHandler,
                shouldOverrideUrlLoading:
                    (InAppWebViewController controller,
                    NavigationAction navigationAction) async {
                  final Uri? uri = navigationAction.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (_isAboutBlankUri(uri)) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  // Google — меняем UA и даём грузиться внутри
                  await _updateUserAgentForUrl(uri);

                  final String scheme =
                  uri.scheme.toLowerCase();

                  if (n1diceIsBareEmail(uri)) {
                    final Uri mailto = n1diceToMailto(uri);
                    await n1diceOpenMailExternal(mailto);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'mailto') {
                    await n1diceOpenMailExternal(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'tel') {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (n1diceIsBankScheme(uri) ||
                      ((scheme == 'http' || scheme == 'https') &&
                          n1diceIsBankDomain(uri))) {
                    await n1diceOpenBank(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme != 'http' && scheme != 'https') {
                    print(
                      'WERLOG: popup blocked non-http/https scheme=$scheme url=$uri',
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCloseWindow: (controller) {
                  print('WERLOG: popup onCloseWindow');
                  _closePopup();
                },
                onLoadError: (controller, uri, code, message) async {
                  print(
                    'WERLOG: popup onLoadError url=$uri code=$code msg=$message',
                  );
                },
                onReceivedError: (controller, request, error) async {
                  print(
                    'WERLOG: popup onReceivedError '
                        'url=${request.url} '
                        'type=${error.type} '
                        'desc=${error.description}',
                  );
                },
                onReceivedHttpError:
                    (controller, request, errorResponse) async {
                  print(
                    'WERLOG: popup onReceivedHttpError '
                        'url=${request.url} '
                        'status=${errorResponse.statusCode} '
                        'reason=${errorResponse.reasonPhrase}',
                  );
                },
                onConsoleMessage: (controller, consoleMessage) {
                  print(
                    'WERLOG: popup console: '
                        '${consoleMessage.messageLevel} ${consoleMessage.message}',
                  );
                },
                onDownloadStartRequest:
                    (controller, req) async {
                  print(
                      'WERLOG: popup download for url=${req.url}, opening external');
                  await n1diceOpenExternal(req.url);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- LOADER для WebView (фон + прогресс) ----------------

  Widget _buildWebViewLoaderOverlay() {
    final double percent =
    (n1diceWarmProgress * 100).clamp(0, 100).toDouble();

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Фон как в Hall
          Image.asset(
            'assets/nightdice_bg.png',
            fit: BoxFit.cover,
          ),
          Container(
            color: Colors.black.withOpacity(0.25),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                const Spacer(),
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: n1diceWarmProgress,
                          backgroundColor: Colors.black.withOpacity(0.4),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFC04A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Loading...',
                            style: TextStyle(
                              color: Color(0xFFFFC04A),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${percent.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Color(0xFFFFC04A),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    n1diceBindNotificationTap();

    final Color bgColor =
    _safeAreaEnabled ? _safeAreaBackgroundColor : Colors.black;

    // Сам WebView (грузится всегда, независимо от лоадера)
    final Widget webView = Stack(
      children: <Widget>[
        if (n1diceCoverVisible)
          Center(child: Container())
        else
          Container(
            color: bgColor,
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  key: ValueKey<int>(n1diceWebViewKeyCounter),
                  initialSettings: _mainWebViewSettings(),
                  initialUrlRequest: URLRequest(
                    url: WebUri(n1diceHomeUrl),
                  ),
                  onWebViewCreated:
                      (InAppWebViewController controller) async {
                    n1diceWebViewController = controller;
                    _currentUrl = n1diceHomeUrl;

                    n1diceBosunInstance ??= n1diceBosunViewModel(
                      n1diceDeviceProfileInstance:
                      n1diceDeviceProfileInstance,
                      n1diceAnalyticsSpyInstance:
                      n1diceAnalyticsSpyInstance,
                    );

                    n1diceCourier ??= n1diceCourierService(
                      n1diceBosun: n1diceBosunInstance!,
                      n1diceGetWebViewController: () =>
                      n1diceWebViewController,
                    );

                    try {
                      final ua =
                      await controller.evaluateJavascript(
                        source: "navigator.userAgent",
                      );
                      if (ua is String && ua.trim().isNotEmpty) {
                        _baseUserAgent = ua.trim();
                        _currentUserAgent = _baseUserAgent!;
                        n1diceDeviceProfileInstance
                            .n1diceBaseUserAgent = _baseUserAgent;
                        n1diceLoggerService().n1diceLogInfo(
                            'Initial WebView User-Agent: $_baseUserAgent');
                        print(
                            '[UA] INITIAL WEBVIEW USER AGENT: $_baseUserAgent');
                      }
                    } catch (e) {
                      n1diceLoggerService().n1diceLogWarn(
                          'Failed to read navigator.userAgent on create: $e');
                    }

                    await _applyNormalUserAgentIfNeeded();

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupLocalStorageSetItem',
                      callback: (List<dynamic> args) async {
                        try {
                          if (args.isEmpty) return null;
                          final dynamic raw = args.first;
                          if (raw is Map) {
                            final String key =
                                raw['key']?.toString() ?? '';
                            final String value =
                                raw['value']?.toString() ?? '';
                            if (key.isNotEmpty) {
                              final SharedPreferences prefs =
                              await SharedPreferences.getInstance();
                              await prefs.setString(key, value);
                              n1diceLoggerService().n1diceLogInfo(
                                  'NcupLocalStorageSetItem (main): saved key="$key" len=${value.length}');
                            }
                          }
                        } catch (e, st) {
                          n1diceLoggerService().n1diceLogError(
                              'NcupLocalStorageSetItem main handler error: $e\n$st');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'onServerResponse',
                      callback: (List<dynamic> args) async {
                        if (args.isEmpty) return null;

                        print("Get Data server $args");

                        try {
                          dynamic first = args[0];

                          if (first is List && first.isNotEmpty) {
                            first = first.first;
                          }

                          final bool handled =
                          await _handleCheckoutAction(first);
                          if (handled) {}

                          if (first is Map) {
                            final Map<dynamic, dynamic> root =
                                first;

                            if (root['savedata'] != null) {
                              n1diceHandleServerSavedata(
                                  root['savedata']
                                      .toString());
                              await _handleCheckoutAction(
                                  root['savedata']);
                            }

                            _updateExtraDataFromServerPayload(
                                root);
                            _updateSafeAreaFromServerPayload(
                                root);
                            await _updateUserAgentFromServerPayload(
                                root);

                            await _applyNormalUserAgentIfNeeded();

                            try {
                              if (!_loadedJsExecutedOnce) {
                                final dynamic adataRaw =
                                root['adata'];
                                if (adataRaw is Map) {
                                  final Map adata = adataRaw;
                                  final dynamic loadedJsRaw =
                                  adata['loadedjs'];
                                  if (loadedJsRaw != null) {
                                    final String loadedJs =
                                    loadedJsRaw
                                        .toString()
                                        .trim();
                                    if (loadedJs.isNotEmpty) {
                                      _pendingLoadedJs =
                                          loadedJs;
                                      n1diceLoggerService()
                                          .n1diceLogInfo(
                                        'loadedjs received, will execute ONCE after 6 seconds',
                                      );

                                      Future<void>.delayed(
                                        const Duration(
                                            seconds: 6),
                                            () async {
                                          if (!mounted)
                                            return;
                                          if (_loadedJsExecutedOnce) {
                                            n1diceLoggerService()
                                                .n1diceLogInfo(
                                                'Skipping loadedjs: already executed once');
                                            return;
                                          }
                                          if (n1diceWebViewController ==
                                              null) {
                                            n1diceLoggerService()
                                                .n1diceLogWarn(
                                                'Skipping loadedjs execution: controller is null');
                                            return;
                                          }
                                          final String?
                                          jsToRun =
                                              _pendingLoadedJs;
                                          if (jsToRun ==
                                              null ||
                                              jsToRun
                                                  .isEmpty) {
                                            return;
                                          }
                                          n1diceLoggerService()
                                              .n1diceLogInfo(
                                              'Executing loadedjs from server payload (ONCE, delayed 6s)');
                                          try {
                                            await n1diceWebViewController
                                                ?.evaluateJavascript(
                                              source:
                                              jsToRun,
                                            );
                                            _loadedJsExecutedOnce =
                                            true;
                                          } catch (e, st) {
                                            n1diceLoggerService()
                                                .n1diceLogError(
                                                'Error executing delayed loadedjs: $e\n$st');
                                          }
                                        },
                                      );
                                    }
                                  }
                                }
                              } else {
                                n1diceLoggerService()
                                    .n1diceLogInfo(
                                    'loadedjs ignored: already executed once earlier');
                              }
                            } catch (e, st) {
                              n1diceLoggerService()
                                  .n1diceLogError(
                                  'Error scheduling loadedjs: $e\n$st');
                            }
                          }
                        } catch (e, st) {
                          print('onServerResponse error: $e\n$st');
                        }

                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupCheckoutAction',
                      callback: (List<dynamic> args) async {
                        try {
                          print(
                              'WERLOG: MAIN NcupCheckoutAction args=$args');
                          if (args.isNotEmpty) {
                            await _handleCheckoutAction(
                                args.first);
                          }
                        } catch (e) {
                          print(
                              'WERLOG: MAIN NcupCheckoutAction error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupJSLogger',
                      callback: (List<dynamic> args) {
                        try {
                          final dynamic payload =
                          args.isNotEmpty
                              ? args.first
                              : null;
                          print(
                              'WERLOG: MAIN JS error payload: $payload');
                        } catch (e) {
                          print(
                              'WERLOG: NcupJSLogger handler error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupPostMessage',
                      callback: (List<dynamic> args) async {
                        try {
                          print(
                              'WERLOG: MAIN NcupPostMessage args=$args');
                          if (args.isNotEmpty) {
                            final dynamic first =
                                args.first;
                            if (first is Map &&
                                first['data'] != null) {
                              await _handleCheckoutAction(
                                  first['data']);
                            } else {
                              await _handleCheckoutAction(
                                  first);
                            }
                          }
                        } catch (e) {
                          print(
                              'WERLOG: NcupPostMessage handler error: $e');
                        }
                        return null;
                      },
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  onLoadStart:
                      (InAppWebViewController controller,
                      Uri? uri) async {
                    n1diceStartLoadTimestamp =
                        DateTime.now().millisecondsSinceEpoch;

                    final Uri? n1diceViewUri = uri;
                    if (n1diceViewUri != null) {
                      _currentUrl = n1diceViewUri.toString();

                      // Google / не-Google — только меняем UA, всё остаётся в WebView
                      await _updateUserAgentForUrl(
                          n1diceViewUri);

                      await _updateBackButtonVisibility();

                      if (n1diceIsBareEmail(n1diceViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        final Uri n1diceMailto =
                        n1diceToMailto(
                            n1diceViewUri);
                        await n1diceOpenMailExternal(
                            n1diceMailto);
                        return;
                      }

                      final String n1diceScheme =
                      n1diceViewUri.scheme
                          .toLowerCase();

                      if (n1diceScheme == 'mailto') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await n1diceOpenMailExternal(
                            n1diceViewUri);
                        return;
                      }

                      if (n1diceIsBankScheme(
                          n1diceViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await n1diceOpenBank(
                            n1diceViewUri);
                        return;
                      }

                      if (n1diceScheme != 'http' &&
                          n1diceScheme != 'https') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                      }
                    }
                  },
                  onLoadError: (
                      InAppWebViewController controller,
                      Uri? uri,
                      int code,
                      String message,
                      ) async {
                    final int n1diceNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String n1diceEvent =
                        'InAppWebViewError(code=$code, message=$message)';

                    await n1dicePostStat(
                      event: n1diceEvent,
                      timeStart: n1diceNow,
                      timeFinish: n1diceNow,
                      url: uri?.toString() ?? '',
                      appSid: n1diceAnalyticsSpyInstance
                          .n1diceAppsFlyerUid,
                      firstPageLoadTs:
                      n1diceFirstPageTimestamp,
                    );
                  },
                  onReceivedError: (
                      InAppWebViewController controller,
                      WebResourceRequest request,
                      WebResourceError error,
                      ) async {
                    final int n1diceNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String n1diceDescription =
                    (error.description ?? '')
                        .toString();
                    final String n1diceEvent =
                        'WebResourceError(code=$error, message=$n1diceDescription)';

                    await n1dicePostStat(
                      event: n1diceEvent,
                      timeStart: n1diceNow,
                      timeFinish: n1diceNow,
                      url: request.url?.toString() ?? '',
                      appSid: n1diceAnalyticsSpyInstance
                          .n1diceAppsFlyerUid,
                      firstPageLoadTs:
                      n1diceFirstPageTimestamp,
                    );
                  },
                  onLoadStop:
                      (InAppWebViewController controller,
                      Uri? uri) async {
                    n1diceCurrentUrl = uri.toString();
                    _currentUrl = n1diceCurrentUrl;

                    if (uri != null) {
                      await _updateUserAgentForUrl(uri);
                    }

                    if (!_isAboutBlankUri(uri)) {
                      _scheduleSafeInstall(
                          controller,
                          label: 'parent');
                    }

                    await debugPrintCurrentUserAgent();

                    await _sendAllDataToPageTwice();
                    await _updateBackButtonVisibility();

                    Future<void>.delayed(
                      const Duration(seconds: 20),
                          () {
                        n1diceSendLoadedOnce(
                          url: n1diceCurrentUrl
                              .toString(),
                          timestart:
                          n1diceStartLoadTimestamp,
                        );
                      },
                    );
                  },
                  onUpdateVisitedHistory:
                      (controller, url, isReload) async {
                    if (url != null &&
                        !_isAboutBlankUri(url)) {
                      _currentUrl = url.toString();
                      await _updateBackButtonVisibility();
                    }
                  },
                  shouldOverrideUrlLoading:
                      (InAppWebViewController controller,
                      NavigationAction action) async {
                    final Uri? n1diceUri =
                        action.request.url;
                    if (n1diceUri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    _currentUrl = n1diceUri.toString();
                    await _updateBackButtonVisibility();

                    if (_isAboutBlankUri(n1diceUri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    // Google / не-Google — всё в WebView, переключаем UA
                    await _updateUserAgentForUrl(
                        n1diceUri);

                    if (n1diceIsBareEmail(n1diceUri)) {
                      final Uri n1diceMailto =
                      n1diceToMailto(n1diceUri);
                      await n1diceOpenMailExternal(
                          n1diceMailto);
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String n1diceScheme =
                    n1diceUri.scheme
                        .toLowerCase();

                    if (n1diceScheme == 'mailto') {
                      await n1diceOpenMailExternal(
                          n1diceUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (n1diceIsBankScheme(
                        n1diceUri)) {
                      await n1diceOpenBank(n1diceUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if ((n1diceScheme == 'http' ||
                        n1diceScheme == 'https') &&
                        n1diceIsBankDomain(
                            n1diceUri)) {
                      await n1diceOpenBank(n1diceUri);

                      if (_isAdobeRedirect(
                          n1diceUri)) {
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AdobeRedirectScreen(
                                      uri: n1diceUri),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (n1diceScheme == 'tel') {
                      await launchUrl(
                        n1diceUri,
                        mode: LaunchMode
                            .externalApplication,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String host =
                    n1diceUri.host.toLowerCase();
                    final bool n1diceIsSocial =
                        host.endsWith('facebook.com') ||
                            host.endsWith(
                                'instagram.com') ||
                            host.endsWith(
                                'twitter.com') ||
                            host.endsWith('x.com');

                    if (n1diceIsSocial) {
                      await n1diceOpenExternal(
                          n1diceUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (n1diceIsPlatformLink(
                        n1diceUri)) {
                      final Uri n1diceWebUri =
                      n1diceHttpizePlatformUri(
                          n1diceUri);
                      await n1diceOpenExternal(
                          n1diceWebUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (n1diceScheme != 'http' &&
                        n1diceScheme != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: _onCreateWindowHandler,
                  onCloseWindow: (controller) {
                    print('WERLOG: MAIN onCloseWindow');
                  },
                  onDownloadStartRequest:
                      (InAppWebViewController controller,
                      DownloadStartRequest req) async {
                    await n1diceOpenExternal(req.url);
                  },
                  onConsoleMessage: (controller,
                      consoleMessage) {
                    print(
                      'WERLOG: MAIN console: '
                          '${consoleMessage.messageLevel} ${consoleMessage.message}',
                    );
                  },
                ),
                if (_isPopupVisible &&
                    (_popupUrl != null ||
                        _popupCreateAction != null))
                  _buildPopupWebView(),
              ],
            ),
          ),
      ],
    );

    final bool popupInWhitelist =
    _isCurrentPopupInWhitelist();

    final bool whitelistMatch =
        (!_isPopupVisible && _showBackButton) ||
            popupInWhitelist;

    final bool shouldShowTopBackBar =
        whitelistMatch && !_backButtonHiddenAfterTap;

    final Color topBarColor =
    _safeAreaEnabled ? _safeAreaBackgroundColor : Colors.black;

    final Widget topBackBar = shouldShowTopBackBar
        ? Container(
      color: topBarColor,
      padding: const EdgeInsets.only(left: 4, right: 4),
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back,
                color: Colors.white),
            onPressed: _handleBackButtonPressed,
          ),
        ],
      ),
    )
        : const SizedBox.shrink();

    final Widget columnWithWebView = Column(
      children: [
        topBackBar,
        Expanded(child: webView),
      ],
    );

    final Widget bodyStack = Stack(
      children: [
        columnWithWebView,
        if (_showInitialLoader) _buildWebViewLoaderOverlay(),
      ],
    );

    final Widget body = _safeAreaEnabled
        ? SafeArea(
      child: bodyStack,
    )
        : bodyStack;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SizedBox.expand(
          child: ColoredBox(
            color: bgColor,
            child: body,
          ),
        ),
      ),
    );
  }

  bool _isAdobeRedirect(Uri uri) {
    final String host = uri.host.toLowerCase();
    return host == 'c00.adobe.com';
  }
}

// ---------------------- Экран для c00.adobe.com ----------------------

class AdobeRedirectScreen extends StatelessWidget {
  final Uri uri;

  const AdobeRedirectScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111111),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Go to the App Store and download the app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              SizedBox(height: 24),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(n1diceFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: n1diceHall(), // Hall остаётся, но без визуального loader’а
    ),
  );
}