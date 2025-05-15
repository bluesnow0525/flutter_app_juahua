import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';

/// 標案模型
class Tender {
  final int id;
  final String name;
  final List<String> districts;

  Tender({
    required this.id,
    required this.name,
    required this.districts,
  });

  factory Tender.fromJson(Map<String, dynamic> j) => Tender(
    id: j['id'] as int,
    name: j['prjName'] as String,
    districts: (j['districts'] as List).cast<String>(),
  );
}

/// 派工單模型（包含所有回傳欄位）
class DispatchItem {
  final int id;
  final String type;
  final String caseNum;
  final String prjId;
  final DateTime dispatchDate;
  final DateTime dueDate;
  final String district;
  final String village;
  final String address;
  final DateTime workStartDate;
  final DateTime workEndDate;
  final String material;
  final double materialSize;
  final double workLength;
  final double workWidth;
  final double workDepthMilling;
  final double workDepthPaving;
  final String remark;
  final double startLng;
  final double startLat;
  final double endLng;
  final double endLat;
  final bool? sampleTaken;
  final DateTime? sampleDate;
  final String? testItem;
  final List<Map<String, dynamic>> images;

  DispatchItem({
    required this.id,
    required this.type,
    required this.caseNum,
    required this.prjId,
    required this.dispatchDate,
    required this.dueDate,
    required this.district,
    required this.village,
    required this.address,
    required this.workStartDate,
    required this.workEndDate,
    required this.material,
    required this.materialSize,
    required this.workLength,
    required this.workWidth,
    required this.workDepthMilling,
    required this.workDepthPaving,
    required this.remark,
    required this.startLng,
    required this.startLat,
    required this.endLng,
    required this.endLat,
    required this.sampleTaken,
    required this.sampleDate,
    required this.testItem,
    required this.images,
  });

  factory DispatchItem.fromJson(Map<String, dynamic> j) {
    DateTime? parseNullableDate(String? s) =>
        s == null ? null : DateTime.parse(s);
    return DispatchItem(
      id: j['id'] as int,
      type: j['type'] as String,
      caseNum: j['case_num'] as String,
      prjId: j['prj_id'] as String,
      dispatchDate: DateTime.parse(j['dispatch_date'] as String),
      dueDate: DateTime.parse(j['due_date'] as String),
      district: j['district'] as String,
      village: j['cavlge'] as String,
      address: j['address'] as String,
      workStartDate: DateTime.parse(j['work_start_date'] as String),
      workEndDate: DateTime.parse(j['work_end_date'] as String),
      material: j['material'] as String,
      materialSize: (j['material_size'] as num).toDouble(),
      workLength: (j['work_length'] as num).toDouble(),
      workWidth: (j['work_width'] as num).toDouble(),
      workDepthMilling: (j['work_depth_milling'] as num).toDouble(),
      workDepthPaving: (j['work_depth_paving'] as num).toDouble(),
      remark: j['remark'] as String,
      startLng: (j['start_lng'] as num).toDouble(),
      startLat: (j['start_lat'] as num).toDouble(),
      endLng: (j['end_lng'] as num).toDouble(),
      endLat: (j['end_lat'] as num).toDouble(),
      sampleTaken: j['sample_taken'] as bool?,
      sampleDate: parseNullableDate(j['sample_date'] as String?),
      testItem: j['test_item'] as String?,
      images: (j['images'] as List).cast<Map<String, dynamic>>(),
    );
  }

  /// 用於 DataTable 顯示的「狀態」
  String get status => sampleTaken == true ? '已回報' : '待施工';

  /// 取回第一張圖的完整 URL（table 中只顯示第一張）
  String get firstImageUrl {
    // 找到第一個 path 不是 .zip 的 entry
    final jpg = images.firstWhere(
          (m) {
        final path = (m['img_path'] as String).toLowerCase();
        return !path.endsWith('.zip');
      },
      orElse: () => {},
    );

    final path = jpg.isNotEmpty
        ? jpg['img_path'] as String
        : '';
    return path.isEmpty
        ? ''
        : 'http://211.23.157.201/$path';
  }
}

