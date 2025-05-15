import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black87,
      toolbarHeight: 80,
      centerTitle: false,
      leadingWidth: 120,
      leading: Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: GestureDetector(
          onTap: () {
            // 更新全局狀態 currentPage 並導向 HomePage
            context.read<AppState>().setCurrentPage('home');
            Navigator.pushReplacementNamed(context, '/home');
          },
          child: SizedBox(
            width: 100,
            child: Image.asset(
              'assets/images/login-header.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
      titleSpacing: 10,
      title: Text(
        '工程道路巡查系統',
        style: TextStyle(
          fontSize: 20,
          color: Colors.white,
          fontWeight: FontWeight.bold, // 粗體字
        ),
      ),
      actions: [
        Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu),
            iconSize: 32,
            onPressed: () {
              Scaffold.of(ctx).openEndDrawer();
            },
          ),
        ),
        SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(80);
}
