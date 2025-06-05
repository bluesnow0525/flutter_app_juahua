import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../components/config.dart';

class Company {
  final int id;
  final String key;
  final String name;
  Company({required this.id, required this.key, required this.name});
  factory Company.fromJson(Map<String, dynamic> j) => Company(
    id: j['id'],
    key: j['key'],
    name: j['name'],
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _companyCodeController = TextEditingController();
  Company? _selectedCompany;
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();

  List<Company> _companies = [];
  List<Company> _filtered = [];

  @override
  void initState() {
    super.initState();
    // 1) 先拉公司列表，再載入本機存的憑證
    fetchCompanies().then((_) => _loadSavedCredentials());
    _companyCodeController.addListener(_filterCompanies);
    // 2) 延後一幀再檢查 token 是否有效
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSavedToken());
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = prefs.getString('companyKey');
    final acc   = prefs.getString('account');
    final pwd   = prefs.getString('password');

    if (key != null && _companies.isNotEmpty) {
      _companyCodeController.text = key;
      _selectedCompany = _companies.firstWhere(
            (c) => c.key == key,
        orElse: () => _companies.first,
      );
      setState(() {}); // 更新 dropdown
    }
    if (acc != null) _accountController.text = acc;
    if (pwd != null) _passwordController.text = pwd;
  }

  Future<void> _checkSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final expMs  = prefs.getInt('expire');
    if (token != null && expMs != null) {
      final exp = DateTime.fromMillisecondsSinceEpoch(expMs);
      if (DateTime.now().isBefore(exp)) {
        final ok = await _refreshToken(token);
        if (ok && mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    }
  }

  Future<bool> _refreshToken(String oldToken) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/user/refreshToken');
    final resp = await http.put(
      url,
      headers: {'Authorization': 'Bearer $oldToken'},
    );
    if (resp.statusCode == 200) {
      final js = json.decode(resp.body) as Map<String, dynamic>;
      if (js['status'] == true) {
        final data = js['data'];
        final newToken = data['token'] as String;
        final expMs    = data['expirationDate'] as int;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', newToken);
        await prefs.setInt('expire', expMs);
        final savedAccount = prefs.getString('account') ?? '';
        context.read<AppState>().setUserId(savedAccount);
        context.read<AppState>().setToken(
          newToken,
          DateTime.fromMillisecondsSinceEpoch(expMs),
        );
        return true;
      }
    }
    return false;
  }

  Future<void> fetchCompanies() async {
    final url = Uri.parse(
      'http://juahua.com.tw:3005/api/get/login/companies?companyId=1',
    );
    final resp = await http.get(url);
    if (resp.statusCode == 200) {
      final js = json.decode(resp.body) as Map<String, dynamic>;
      if (js['status'] == true) {
        final data = (js['data'] as List).cast<Map<String, dynamic>>();
        _companies = data.map((j) => Company.fromJson(j)).toList();
        _filtered  = List.from(_companies);
        if (_filtered.isNotEmpty) {
          _selectedCompany = _filtered.first;
          _companyCodeController.text = _selectedCompany!.key;
        }
        setState(() {});
      }
    }
  }

  void _filterCompanies() {
    final input = _companyCodeController.text;
    _filtered = input.isEmpty
        ? List.from(_companies)
        : _companies
        .where((c) => c.key.toLowerCase().contains(input.toLowerCase()))
        .toList();
    if (_filtered.isNotEmpty) _selectedCompany = _filtered.first;
    setState(() {});
  }

  Future<void> _login() async {
    final body = json.encode({
      "companyKey":   _companyCodeController.text,
      "userId":       _accountController.text,
      "password":     _passwordController.text,
      "captcha":      "",
      "companyName":  _selectedCompany?.name ?? "",
      "loginAttempts":0,
      "needAuth":     true,
    });
    final url = Uri.parse('${ApiConfig.baseUrl}/api/user/authenticate');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode == 200) {
      final js = json.decode(resp.body) as Map<String, dynamic>;
      if (js['status'] == true) {
        final d  = js['data'];
        final t  = d['token'] as String;
        final exp= DateTime.parse(d['expirationDate'] as String);
        final prefs = await SharedPreferences.getInstance();
        // 存 token
        await prefs.setString('token', t);
        await prefs.setInt('expire', exp.millisecondsSinceEpoch);
        // 存公司 + 帳號密碼
        await prefs.setString('companyKey',  _companyCodeController.text);
        await prefs.setString('companyName', _selectedCompany?.name ?? '');
        await prefs.setString('account',     _accountController.text);
        await prefs.setString('password',    _passwordController.text);

        // 更新 AppState
        context.read<AppState>().setUserId(_accountController.text);
        context.read<AppState>().setToken(t, exp);

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
        return;
      } else {
        _showError(js['message'] ?? '登入失敗');
      }
    } else {
      _showError('伺服器錯誤：${resp.statusCode}');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('登入失敗'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _companyCodeController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: Image.asset('assets/images/login-bg.png', fit: BoxFit.cover),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/images/login-header.png',
                    width: 240, height: 100),
                const SizedBox(height: 20),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(children: [
                    const Text(
                      '覺華工程道路巡查系統',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const Divider(color: Colors.white),
                    const SizedBox(height: 16),
                    Row(children: [
                      _buildLabel('公司'),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: _buildTextField(
                            controller: _companyCodeController,
                            hint: '代號'),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 5,
                        child: DropdownButtonFormField<Company>(
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.2),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          dropdownColor: Colors.black87,
                          style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                          value: _selectedCompany,
                          items: _filtered
                              .map((c) => DropdownMenuItem<Company>(
                            value: c,
                            child: Text(c.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12)),
                          ))
                              .toList(),
                          onChanged: (c) {
                            setState(() {
                              _selectedCompany = c;
                              _companyCodeController.text = c?.key ?? '';
                            });
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      _buildLabel('帳號'),
                      const SizedBox(width: 8),
                      Expanded(
                          child:
                          _buildTextField(controller: _accountController, hint: '請輸入帳號')),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      _buildLabel('密碼'),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildTextField(
                              controller: _passwordController,
                              hint: '請輸入密碼',
                              obscureText: true)),
                    ]),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF003D79),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text('登入',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 30),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildLabel(String label) => Text(label,
      style: const TextStyle(color: Colors.white, fontSize: 16));
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.2),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      );
}