class DispatchListPage extends StatefulWidget {
  const DispatchListPage({Key? key}) : super(key: key);

  @override
  _DispatchListPageState createState() => _DispatchListPageState();
}

class _DispatchListPageState extends State<DispatchListPage> {
  // 派工日期起訖
  DateTime _dispatchStart = DateTime.now();
  DateTime _dispatchEnd = DateTime.now();

  // 篩選條件
  List<int> _selectedProjectIds = [];
  List<String> _selectedFormTypes = [];
  List<String> _selectedDistricts = [];
  List<String> _selectedVillages = [];
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _caseNumController = TextEditingController();

  bool _showFilters = false;
  bool _loading = false;

  // 資料
  List<Tender> _tenders = [];
  Map<String, List<String>> _villagesMap = {};
  List<DispatchItem> _results = [];

  // UI 控制
  int _activeFilter = 0;
  late final ScrollController _districtScrollController;
  late final ScrollController _villageScrollController;

  final List<String> _formTypes = ['刨除加封', '路基改善'];

  @override
  void initState() {
    super.initState();
    _districtScrollController = ScrollController();
    _villageScrollController = ScrollController();
    _fetchTenders();
    _fetchVillages();
    _fetchDispatches();
  }

  @override
  void dispose() {
    _districtScrollController.dispose();
    _villageScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTenders() async {
    final token = context.read<AppState>().token;
    final uri = Uri.parse('http://211.23.157.201/api/get/tender');
    final resp = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
    });
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['status'] == true && body['data'] is List) {
        setState(() {
          _tenders = (body['data'] as List)
              .map((j) => Tender.fromJson(j as Map<String, dynamic>))
              .toList();
        });
      }
    }
  }

  Future<void> _fetchVillages() async {
    final token = context.read<AppState>().token;
    final resp = await http.get(
      Uri.parse('http://211.23.157.201/api/get/geo/area'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['status'] == true && body['data'] is List) {
        final Map<String, List<String>> map = {};
        for (var county in body['data'] as List) {
          for (var d in county['districts'] as List) {
            final name = d['district_name'] as String;
            map[name] = (d['cavlges'] as List).cast<String>();
          }
        }
        setState(() => _villagesMap = map);
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _dispatchStart : _dispatchEnd;
    final dt = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (dt != null) {
      setState(() {
        if (isStart)
          _dispatchStart = dt;
        else
          _dispatchEnd = dt;
      });
    }
  }

  /// 把 list 裡的每個元素，都用 key=value 的方式 append 到 qs，
  /// 如果 list.length == 1，就再多加一個 key= 空值，強制讓後端視為陣列
  void _addArrayParam<T>(List<T> list, String key, List<String> qs) {
    if (list.isEmpty) return;
    for (var v in list) {
      qs.add('$key=${Uri.encodeComponent(v.toString())}');
    }
    if (list.length == 1) {
      qs.add('$key=');
    }
  }

  Future<void> _fetchDispatches() async {
    setState(() {
      _loading = true;
      _results.clear();
    });

    final qs = <String>[];
    // 派工日期起訖
    qs.add('startDate=${Uri.encodeComponent(DateFormat('yyyy-MM-dd').format(_dispatchStart))}');
    qs.add('endDate=${Uri.encodeComponent(DateFormat('yyyy-MM-dd').format(_dispatchEnd))}');
    // 多值參數
    _addArrayParam(_selectedFormTypes, 'formTypes', qs);
    _addArrayParam(_selectedProjectIds, 'projectIds', qs);
    _addArrayParam(_selectedDistricts, 'districts', qs);
    _addArrayParam(_selectedVillages, 'cavlges', qs);
    // 單值參數
    if (_addressController.text.trim().isNotEmpty) {
      qs.add('address=${Uri.encodeComponent(_addressController.text.trim())}');
    }
    if (_caseNumController.text.trim().isNotEmpty) {
      qs.add('caseNumber=${Uri.encodeComponent(_caseNumController.text.trim())}');
    }

    final url = 'http://211.23.157.201/api/get/workorder/repairDispatch?${qs.join('&')}';
    print('🔍 Dispatch Request URL: $url');

    try {
      final token = context.read<AppState>().token;
      final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});

      // 印出回應 debug 資料
      print('🔍 Dispatch Response status: ${resp.statusCode}');
      print('🔍 Dispatch Response body: ${resp.body}');

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['status'] == true && body['data'] is List) {
          setState(() {
            _results = (body['data'] as List)
                .map((j) => DispatchItem.fromJson(j as Map<String, dynamic>))
                .toList();
          });
        } else {
          final msg = body['message'] ?? '未知錯誤';
          print('❌ Dispatch 查詢失敗: $msg');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('查詢失敗：$msg')),
          );
        }
      } else {
        print('❌ Dispatch HTTP 錯誤 ${resp.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('HTTP ${resp.statusCode} 錯誤')),
        );
      }
    } catch (e, stack) {
      print('🔥 Exception in _fetchDispatches: $e');
      print(stack);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('查詢例外：$e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableDistricts = (_selectedProjectIds.isEmpty
        ? _tenders
        : _tenders.where((t) => _selectedProjectIds.contains(t.id)))
        .expand((t) => t.districts)
        .toSet();

    final availableVillages = (_selectedDistricts.isEmpty
        ? _villagesMap.values.expand((v) => v)
        : _selectedDistricts.expand((d) => _villagesMap[d] ?? []))
        .toSet();

    return Scaffold(
      appBar: AppHeader(),
      endDrawer: MyEndDrawer(),
      body: Stack(
          children: [
      // 底層：按鈕列 + 資料表
      Column(
      children: [
      // 按鈕列
      Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Column(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0070C0),
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    Navigator.pushNamed(context, '/dispatchCutForm'),
                child: const Text('刨除加封'),
              ),
              const SizedBox(height: 2),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0070C0),
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    Navigator.pushNamed(context, '/dispatchBaseForm'),
                child: const Text('路基改善'),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '派工單列表',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF30475E),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF30475E),
              foregroundColor: Colors.white,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            child: Row(
              children: [
                const Text('查詢欄'),
                Icon(_showFilters
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down),
              ],
            ),
          ),
        ],
      ),
    ),

    // 資料列表
    Expanded(
    child: _results.isEmpty
    ? Center(child: Text(_loading ? '查詢中…' : '尚無資料，請按「查詢」'))
        : SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.all(12),
    child: DataTable(
    columns: const [
    DataColumn(label: Text('狀態')),
    DataColumn(label: Text('表單類型')),
    DataColumn(label: Text('案件編號')),
    DataColumn(label: Text('行政區')),
    DataColumn(label: Text('里別')),
    DataColumn(label: Text('派工日期')),
    DataColumn(label: Text('施工日期')),
    DataColumn(label: Text('指派人員')),
    DataColumn(label: Text('施工路段')),
    DataColumn(label: Text('照片')),
    ],
    rows: _results.map((item) {
    final formRoute = item.type == '刨除加封'
    ? '/dispatchCutForm'
        : '/dispatchBaseForm';
    return DataRow(
    onSelectChanged: (selected) {
    if (selected == true) {
    Navigator.pushNamed(context, formRoute, arguments: item);
    }
    },
    cells: [
    DataCell(Text(item.status)),
    DataCell(Text(item.type)),
    DataCell(Text(item.caseNum)),
    DataCell(Text(item.district)),
    DataCell(Text(item.village)),
    DataCell(Text(DateFormat('yyyy-MM-dd').format(item.dispatchDate))),
    DataCell(Text(
    '${DateFormat('yyyy-MM-dd').format(item.workStartDate)} ~ '
    '${DateFormat('yyyy-MM-dd').format(item.workEndDate)}')),
    DataCell(Text(item.prjId)),
    DataCell(Text(item.address)),
    DataCell(
    item.firstImageUrl.isNotEmpty
    ? Image.network(
    item.firstImageUrl,
    width: 50,
    height: 50,
    fit: BoxFit.cover,
    )
        : const SizedBox.shrink(),
    ),
    ],
    );
    }).toList(),
    ),
    ),
    ),
    ],
    ),

    // 半透遮罩，點擊收起查詢
    if (_showFilters)
    Positioned.fill(
    child: GestureDetector(
    onTap: () => setState(() => _showFilters = false),
    child: Container(color: Colors.black54),
    ),
    ),

    // 浮層查詢面板
    if (_showFilters)
    Positioned(
    top: kToolbarHeight + 60,
    left: 16,
    right: 16,
    child: Material(
    elevation: 8,
    borderRadius: BorderRadius.circular(8),
    child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    ),
    child: ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 600),
    child: SingleChildScrollView(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // 第1排：派工起訖日期
    Row(
    children: [
    _buildDateField(
    '派工開始日期', _dispatchStart, () => _pickDate(isStart: true)),
    const SizedBox(width: 12),
    _buildDateField(
    '派工結束日期', _dispatchEnd, () => _pickDate(isStart: false)),
    ],
    ),
    const SizedBox(height: 8),

    // 第2排：標案 & 表單類型
    Row(
    children: [
    SizedBox(
    width: 200,
    child: ExpansionTile(
    tilePadding:
    const EdgeInsets.symmetric(horizontal: 2),
    childrenPadding:
    const EdgeInsets.symmetric(horizontal: 2),
    title: Text(
    '標案：${_selectedProjectIds.isEmpty ? '' : _selectedProjectIds.map((i) => _tenders.firstWhere((t) => t.id == i).name).join('、')}',
    style: const TextStyle(fontSize: 14),
    ),
    initiallyExpanded: _activeFilter == 2,
    onExpansionChanged: (open) =>
    setState(() => _activeFilter = open ? 2 : 0),
    children: [
    ConstrainedBox(
    constraints:
    const BoxConstraints(maxHeight: 230),
    child: Scrollbar(
    child: ListView(
    padding: EdgeInsets.zero,
    children: _tenders.map((t) {
    final checked =
    _selectedProjectIds.contains(t.id);
    return CheckboxListTile(
    contentPadding: const EdgeInsets
        .symmetric(vertical: 2, horizontal: 4),
    title: Text(t.name,
    style:
    const TextStyle(fontSize: 16)),
    value: checked,
    onChanged: (v) {
    setState(() {
    if (v == true)
    _selectedProjectIds.add(t.id);
    else
    _selectedProjectIds.remove(t.id);
    });
    },
    );
    }).toList(),
    ),
    ),
    ),
    ],
    ),
    ),
    const SizedBox(width: 12),
    SizedBox(
    width: 120,
    child: ExpansionTile(
    tilePadding:
    const EdgeInsets.symmetric(horizontal: 2),
    childrenPadding:
    const EdgeInsets.symmetric(horizontal: 2),
    title: Text(
    '表單：${_selectedFormTypes.join('、')}',
    style: const TextStyle(fontSize: 14),
    ),
    initiallyExpanded: _activeFilter == 3,
    onExpansionChanged: (open) =>
    setState(() => _activeFilter = open ? 3 : 0),
    children: [
    ConstrainedBox(
    constraints:
    const BoxConstraints(maxHeight: 130),
    child: Scrollbar(
    child: ListView(
    padding: EdgeInsets.zero,
    children: _formTypes.map((t) {
    final checked =
    _selectedFormTypes.contains(t);
    return CheckboxListTile(
    contentPadding:
    const EdgeInsets.symmetric(
    vertical: 4, horizontal: 4),
    title: Text(t,
    style:
    const TextStyle(fontSize: 14)),
    value: checked,
    onChanged: (v) {
    setState(() {
    if (v == true)
    _selectedFormTypes.add(t);
    else
    _selectedFormTypes.remove(t);
    });
    },
    );
    }).toList(),
    ),
    ),
    ),
    ],
    ),
    ),
    ],
    ),
    const SizedBox(height: 8),

    // 第3排：行政區 & 里別
    Row(
    children: [
    SizedBox(
    width: 160,
    child: ExpansionTile(
    title: Text(
    '行政區：${_selectedDistricts.join('、')}',
    style: const TextStyle(fontSize: 14),
    ),
    initiallyExpanded: _activeFilter == 1,
    onExpansionChanged: (open) =>
    setState(() => _activeFilter = open ? 1 : 0),
    children: [
    ConstrainedBox(
    constraints:
    const BoxConstraints(maxHeight: 180),
    child: Scrollbar(
    controller: _districtScrollController,
    thumbVisibility: true,
    thickness: 4,
    radius: const Radius.circular(2),
    child: ListView(
    controller: _districtScrollController,
    padding: EdgeInsets.zero,
    children: availableDistricts.map((d) {
    final checked =
    _selectedDistricts.contains(d);
    return CheckboxListTile(
    contentPadding:
    const EdgeInsets.symmetric(
    vertical: 2, horizontal: 4),
    title: Text(d,
    style:
    const TextStyle(fontSize: 16)),
    value: checked,
    onChanged: (v) {
    setState(() {
    if (v == true)
    _selectedDistricts.add(d);
    else
    _selectedDistricts.remove(d);
    _selectedVillages = _selectedVillages
        .where((v) => availableVillages.contains(v))
        .toList();
    });
    },
    );
    }).toList(),
    ),
    ),
    ),
    ],
    ),
    ),
    const SizedBox(width: 8),
    SizedBox(
    width: 160,
    child: ExpansionTile(
    title: Text(
    '里別：${_selectedVillages.join('、')}',
    style: const TextStyle(fontSize: 14),
    ),
    initiallyExpanded: _activeFilter == 5,
    onExpansionChanged: (open) =>
    setState(() => _activeFilter = open ? 5 : 0),
    children: [
    ConstrainedBox(
    constraints:
    const BoxConstraints(maxHeight: 250),
    child: Scrollbar(
    controller: _villageScrollController,
    thumbVisibility: true,
    thickness: 4,
    radius: const Radius.circular(2),
    child: ListView(
    controller: _villageScrollController,
    padding: EdgeInsets.zero,
    children: availableVillages.map((v) {
    final checked =
    _selectedVillages.contains(v);
    return CheckboxListTile(
    contentPadding:
    const EdgeInsets.symmetric(
    vertical: 1, horizontal: 4),
    title: Text(v,
    style:
    const TextStyle(fontSize: 14)),
    value: checked,
    onChanged: (val) {
    setState(() {
    if (val == true)
    _selectedVillages.add(v);
    else
    _selectedVillages.remove(v);
    });
    },
    );
    }).toList(),
    ),
    ),
    ),
    ],
    ),
    ),
    ],
    ),
    const SizedBox(height: 8),

    // 第4排：施工路名 & 案件編號
    Row(
    children: [
    SizedBox(
    width: 160,
    child: TextField(
    controller: _addressController,
    decoration: const InputDecoration(
    labelText: '施工路名',
    ),
    ),
    ),
    const SizedBox(width: 12),
    SizedBox(
    width: 150,
    child: TextField(
    controller: _caseNumController,
    decoration: const InputDecoration(
    labelText: '案件編號'),
    ),
    ),
    ],
    ),
    const SizedBox(height: 12),

    // 查詢按鈕
    Center(
    child: SizedBox(
    width: 100,
    child: ElevatedButton(
    style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF30475E),
    foregroundColor: Colors.white,
    ),
    onPressed: _loading
    ? null
        : () async {
    await _fetchDispatches();
    setState(() => _showFilters = false);
    },
    child: Text(_loading ? '查詢中…' : '查詢'),
    ),
    ),
    ),
    ],
    ),
    ),
    ),
    ),
    ),
    ),
    ],
    ),
    );
  }


  Widget _buildDateField(
      String label, DateTime date, VoidCallback onTap) {
    return SizedBox(
      width: 140,
      child: TextFormField(
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today),
          isDense: true,
        ),
        controller: TextEditingController(
            text: DateFormat('yyyy-MM-dd').format(date)),
        onTap: onTap,
      ),
    );
  }
}
