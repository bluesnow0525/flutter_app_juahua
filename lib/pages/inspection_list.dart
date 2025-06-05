import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';
import '../components/config.dart';

/// 標案模型
class Tender {
  final int id;
  final String name;
  final List<String> districts;

  Tender({required this.id, required this.name, required this.districts});

  factory Tender.fromJson(Map<String, dynamic> j) => Tender(
    id: j['id'] as int,
    name: j['prjName'] as String,
    districts: (j['districts'] as List).cast<String>(),
  );
}

/// 巡修單項目模型
class InspectionItem {
  final int    id;
  final String caseNum;
  final String formType;
  final DateTime recordDate;
  final String person;
  final String district;
  final String village;
  final String address;
  final String damageType;
  final double damageLength;  // 新增
  final double damageWidth;   // 新增
  final String period;        // 上午 / 下午
  final String weather;       // 天氣
  final double longitude;     // GPS 經度
  final double latitude;      // GPS 緯度
  final String remark;        // 備註
  final String? material;     // 施工材料
  final double? refillLength; // 回填長度
  final double? refillWidth;  // 回填寬度
  final int?    quantity;     // 材料數量
  final String  photoUrl;     // 原本的主圖
  final String? photoBefore;  // img_before
  final String? photoDuring;  // img_during
  final String? photoAfter;   // img_after

  InspectionItem({
    required this.id,
    required this.caseNum,
    required this.formType,
    required this.recordDate,
    required this.person,
    required this.district,
    required this.village,
    required this.address,
    required this.damageType,
    required this.damageLength,
    required this.damageWidth,
    required this.period,
    required this.weather,
    required this.longitude,
    required this.latitude,
    required this.remark,
    this.material,
    this.refillLength,
    this.refillWidth,
    this.quantity,
    required this.photoUrl,
    this.photoBefore,
    this.photoDuring,
    this.photoAfter,
  });

  factory InspectionItem.fromJson(Map<String, dynamic> j) {
    const urlBase = '${ApiConfig.baseUrl}/';
    String photoUrl = '';
    String? photoBefore;
    String? photoDuring;
    String? photoAfter;

    if (j['images'] is List) {
      for (var img in j['images'] as List<dynamic>) {
        final m = img as Map<String, dynamic>;
        final path = m['img_path'] as String? ?? '';
        if (path.isEmpty) continue;
        switch (m['img_type']) {
          case 'IMG':
            photoUrl = urlBase + path;
            break;
          case 'IMG_BEFORE':
            photoBefore = urlBase + path;
            break;
          case 'IMG_DURING':
            photoDuring = urlBase + path;
            break;
          case 'IMG_AFTER':
            photoAfter = urlBase + path;
            break;
        }
      }
    }

    return InspectionItem(
      id:          j['id']              as int,
      caseNum:     j['case_num']        as String,
      formType:    j['type']            as String,
      recordDate:  DateTime.parse(j['survey_date'] as String),
      person:      j['prj_id']          as String,
      district:    j['district']        as String,
      village:     j['cavlge']          as String,
      address:     j['address']         as String,
      damageType:  j['dtype']           as String,
      damageLength: (j['dtype_length']  as num).toDouble(),
      damageWidth:  (j['dtype_width']   as num).toDouble(),
      period:      j['period']          as String,
      weather:     j['weather']         as String,
      longitude:   (j['longitude']      as num).toDouble(),
      latitude:    (j['latitude']       as num).toDouble(),
      remark:      j['remark']          as String,
      material:    j['material']        as String?,
      refillLength: j['refill_length'] != null ? (j['refill_length'] as num).toDouble() : null,
      refillWidth:  j['refill_width']  != null ? (j['refill_width']  as num).toDouble() : null,
      quantity:     j['quantity']      as int?,
      photoUrl:     photoUrl,
      photoBefore:  photoBefore,
      photoDuring:  photoDuring,
      photoAfter:   photoAfter,
    );
  }
}


class InspectionListPage extends StatefulWidget {
  const InspectionListPage({Key? key}) : super(key: key);
  @override
  _InspectionListPageState createState() => _InspectionListPageState();
}

