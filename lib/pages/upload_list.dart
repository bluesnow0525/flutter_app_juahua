import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';

class UploadListPage extends StatelessWidget {
  const UploadListPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentPage = context.watch<AppState>().currentPage;

    return Scaffold(
      appBar: AppHeader(),
      endDrawer: MyEndDrawer(),
      body: Center(
        child: Text(
          '這是 上傳列表\n(目前頁面狀態：$currentPage)',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
