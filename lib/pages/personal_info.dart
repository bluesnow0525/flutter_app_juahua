import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({Key? key}) : super(key: key);

  @override
  _PersonalInfoPageState createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  final TextEditingController _companyController  = TextEditingController();
  final TextEditingController _accountController  = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadSavedInfo();
  }

  Future<void> _loadSavedInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _companyController.text  = prefs.getString('companyName') ?? '';
      _accountController.text  = prefs.getString('account')     ?? '';
      _passwordController.text = prefs.getString('password')    ?? '';
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('expire');
    await prefs.remove('companyKey');
    await prefs.remove('companyName');
    await prefs.remove('account');
    await prefs.remove('password');

    context.read<AppState>().setToken('', DateTime.now());
    context.read<AppState>().setUserId('');
    context.read<AppState>().setCurrentPage('login');

    Navigator.pushReplacementNamed(context, '/');
  }

  Widget _buildField(String label, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2F5597),  // label:#2F5597
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppHeader(),
      endDrawer: const MyEndDrawer(),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_outline,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 8),
              const Text(
                '一般人員',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF30475E),  // 一般人員字體:#30475E
                ),
              ),
              const SizedBox(height: 24),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    // 公司單位
                    _buildField(
                      '公司單位',
                      TextField(
                        controller: _companyController,
                        readOnly: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFDAE3F3),  // 欄位唯讀背景:#DAE3F3
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),

                    // 使用者帳號
                    _buildField(
                      '使用者帳號',
                      TextField(
                        controller: _accountController,
                        readOnly: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFDAE3F3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),

                    // 使用者密碼
                    _buildField(
                      '使用者密碼',
                      TextField(
                        controller: _passwordController,
                        readOnly: true,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFDAE3F3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscure = !_obscure;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 登出按鈕
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF30475E),  // 按鈕背景:#30475E
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          '登出',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,  // 字體白
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
