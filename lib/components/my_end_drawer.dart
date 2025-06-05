import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';

class MyEndDrawer extends StatelessWidget {
  const MyEndDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      // 自訂寬度
      width: 200,
      // Drawer 裡面
      child: Container(
        color: Colors.blueGrey[800], // 整個 Drawer 的背景色
        child: ListView(
          children: [
            // 修改 DrawerHeader：用 SizedBox 包裹縮短高度，並設置 margin 與 padding 為 0，方便調整顏色
            SizedBox(
              height: 40, // 調整高度，可自行更改
              child: DrawerHeader(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                decoration: BoxDecoration(
                  // 修改成你想要的顏色，例如 #000000 代表純黑
                  color: Colors.blueGrey[800], // #000000，可自行修改為預設藍黑色，如 Colors.blueGrey[900]
                ),
                child: Center(
                  child: Text(
                    '選單',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold, // 粗體字
                    ),
                  ),
                ),
              ),
            ),
            // Home
            ListTile(
              leading: Icon(Icons.home, color: Colors.white),
              title: Text('首頁', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context); // 關閉 Drawer
                context.read<AppState>().setCurrentPage('home');
                Navigator.pushReplacementNamed(context, '/home');
              },
            ),
            // 派工模組 (群組)
            Theme(
              // 用 Theme 包住 ExpansionTile，單獨改它的顏色
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent, // 移除展開線
                unselectedWidgetColor: Colors.white, // 未選中狀態的箭頭顏色
                expansionTileTheme: ExpansionTileThemeData(
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  collapsedTextColor: Colors.white,
                  textColor: Colors.white,
                  backgroundColor: Colors.blueGrey[700],
                  collapsedBackgroundColor: Colors.blueGrey[800],
                ),
              ),
              child: ExpansionTile(
                title: Text('派工模組', style: TextStyle(color: Colors.white)),
                leading: Icon(Icons.work, color: Colors.white),
                children: [
                  ListTile(
                    title: Text('巡修列表', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      context.read<AppState>().setCurrentPage('inspectionList');
                      Navigator.pushReplacementNamed(context, '/inspectionList');
                    },
                  ),
                  ListTile(
                    title: Text('派工列表', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      context.read<AppState>().setCurrentPage('dispatchList');
                      Navigator.pushReplacementNamed(context, '/dispatchList');
                    },
                  ),
                  ListTile(
                    title: Text('上傳列表', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      context.read<AppState>().setCurrentPage('uploadList');
                      Navigator.pushReplacementNamed(context, '/uploadList');
                    },
                  ),
                ],
              ),
            ),
            // 個人資訊
            ListTile(
              leading: Icon(Icons.person, color: Colors.white),
              title: Text('個人資訊', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                context.read<AppState>().setCurrentPage('personalInfo');
                Navigator.pushReplacementNamed(context, '/personalInfo');
              },
            ),
          ],
        ),
      ),
    );
  }
}
