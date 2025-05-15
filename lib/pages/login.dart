import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../app_state.dart';

class Company {
  final int id;
  final String key;
  final String name;

  Company({required this.id, required this.key, required this.name});

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'],
      key: json['key'],
      name: json['name'],
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 輸入控制器
  final TextEditingController _companyCodeController = TextEditingController();
  Company? _selectedCompany;
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 公司資料列表
  List<Company> _companies = [];
  List<Company> _filteredCompanies = [];

  @override
  void initState() {
    super.initState();
    fetchCompanies().then((_) => _loadSavedCredentials());
    _companyCodeController.addListener(_filterCompanies);
    _checkSavedToken();
  }


  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('companyKey');
    final savedAccount  = prefs.getString('account');
    final savedPassword = prefs.getString('password');

    if (savedKey != null && _companies.isNotEmpty) {
      _companyCodeController.text = savedKey;

      // 這裡 orElse 不再回傳 null，而是回傳 _companies.first
      final match = _companies.firstWhere(
            (c) => c.key == savedKey,
        orElse: () => _companies.first,
      );

      setState(() {
        _selectedCompany = match;
      });
    }

    if (savedAccount != null)  _accountController.text  = savedAccount;
    if (savedPassword != null) _passwordController.text = savedPassword;
  }

  Future<void> _checkSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('token');
    final expireTs = prefs.getInt('expire');
    if (savedToken != null && expireTs != null) {
      final expiration = DateTime.fromMillisecondsSinceEpoch(expireTs);
      if (DateTime.now().isBefore(expiration)) {
        final refreshed = await _refreshToken(savedToken);
        if (refreshed) {
          Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      }
    }
    // 否則留在登入頁面
  }

  Future<bool> _refreshToken(String token) async {
    final url = Uri.parse('http://211.23.157.201/api/user/refreshToken');
    final response = await http.put(url, headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final jsonRes = json.decode(response.body);
      if (jsonRes['status'] == true) {
        final newToken = jsonRes['data']['token'];
        final expMs = jsonRes['data']['expirationDate'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', newToken);
        await prefs.setInt('expire', expMs);

        // 更新 AppState
        context.read<AppState>().setToken(
          newToken,
          DateTime.fromMillisecondsSinceEpoch(expMs),
        );
        return true;
      }
    }
    return false;
  }

  // 呼叫 API 取得公司資料
  Future<void> fetchCompanies() async {
    final url = Uri.parse(
      'http://juahua.com.tw:3005/api/get/login/companies?companyId=1',
    );
    final response = await http.get(url, headers: {
      'Authorization':
      '',
    });
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      if (jsonResponse['status'] == true) {
        final List data = jsonResponse['data'];
        setState(() {
          _companies = data.map((e) => Company.fromJson(e)).toList();
          _filteredCompanies = List.from(_companies);
          if (_filteredCompanies.isNotEmpty) {
            _selectedCompany = _filteredCompanies.first;
            _companyCodeController.text = _selectedCompany!.key;
          }
        });
      }
    } else {
      print("取得公司資料失敗");
    }
  }

  void _filterCompanies() {
    final input = _companyCodeController.text;
    setState(() {
      if (input.isEmpty) {
        _filteredCompanies = List.from(_companies);
      } else {
        _filteredCompanies = _companies
            .where((c) =>
            c.key.toLowerCase().contains(input.toLowerCase()))
            .toList();
      }
      _selectedCompany =
      _filteredCompanies.isNotEmpty ? _filteredCompanies.first : null;
    });
  }

  Future<void> _login() async {
    final body = json.encode({
      "companyKey": _companyCodeController.text,
      "userId": _accountController.text,
      "password": _passwordController.text,
      "captcha": "",
      "companyName": _selectedCompany?.name ?? "",
      "loginAttempts": 0,
      "needAuth": true
    });
    final url =
    Uri.parse('http://211.23.157.201/api/user/authenticate');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonRes = json.decode(response.body);
      if (jsonRes['status'] == true) {
        final data = jsonRes['data'];
        final token = data['token'];
        final expiration =
        DateTime.parse(data['expirationDate']); // ISO8601 格式

        // 存到 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setInt(
          'expire',
          expiration.millisecondsSinceEpoch,
        );

        // 新增：存公司代號、公司名稱、帳號、密碼
        await prefs.setString('companyKey', _companyCodeController.text);
        await prefs.setString('companyName', _selectedCompany?.name ?? '');
        await prefs.setString('account', _accountController.text);
        await prefs.setString('password', _passwordController.text);

        // 更新 AppState
        context.read<AppState>().setUserId(_accountController.text);
        context.read<AppState>().setToken(token, expiration);

        Navigator.pushReplacementNamed(context, '/home');
      } else {
        _showError(jsonRes['message'] ?? '驗證失敗');
      }
    } else {
      _showError('伺服器錯誤：${response.statusCode}');
    }
  }

  void _showError(String msg) {
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
      // 背景圖片
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/login-bg.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/login-header.png',
                      width: 240,
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              '覺華工程道路巡查系統',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white, thickness: 1),
                          const SizedBox(height: 16),
                          // 公司代號 + 下拉
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildLabel('公司'),
                              const SizedBox(width: 8),
                              Flexible(
                                flex: 2,
                                child: _buildTextField(
                                  controller: _companyCodeController,
                                  hint: '代號',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                flex: 5,
                                child: DropdownButtonFormField<Company>(
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor:
                                    Colors.white.withOpacity(0.2),
                                    contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  isExpanded: true,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                  dropdownColor: Colors.black87,
                                  value: _selectedCompany,
                                  items: _filteredCompanies
                                      .map((company) =>
                                      DropdownMenuItem<Company>(
                                        value: company,
                                        child: Text(
                                          company.name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                        ),
                                      ))
                                      .toList(),
                                  onChanged: (c) {
                                    setState(() {
                                      _selectedCompany = c;
                                      _companyCodeController.text =
                                          c?.key ?? '';
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 帳號
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildLabel('帳號'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildTextField(
                                  controller: _accountController,
                                  hint: '請輸入帳號',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 密碼
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildLabel('密碼'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildTextField(
                                  controller: _passwordController,
                                  hint: '請輸入密碼',
                                  obscureText: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF003D79),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: const Text(
                                '登入',
                                style: TextStyle(color: Colors.white),
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
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String label) => Text(
    label,
    style: const TextStyle(color: Colors.white, fontSize: 16),
  );

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
            borderSide: BorderSide.none,
          ),
        ),
      );
}
