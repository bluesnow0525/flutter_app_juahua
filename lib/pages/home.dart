import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';
import './dispatch_list.dart';   // DispatchItem 模型定義
import './inspection_list.dart'; // InspectionItem & 列表頁
import '../components/config.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<InspectionItem> _todayInspections = [];
  List<DispatchItem> _todayDispatches = [];

  // 新增：用來儲存被勾選的 DispatchItem ID
  final Set<int> _selectedDispatchIds = {};

  @override
  void initState() {
    super.initState();
    _fetchTodayInspections();
    _fetchTodayDispatches();
  }

  Future<void> _fetchTodayInspections() async {
    final token = context.read<AppState>().token;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final url =
        '${ApiConfig.baseUrl}/api/get/workorder/maintenance'
        '?startDate=$today&endDate=$today';
    final resp = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['status'] == true && body['data'] is List) {
        final all = (body['data'] as List)
            .map((j) => InspectionItem.fromJson(j))
            .toList();
        setState(() {
          _todayInspections = all.length > 10 ? all.sublist(0, 10) : all;
        });
      }
    }
  }

  Future<void> _fetchTodayDispatches() async {
    final token = context.read<AppState>().token;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final url =
        '${ApiConfig.baseUrl}/api/get/workorder/repairDispatch'
        '?startDate=$today&endDate=$today';
    final resp = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['status'] == true && body['data'] is List) {
        setState(() {
          _todayDispatches = (body['data'] as List)
              .map((j) => DispatchItem.fromJson(j))
              .toList();
          // 如果一開始要預設清空選取，可在這裡確保 _selectedDispatchIds 清空
          _selectedDispatchIds.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = context.watch<AppState>().currentPage;

    return Scaffold(
      appBar: AppHeader(),
      endDrawer: MyEndDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          children: [
            // 上方標題
            const Center(
              child: Text(
                '新增表單',
                style: TextStyle(
                  color: Color(0xFF2F5597),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 三個表單按鈕
            Row(
              children: [
                Expanded(
                  child: _buildFormButton(
                    label: '巡修單',
                    onPressed: () =>
                        Navigator.pushNamed(context, '/inspectionForm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFormButton(
                    label: '派工單\n刨除加封',
                    onPressed: () =>
                        Navigator.pushNamed(context, '/dispatchCutForm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFormButton(
                    label: '派工單\n路基改善',
                    onPressed: () =>
                        Navigator.pushNamed(context, '/dispatchBaseForm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 今日派工回報清單
            Align(
              alignment: Alignment.center,
              child: Text(
                '今日派工回報清單',
                style: const TextStyle(
                  color: Color(0xFF30475E),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildDispatchTable(), // 在這裡呼叫更新後的 Dispatch Table

            const SizedBox(height: 24),

            // 今日完成巡修單
            Align(
              alignment: Alignment.center,
              child: const Text(
                '今日完成巡修單',
                style: TextStyle(
                  color: Color(0xFF30475E),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '今日共 ${_todayInspections.length} 筆',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/inspectionList');
                    },
                    child: const Text('更多≫'),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 36,
                columns: const [
                  DataColumn(label: Text('項目')),
                  DataColumn(label: Text('案件編號')),
                  DataColumn(label: Text('破壞項目')),
                  DataColumn(label: Text('里別')),
                  DataColumn(label: Text('地址')),
                ],
                rows: _todayInspections.map((item) {
                  final color = item.formType == '巡查單'
                      ? const Color(0xFF0070C0)
                      : const Color(0xFFFFA500);
                  return DataRow(cells: [
                    DataCell(Text(
                      item.formType,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold),
                    )),
                    DataCell(Text(item.caseNum)),
                    DataCell(Text(item.damageType)),
                    DataCell(Text(item.village)),
                    DataCell(Text(item.address)),
                  ]);
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),
            Text(
              '(目前頁面狀態：$currentPage)',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2F5597),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        minimumSize: const Size(0, 60),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 更新：Dispatch Table，新增「勾選」欄位以及「回報」按鈕
  Widget _buildDispatchTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 今日共 X 筆 + 「回報」按鈕
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Text(
                '今日共 ${_todayDispatches.length} 筆',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // 「更多≫」導向 Dispatch List
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/dispatchList'),
                child: const Text('更多≫'),
              ),
            ],
          ),
        ),
        // 在「今日共 X 筆」下方，新增「回報」按鈕
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 2),
          child: ElevatedButton(
            onPressed: () {
              // 點擊時跳出 AlertDialog，顯示被勾選的 ID 列表
              final selectedIdsString =
              _selectedDispatchIds.isEmpty ? '（未選擇任何項目）' : _selectedDispatchIds.join(', ');
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('回報確認'),
                  content: Text('已選擇的 Dispatch ID：\n$selectedIdsString'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('關閉'),
                    ),
                  ],
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F5597),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            ),
            child: const Text(
              '回報',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        // DataTable（含「勾選」欄位）
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 36,
            columns: [
              // 新增「勾選」欄位
              const DataColumn(label: Text('勾選')),
              const DataColumn(label: Text('狀態')),
              const DataColumn(label: Text('派工單類型')),
              const DataColumn(label: Text('案件編號')),
              const DataColumn(label: Text('行政區')),
              const DataColumn(label: Text('里別')),
            ],
            rows: _todayDispatches.map((item) {
              Color statusColor;
              switch (item.status) {
                case '已回報':
                  statusColor = Colors.green;
                  break;
                case '已編輯':
                  statusColor = Colors.orange;
                  break;
                default:
                  statusColor = Colors.red;
              }
              final checked = _selectedDispatchIds.contains(item.id);
              return DataRow(cells: [
                // 第一欄：Checkbox
                DataCell(
                  Checkbox(
                    value: checked,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedDispatchIds.add(item.id);
                        } else {
                          _selectedDispatchIds.remove(item.id);
                        }
                      });
                    },
                  ),
                ),
                DataCell(Text(item.status,
                    style: TextStyle(color: statusColor))),
                DataCell(Text(item.type)),
                DataCell(Text(item.caseNum)),
                DataCell(Text(item.district)),
                DataCell(Text(item.village)),
              ]);
            }).toList(),
          ),
        ),
      ],
    );
  }
}
