import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_state.dart';
import 'pages/login.dart';
import 'pages/home.dart';
import 'pages/inspection_list.dart';
import 'pages/dispatch_list.dart';
import 'pages/upload_list.dart';
import 'pages/personal_info.dart';
import 'pages/inspection_form.dart';
import 'pages/dispatch_form_cut.dart';
import 'pages/dispatch_form_base.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive，仅打开上傳佇列 box
  await Hive.initFlutter();
  await Hive.openBox('uploadBox');

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..loadUploadsFromDisk(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '道路案件 App',
      theme: ThemeData(primarySwatch: Colors.blue),
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [
        Locale('zh', 'TW'),
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: '/',
      routes: {
        '/': (_) => const LoginPage(),
        '/home': (_) => const HomePage(),
        '/inspectionList': (_) => const InspectionListPage(),
        '/dispatchList': (_) => const DispatchListPage(),
        '/uploadList': (_) => const UploadListPage(),
        '/personalInfo': (_) => const PersonalInfoPage(),
        '/inspectionForm': (_) => const InspectionFormPage(),
        '/dispatchCutForm': (_) => const DispatchCutFormPage(),
        '/dispatchBaseForm': (_) => const DispatchBaseFormPage(),
      },
    );
  }
}