class _InspectionListPageState extends State<InspectionListPage> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  int _activeFilter = 0;

  // UI-only 縣市
  // String? _selectedCounty;
  // final _counties = ['臺北市','新北市','桃園市','臺中市','臺南市','高雄市'];

  // 真正帶去 Query 的多選
  List<int> _selectedProjectIds = [];
  List<String> _selectedDistricts = [];
  List<String> _selectedFormTypes = [];
  List<String> _selectedDamageTypes = [];
  List<String> _selectedVillages = [];
  final TextEditingController _caseNumController = TextEditingController();

  bool _showFilters = false;
  bool _loading = false;
  List<InspectionItem> _results = [];

  late final ScrollController _districtScrollController;
  late final ScrollController _villageScrollController;

  List<Tender> _tenders = [];
  Map<String, List<String>> _villagesMap = {};
  // final List<String> _villages = [ // TODO: 用真實資料塞這裡
  //   '仁福里','中興里','溪洲里','復興里'
  // ];
  final List<String> _formTypes = ['巡查單', '巡修單'];
  final List<String> _damageTypes = [
    '坑洞','龜裂','下陷','掏空','管線回填','補綻','人手孔','車轍','車道與路肩高差',
    '縱橫向裂縫','塊狀裂縫','邊緣裂縫','反射裂縫','滑動裂縫','粒料光滑','跨越鐵道',
    '波浪型鋪面','凸起','推擠','隆起','剝脫','風化','冒油',
  ];

  // bool _expProjects = false;
  // bool _expDistricts = false;
  // bool _expFormTypes = false;
  // bool _expDamageTypes = false;

  @override
  void initState() {
    super.initState();
    _districtScrollController = ScrollController();
    _villageScrollController = ScrollController();
    _fetchTenders();
    _fetchVillages();
    _fetchInspections();
  }

  @override
  void dispose() {
    // 記得 dispose
    _districtScrollController.dispose();
    _villageScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTenders() async {
    final token = context.read<AppState>().token;
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/get/tender');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
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

  // 新增：一次拿到所有里別的結構
  Future<void> _fetchVillages() async {
    final token = context.read<AppState>().token;
    final resp = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/get/geo/area'),
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
    final initial = isStart ? _startDate : _endDate;
    final dt = await showDatePicker(
      context: context,
      locale: const Locale('zh', 'TW'),
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (dt != null) {
      setState(() {
        if (isStart) _startDate = dt;
        else _endDate = dt;
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
      qs.add('$key=');  // 多一個空值參數，變成 array
    }
  }

  Future<void> _fetchInspections() async {
    setState(() {
      _loading = true;
      _results.clear();
    });

    final qs = <String>[];

    // 起迄日期永遠要
    qs.add('startDate=${Uri.encodeComponent(DateFormat('yyyy-MM-dd').format(_startDate))}');
    qs.add('endDate=${Uri.encodeComponent(DateFormat('yyyy-MM-dd').format(_endDate))}');

    // 多值參數用 helper
    _addArrayParam(_selectedFormTypes, 'formTypes', qs);
    _addArrayParam(_selectedProjectIds, 'projectIds', qs);
    _addArrayParam(_selectedDistricts, 'districts', qs);
    _addArrayParam(_selectedDamageTypes, 'cracktypes', qs);

    // caseNumber 單一字串
    if (_caseNumController.text.isNotEmpty) {
      qs.add('caseNumber=${Uri.encodeComponent(_caseNumController.text)}');
    }

    final url = '${ApiConfig.baseUrl}/api/get/workorder/maintenance?${qs.join('&')}';
    print('🔍 Request URL: $url');

    try {
      final token = context.read<AppState>().token;
      final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});

      // --- 印出原始回應，方便 debug
      print('🔍 Response status: ${resp.statusCode}');
      print('🔍 Response body: ${resp.body}');

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['status'] == true && body['data'] is List) {
          setState(() {
            _results = (body['data'] as List)
                .map((j) => InspectionItem.fromJson(j))
                .toList();
          });
        } else {
          final msg = body['message'] ?? '未知錯誤';
          print('❌ 查詢失敗: $msg');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('查詢失敗：$msg')),
          );
        }
      } else {
        print('❌ HTTP 錯誤 ${resp.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('HTTP ${resp.statusCode} 錯誤')),
        );
      }
    } catch (e, stack) {
      print('🔥 Exception in _fetchInspections: $e');
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
    // 計算可選行政區與里別
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
          // 「新增案件」按鈕
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0070C0),
              foregroundColor: Colors.white,
            ),
            onPressed: () =>
                Navigator.pushNamed(context, '/inspectionForm'),
            child: const Text('新增案件'),
          ),
          const SizedBox(width: 8),
          // 標題
          Expanded(
            child: Text(
              '巡修單列表',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF30475E),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 查詢欄切換
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
    // 資料表
    Expanded(
    child: _results.isEmpty
    ? Center(child: Text(_loading ? '查詢中…' : '尚無資料，請按「查詢」'))
        : SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.all(12),
    child: DataTable(
    columns: const [
    DataColumn(label: Text('表單類型')),
    DataColumn(label: Text('案件編號')),
    DataColumn(label: Text('巡查日期')),
    DataColumn(label: Text('人員')),
    DataColumn(label: Text('行政區')),
    DataColumn(label: Text('里別')),
    DataColumn(label: Text('地址')),
    DataColumn(label: Text('破壞類型')),
    DataColumn(label: Text('照片')),
    ],
    rows: _results.map((item) {
    return DataRow(
    onSelectChanged: (sel) {
    if (sel == true) {
    Navigator.pushNamed(
    context,
    '/inspectionForm',
    arguments: item,
    );
    }
    },
    cells: [
    DataCell(Text(item.formType)),
    DataCell(Text(item.caseNum)),
    DataCell(Text(DateFormat('yyyy-MM-dd').format(item.recordDate))),
    DataCell(Text(item.person)),
    DataCell(Text(item.district)),
    DataCell(Text(item.village)),
    DataCell(Text(item.address)),
    DataCell(Text(item.damageType)),
    DataCell(
    item.photoUrl.isNotEmpty
    ? Image.network(
    item.photoUrl,
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

    // 半透遮罩：點擊可收起查詢欄
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
    // 起訖日期
    Row(
    children: [
    _buildDateField('開始日期', _startDate, () => _pickDate(isStart: true)),
    const SizedBox(width: 12),
    _buildDateField('結束日期', _endDate, () => _pickDate(isStart: false)),
    ],
    ),
    const SizedBox(height: 8),
    // 標案
    Row(
    children: [
    SizedBox(
    width: 200,
    child: ExpansionTile(
    title: Text(
    '標案：${_selectedProjectIds.isEmpty ? '' : _selectedProjectIds.map((i) => _tenders.firstWhere((t) => t.id == i).name).join('、')}',
    style: const TextStyle(fontSize: 14),
    ),
    initiallyExpanded: _activeFilter == 2,
    onExpansionChanged: (o) => setState(() => _activeFilter = o ? 2 : 0),
    children: [
    ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 230),
    child: Scrollbar(
    child: ListView(
    padding: EdgeInsets.zero,
    children: _tenders.map((t) {
    final checked = _selectedProjectIds.contains(t.id);
    return CheckboxListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    title: Text(t.name),
    value: checked,
    onChanged: (v) {
    setState(() {
    if (v == true) _selectedProjectIds.add(t.id);
    else _selectedProjectIds.remove(t.id);
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
    // 表單類型
    SizedBox(
    width: 120,
    child: ExpansionTile(
    title: Text('表單：${_selectedFormTypes.join('、')}'),
    initiallyExpanded: _activeFilter == 3,
    onExpansionChanged: (o) => setState(() => _activeFilter = o ? 3 : 0),
    children: [
    ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 130),
    child: Scrollbar(
    child: ListView(
    padding: EdgeInsets.zero,
    children: _formTypes.map((f) {
    final c = _selectedFormTypes.contains(f);
    return CheckboxListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    title: Text(f),
    value: c,
    onChanged: (v) {
    setState(() {
    if (v == true) _selectedFormTypes.add(f);
    else _selectedFormTypes.remove(f);
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
    // 行政區 & 里別
    Row(
    children: [
    SizedBox(
    width: 160,
    child: ExpansionTile(
    title: Text('行政區：${_selectedDistricts.join('、')}'),
    initiallyExpanded: _activeFilter == 1,
    onExpansionChanged: (o) => setState(() => _activeFilter = o ? 1 : 0),
    children: [
    ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 180),
    child: Scrollbar(
    controller: _districtScrollController,
    thickness: 4,
    thumbVisibility: true,
    child: ListView(
    controller: _districtScrollController,
    padding: EdgeInsets.zero,
    children: availableDistricts.map((d) {
    final c = _selectedDistricts.contains(d);
    return CheckboxListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    title: Text(d),
    value: c,
    onChanged: (v) {
    setState(() {
    if (v == true) _selectedDistricts.add(d);
    else _selectedDistricts.remove(d);
    _selectedVillages = _selectedVillages
        .where((x) => availableVillages.contains(x))
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
    title: Text('里別：${_selectedVillages.join('、')}'),
    initiallyExpanded: _activeFilter == 5,
    onExpansionChanged: (o) => setState(() => _activeFilter = o ? 5 : 0),
    children: [
    ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 270),
    child: Scrollbar(
    controller: _villageScrollController,
    thickness: 4,
    thumbVisibility: true,
    child: ListView(
    controller: _villageScrollController,
    padding: EdgeInsets.zero,
    children: availableVillages.map((v) {
    final c = _selectedVillages.contains(v);
    return CheckboxListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
    title: Text(v),
    value: c,
    onChanged: (x) {
    setState(() {
    if (x == true) _selectedVillages.add(v);
    else _selectedVillages.remove(v);
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
    // 破壞類型 & 案件編號
    Row(
    children: [
    SizedBox(
    width: 160,
    child: ExpansionTile(
    title: Text('破壞：${_selectedDamageTypes.join('、')}'),
    initiallyExpanded: _activeFilter == 4,
    onExpansionChanged: (o) => setState(() => _activeFilter = o ? 4 : 0),
    children: [
    ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 270),
    child: Scrollbar(
    child: ListView(
    padding: EdgeInsets.zero,
    children: _damageTypes.map((d) {
    final c = _selectedDamageTypes.contains(d);
    return CheckboxListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
    title: Text(d),
    value: c,
    onChanged: (v) {
    setState(() {
    if (v == true) _selectedDamageTypes.add(d);
    else _selectedDamageTypes.remove(d);
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
    width: 150,
    child: TextField(
    controller: _caseNumController,
    decoration: const InputDecoration(labelText: '案件編號'),
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
    await _fetchInspections();
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


  Widget _buildDateField(String label, DateTime date, VoidCallback onTap) {
    return SizedBox(
      width: 140,
      child: TextFormField(
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today),
          isDense: true,
        ),
        controller:
        TextEditingController(text: DateFormat('yyyy-MM-dd').format(date)),
        onTap: onTap,
      ),
    );
  }
}