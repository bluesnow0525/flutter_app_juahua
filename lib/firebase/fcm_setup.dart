import 'package:firebase_messaging/firebase_messaging.dart';

Future<String?> setupFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // 請求通知權限（僅 Android 13+ / iOS）
  NotificationSettings settings = await messaging.requestPermission();

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('✅ 已授權通知');
  } else {
    print('❌ 未授權通知');
  }

  // 取得 FCM token（提供給後端發通知）
  String? token = await messaging.getToken();
  print('🔑 FCM Token: $token');

  // 監聽前景通知
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('📩 收到通知: ${message.notification?.title}');
    print('📄 內容: ${message.notification?.body}');
  });

  // 背景點擊通知處理（從背景點擊通知進入 app）
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📲 使用者點擊通知，打開 app: ${message.notification?.title}');
  });

  return token;
}