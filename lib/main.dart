import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 引入我們的全局狀態
import 'app_state.dart';
// 引入各個 page
import 'pages/login.dart';
import 'pages/home.dart';
import 'pages/inspection_list.dart';
import 'pages/dispatch_list.dart';
import 'pages/upload_list.dart';
import 'pages/personal_info.dart';

import 'pages/inspection_form.dart';
import 'pages/dispatch_form_cut.dart';
import 'pages/dispatch_form_base.dart';

void main() {
  runApp(
    /// 用 ChangeNotifierProvider 來提供全局狀態給整個應用
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '道路案件 App',
      theme: ThemeData(primarySwatch: Colors.blue),
      // 初始路由：登入頁
      initialRoute: '/',
      routes: {
        '/': (context) => LoginPage(),
        '/home': (context) => HomePage(),
        '/inspectionList': (context) => InspectionListPage(),
        '/dispatchList': (context) => DispatchListPage(),
        '/uploadList': (context) => UploadListPage(),
        '/personalInfo': (context) => PersonalInfoPage(),
        '/inspectionForm': (context) => InspectionFormPage(),
        '/dispatchCutForm': (context) => DispatchCutFormPage(),
        '/dispatchBaseForm': (context) => DispatchBaseFormPage(),
      },
    );
  }
}
