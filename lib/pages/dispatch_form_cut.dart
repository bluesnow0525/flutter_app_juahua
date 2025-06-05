import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:convert'; // 用於 UTF8 解碼與 Base64
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:xml/xml.dart' as xml;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';  // getTemporaryDirectory
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';
import 'map_picker_page.dart';
import './dispatch_list.dart';
import '../components/upload_services.dart';        // UploadService.enqueue
import '../components/upload_record.dart';
import '../components/config.dart';

/// 標案模型
class Tender {
  final String prjId;
  final String prjName;
  final List<String> districts;
  Tender({required this.prjId, required this.prjName, required this.districts});
  factory Tender.fromJson(Map<String, dynamic> json) => Tender(
    prjId: json['prjId'] as String,
    prjName: json['prjName'] as String,
    districts: List<String>.from(json['districts'] ?? <dynamic>[]),
  );
}

class DispatchCutFormPage extends StatefulWidget {
  const DispatchCutFormPage({Key? key}) : super(key: key);

  @override
  _DispatchCutFormPageState createState() => _DispatchCutFormPageState();
}

class _DispatchCutFormPageState extends State<DispatchCutFormPage> {
  // ------------------ 控制器 ------------------
  final TextEditingController _caseIdController = TextEditingController(); // 案件編號
  final TextEditingController _projectNameController = TextEditingController(); // 標案
  final TextEditingController _districtController = TextEditingController();    // 行政區
  final TextEditingController _villageController = TextEditingController();     // 里別
  final TextEditingController _dispatchDateController = TextEditingController(); // 派工日期
  final TextEditingController _deadlineController = TextEditingController();     // 施工期限
  final TextEditingController _workDateController = TextEditingController();     // 施工日期
  final TextEditingController _completeDateController = TextEditingController(); // 完工日期
  final TextEditingController _roadNameController = TextEditingController();     // 施工路名

  // 起點
  final TextEditingController _startRoadNameController = TextEditingController();
  final TextEditingController _startGPSController = TextEditingController();
  // 迄點
  final TextEditingController _endRoadNameController = TextEditingController();
  final TextEditingController _endGPSController = TextEditingController();

  // 材料/粒徑
  String _selectedMaterial = "新料";
  final List<String> _materials = ["新料", "再生料"];
  final TextEditingController _particleSizeController = TextEditingController();

  // 範圍與深度
  final TextEditingController _rangeLengthController = TextEditingController();
  final TextEditingController _rangeWidthController = TextEditingController();
  final TextEditingController _cutDepthController = TextEditingController();
  final TextEditingController _paveDepthController = TextEditingController();

  // 備註
  final TextEditingController _noteController = TextEditingController();

  // 照片
  List<File> _photoBefore = [];
  List<File> _photoCut = [];
  List<File> _photoDuring = [];
  List<File> _photoAfter = [];
  final List<File> _photoOthers = [];
  final ImagePicker _picker = ImagePicker();

  // tender 相關
  List<Tender> _tenders = [];
  String? _selectedPrjId;
  List<String> _districtOptions = [];
  String? _selectedDistrict;

  // 編輯模式旗標與儲存傳入的 DispatchItem
  DispatchItem?  _initialArgs;
  bool          _hasInitFromArgs = false;
  bool _hasInitArgs = false;
  bool _isEditMode = false;
  late DispatchItem _editItem;
  // 舊圖 URL（用於編輯時顯示網路圖）
  String? _existingBeforeUrl;
  String? _existingCutUrl;
  String? _existingDuringUrl;
  String? _existingAfterUrl;
  List<Uint8List> _existingOtherImages = [];
  String? _existingOtherZipUrl;
  String? _existingImgZipUrl;
  String? _existingOtherZipLocalPath;

  dynamic _rawArgs;

  @override
  void initState() {
    super.initState();
    // _caseIdController.text = '';
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   final args = ModalRoute.of(context)?.settings.arguments;
    //   if (args is DispatchItem) {
    //     _initialArgs = args;
    //   } else {
    //     // 只有「新增模式」才一開始抓 GPS
    //     _onLocateGPS(_startGPSController);
    //   }
    //   _fetchTenders();
    // });
    _caseIdController.text = '';
    // _onLocateGPS(_startGPSController);
    _fetchTenders();
  }

  @override
  void dispose() {
    _caseIdController.dispose();
    _projectNameController.dispose();
    _districtController.dispose();
    _villageController.dispose();
    _dispatchDateController.dispose();
    _deadlineController.dispose();
    _workDateController.dispose();
    _completeDateController.dispose();
    _roadNameController.dispose();
    _startRoadNameController.dispose();
    _startGPSController.dispose();
    _endRoadNameController.dispose();
    _endGPSController.dispose();
    _particleSizeController.dispose();
    _rangeLengthController.dispose();
    _rangeWidthController.dispose();
    _cutDepthController.dispose();
    _paveDepthController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 当用户点选标案时调用：更新行政区选项，并在编辑时尝试恢复 editItem.district
  void _onProjectChanged(String prjId) {
    // 找到對應的 Tender
    final tender = _tenders.firstWhere((t) => t.prjId == prjId);
    final districts = tender.districts.toSet().toList();

    // 根據不同模式選出要顯示的區域
    String? chosen;
    if (_rawArgs is DispatchItem) {
      // 真正從後端拉回來的編輯模式 -> 用 DispatchItem 裡的 district 還原
      final item = _rawArgs as DispatchItem;
      chosen = districts.contains(item.district)
          ? item.district
          : (districts.isNotEmpty ? districts.first : null);
    } else if (_rawArgs is UploadRecord) {
      // 本地重傳 -> 保留之前在 body 裡回填的 _selectedDistrict（若無效才 fallback）
      chosen = (_selectedDistrict != null && districts.contains(_selectedDistrict))
          ? _selectedDistrict
          : (districts.isNotEmpty ? districts.first : null);
    } else {
      // 新增模式 -> 一律預設第一個
      chosen = districts.isNotEmpty ? districts.first : null;
    }

    setState(() {
      _selectedPrjId = prjId;
      _projectNameController.text = tender.prjName;
      _districtOptions = districts;
      _selectedDistrict = chosen;
      _districtController.text = chosen ?? '';
    });
  }

  /// 根据 DispatchItem.images 填充网络图片 URL
  /// 先把后端给你的所有 img_url 下载并存成本地 File，再赋给 _photoXxx
  Future<void> _populateExistingImageUrls(DispatchItem item) async {
    for (var img in item.images) {
      final url  = '${ApiConfig.baseUrl}/${img['img_path']}';
      final type = img['img_type'] as String;

      // 1) 先下載到暫存
      final localArchive = await _downloadToTemp(url);
      final bytes        = File(localArchive).readAsBytesSync();

      // 2) 嘗試用 ZipDecoder 解壓，失敗就跳過
      Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        print('≫ 非 ZIP/解壓失敗，跳過 $url：$e');
        continue;
      }

      // 3) 把每個檔案寫出來，放到對應陣列
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final raw     = f.content as List<int>;
        final outName = '${const Uuid().v4()}_${f.name}';
        final dir     = (await getTemporaryDirectory()).path;
        final outPath = '$dir/$outName';
        final outFile = File(outPath)..writeAsBytesSync(raw);

        switch (type) {
          case 'IMG_BEFORE_ZIP':
            _photoBefore.add(outFile);
            break;
          case 'IMG_MILLING_AFTER_ZIP': // 服務端對應「刨除後」
            _photoCut.add(outFile);
            break;
          case 'IMG_CUT_ZIP':
            _photoCut.add(outFile);
            break;
          case 'IMG_DURING_ZIP':
            _photoDuring.add(outFile);
            break;
          case 'IMG_AFTER_ZIP':
            _photoAfter.add(outFile);
            break;
          default:
            _photoOthers.add(outFile);
        }
      }
    }
    setState(() {});
  }

  /// 將 DispatchItem 的值注入各欄位
  void _populateFields(DispatchItem item) {
    _caseIdController.text = item.caseNum;
    _onProjectChanged(item.prjId);
    _villageController.text      = item.village;
    _dispatchDateController.text = DateFormat('yyyy-MM-dd').format(item.dispatchDate);
    _deadlineController.text     = DateFormat('yyyy-MM-dd').format(item.dueDate);
    _workDateController.text     = DateFormat('yyyy-MM-dd').format(item.workStartDate);
    _completeDateController.text = DateFormat('yyyy-MM-dd').format(item.workEndDate);
    _roadNameController.text     = item.address;
    _startRoadNameController.text = item.startAddr;  // 新增：接收後端 START_ADDR
    _endRoadNameController.text   = item.endAddr;
    _startGPSController.text     = '${item.startLng}, ${item.startLat}';
    _endGPSController.text       = '${item.endLng}, ${item.endLat}';
    _selectedMaterial            = item.material;
    _particleSizeController.text = item.materialSize.toString();
    _rangeLengthController.text  = item.workLength.toString();
    _rangeWidthController.text   = item.workWidth.toString();
    _cutDepthController.text     = item.workDepthMilling.toString();
    _paveDepthController.text    = item.workDepthPaving.toString();
    _noteController.text         = item.remark;

    // **清空**所有本地列表，保留网络图在 _existingXXXUrl
    _photoBefore.clear();
    _photoCut.clear();
    _photoDuring.clear();
    _photoAfter.clear();
    _photoOthers.clear();
  }

  /// 從 existingOtherZipUrl 下載 ZIP，解壓並把每張圖塞進 _existingOtherImages
  Future<void> _loadOtherZipImages() async {
    if (_existingOtherZipUrl == null) return;
    try {
      final resp = await http.get(Uri.parse(_existingOtherZipUrl!));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        final archive = ZipDecoder().decodeBytes(bytes);
        final imgs = <Uint8List>[];
        for (final file in archive) {
          if (file.isFile) {
            imgs.add(Uint8List.fromList(file.content as List<int>));
          }
        }
        setState(() {
          _existingOtherImages = imgs;
        });
      }
    } catch (e) {
      print('解壓其他照片 ZIP 例外：$e');
    }
  }

  /// 取得標案列表
  /// 从后端取得标案列表，并根据已有 state 恢复选择
  /// 第一次进入页面时，只取一次路由参数
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasInitArgs) return;

    // 只取一次路由參數
    final args = ModalRoute.of(context)?.settings.arguments;
    _rawArgs = args;
    _hasInitArgs = true;

    // 只有「新增模式」（沒有任何 arguments）才自動抓起點 GPS
    if (args == null) {
      _onLocateGPS(_startGPSController);
    }
  }

  /// 取得標案列表，並根據路由參數決定「新增 / 從伺服器編輯 / 本地重傳」
  Future<void> _fetchTenders() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final resp = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/get/tender'),
      headers: {'Authorization': 'Bearer ${appState.token}'},
    );
    if (resp.statusCode != 200) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('取得標案失敗'),
          content: Text('狀態：${resp.statusCode}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('確定'))
          ],
        ),
      );
      return;
    }

    final List<Tender> list = (jsonDecode(resp.body)['data'] as List)
        .map((e) => Tender.fromJson(e))
        .toList();
    if (list.isEmpty) return;

    setState(() {
      _tenders = list;

      // —— 1) 先設定 _selectedPrjId 與 _projectNameController.text ——
      if (_rawArgs is DispatchItem) {
        final item = _rawArgs as DispatchItem;
        _isEditMode = true;
        _editItem = item;
        // 找到對應的 Tender
        final tender = list.firstWhere(
              (t) => t.prjId == item.prjId,
          orElse: () => list.first,
        );
        _selectedPrjId = tender.prjId;
        _projectNameController.text = tender.prjName;

        // 行政區去重、並恢復 args 裡的選擇
        _districtOptions = tender.districts.toSet().toList();
        _selectedDistrict = _districtOptions.contains(item.district)
            ? item.district
            : (_districtOptions.isNotEmpty ? _districtOptions.first : null);
        _districtController.text = _selectedDistrict ?? '';

        // 里別直接用 args 裡的
        _villageController.text = item.village;
      }
      else if (_rawArgs is UploadRecord) {
        final rec = _rawArgs as UploadRecord;
        _isEditMode = rec.isEditing;
        final m = rec.body;

        // 找到對應 Tender
        final prjId = m['PRJ_ID']?.toString() ?? list.first.prjId;
        final tender = list.firstWhere(
              (t) => t.prjId == prjId,
          orElse: () => list.first,
        );
        _selectedPrjId = tender.prjId;
        _projectNameController.text = tender.prjName;

        // 行政區去重、並恢復 rec.body 裡的 DISTRICT
        _districtOptions = tender.districts.toSet().toList();
        final recDist = m['DISTRICT']?.toString();
        _selectedDistrict = (recDist != null && _districtOptions.contains(recDist))
            ? recDist
            : (_districtOptions.isNotEmpty ? _districtOptions.first : null);
        _districtController.text = _selectedDistrict ?? '';

        // 里別用 rec.body 裡的 CAVLGE
        _villageController.text = m['CAVLGE']?.toString() ?? '';

        // 其他文字欄位與本地圖片回填……
        _caseIdController.text = (m['case_num'] as String?)?.isNotEmpty == true
                 ? m['case_num']!
                 : (m['caseNum'] as String?)?.toString() ?? '';
        _dispatchDateController.text = m['DISPATCH_DATE'] ?? '';
        _deadlineController.text     = m['DUE_DATE'] ?? '';
        _workDateController.text     = m['WORK_START_DATE'] ?? '';
        _completeDateController.text = m['WORK_END_DATE'] ?? '';
        _roadNameController.text     = m['ADDRESS'] ?? '';
        _startRoadNameController.text = m['START_ADDR']?.toString() ?? '';
        _endRoadNameController.text   = m['END_ADDR']?.toString() ?? '';
        _startGPSController.text     = '${m['START_LNG']}, ${m['START_LAT']}';
        _endGPSController.text       = '${m['END_LNG']}, ${m['END_LAT']}';
        _selectedMaterial            = m['MATERIAL'] ?? _selectedMaterial;
        _particleSizeController.text = m['MATERIAL_SIZE'] ?? '';
        _rangeLengthController.text  = m['WORK_LENGTH'] ?? '';
        _rangeWidthController.text   = m['WORK_WIDTH'] ?? '';
        _cutDepthController.text     = m['WORK_DEPTH_MILLING'] ?? '';
        _paveDepthController.text    = m['WORK_DEPTH_PAVING'] ?? '';
        _noteController.text         = m['REMARK'] ?? '';

        // 回填本地圖片
        _photoBefore.clear();
        _photoCut.clear();
        _photoDuring.clear();
        _photoAfter.clear();
        _photoOthers.clear();
        rec.filePathMap?.forEach((key, path) {
          final f = File(path);
          if (key.startsWith('IMG_BEFORE'))     _photoBefore.add(f);
          else if (key.startsWith('IMG_MILLING_AFTER')
                 || key.startsWith('IMG_CUT')) {
             _photoCut.add(f);
          }
          else if (key.startsWith('IMG_DURING'))_photoDuring.add(f);
          else if (key.startsWith('IMG_AFTER')) _photoAfter.add(f);
          else if (key.startsWith('IMG_OTHER')) _photoOthers.add(f);
        });
      }
      else {
        // 新增模式：選第一筆
        _isEditMode = false;
        final tender = list.first;
        _selectedPrjId = tender.prjId;
        _projectNameController.text = tender.prjName;
        _districtOptions = tender.districts.toSet().toList();
        _selectedDistrict = _districtOptions.isNotEmpty ? _districtOptions.first : null;
        _districtController.text = _selectedDistrict ?? '';
        // 里別透過 GPS/API 自動填入即可，不用這邊處理
      }

      // 套用 dropdown 與 district text
      _onProjectChanged(_selectedPrjId!);
    });

    // 如果是「從伺服器編輯」還要跑一次影像解包
    if (_rawArgs is DispatchItem) {
      final item = _rawArgs as DispatchItem;
      // 填一次文字欄位（因為 _onProjectChanged 只處理案名＋行政區）
      _populateFields(item);
      // 網路圖打包解壓
      await _populateExistingImageUrls(item);
    }
  }

  // ------------------ 選日期 ------------------
  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('zh', 'TW'),
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // ------------------ 拍照/選圖 ------------------
  Future<void> _pickPhotoDialog(String title) async {
    final List<XFile>? files = await _picker.pickMultiImage();
    if (files == null || files.isEmpty) return;
    setState(() {
      switch (title) {
        case '施工前':
          _photoBefore.addAll(files.map((f) => File(f.path)));
          break;
        case '刨除後':
          _photoCut.addAll(files.map((f) => File(f.path)));
          break;
        case '施工中':
          _photoDuring.addAll(files.map((f) => File(f.path)));
          break;
        case '施工後':
          _photoAfter.addAll(files.map((f) => File(f.path)));
          break;
        case '其他':
          _photoOthers.addAll(files.map((f) => File(f.path)));
          break;
      }
    });
  }

  // void _assignPhoto(String title, File file) {
  //   switch (title) {
  //     case '施工前':
  //       _photoBefore = file;
  //       break;
  //     case '刨除後':
  //       _photoCut = file;
  //       break;
  //     case '施工中':
  //       _photoDuring = file;
  //       break;
  //     case '施工後':
  //       _photoAfter = file;
  //       break;
  //     default:
  //       break;
  //   }
  // }

  // ------------------ GPS 功能 ------------------
  Future<void> _onEditGPS(TextEditingController gpsController, {bool fetchVillage = false}) async {
    LatLng initPos;
    if (gpsController.text.contains(',')) {
      // 已有座標，格式 "lng, lat"
      final parts = gpsController.text.split(',');
      initPos = LatLng(
        double.tryParse(parts[1].trim()) ?? 25.0330,
        double.tryParse(parts[0].trim()) ?? 121.5654,
      );
    } else {
      // 無座標，先取得目前定位
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      initPos = LatLng(pos.latitude, pos.longitude);
    }

    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerPage(initialPosition: initPos)),
    );
    if (result != null) {
      setState(() {
        // 經度, 緯度
        gpsController.text = '${result.longitude.toStringAsFixed(6)}, ${result.latitude.toStringAsFixed(6)}';
      });
      if (gpsController == _startGPSController) {
        _fetchVillageNameAt(result.longitude, result.latitude);
      }
    }
  }

  Future<void> _onLocateGPS(TextEditingController gpsController) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        // 先經度
        print('GPS 位置取得: 經度 ${pos.longitude}, 緯度 ${pos.latitude}');
        gpsController.text = '${pos.longitude.toStringAsFixed(6)}, ${pos.latitude.toStringAsFixed(6)}';
        if (gpsController == _startGPSController) {
          _fetchVillageNameAt(pos.longitude, pos.latitude);
        }
      } else {
        print('定位權限未授予');
      }
    } catch (e) {
      print('取得定位時發生錯誤: $e');
    }
  }

  // ------------------ API 取得里別 ------------------
  Future<void> _fetchVillageNameAt(double lng, double lat) async {
    final url = 'https://api.nlsc.gov.tw/other/TownVillagePointQuery/$lng/$lat/4326';
    print('呼叫國土API URL: $url');
    try {
      final resp = await http.get(Uri.parse(url));
      print('API 狀態碼: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final decoded = utf8.decode(resp.bodyBytes);
        print('API 回傳資料: $decoded');
        final doc = xml.XmlDocument.parse(decoded);
        final elems = doc.findAllElements('villageName');
        if (elems.isNotEmpty) {
          final name = elems.first.text;
          print('取得里別名稱: $name');
          setState(() => _villageController.text = name);
        } else {
          print('未取得 <villageName> 元素');
        }
      } else {
        print('Error: API 回傳狀態 ${resp.statusCode}');
      }
    } catch (e) {
      print('查里別例外：$e');
    }
  }

  // // ------------------ Base64 & Zip 圖片壓縮 ------------------
  // Future<String> _encodeOtherPhotosZip() async {
  //   final archive = Archive();
  //   for (var file in _photoOthers) {
  //     final bytes = await file.readAsBytes();
  //     archive.addFile(ArchiveFile(file.path.split('/').last, bytes.length, bytes));
  //   }
  //   final zipData = ZipEncoder().encode(archive);
  //   return zipData != null ? base64Encode(zipData) : '';
  // }

  // ------------------ 上傳 API ------------------
  /// 统一处理 POST（新增）/PATCH（编辑）上傳
  // Future<void> _uploadData() async {
  //   final appState = Provider.of<AppState>(context, listen: false);
  //   final method   = _isEditMode ? 'PATCH' : 'POST';
  //   final uri      = Uri.parse('http://211.23.157.201/api/app/workorder/repairDispatch');
  //   final req      = http.MultipartRequest(method, uri)
  //     ..headers['Authorization'] = 'Bearer ${appState.token}';
  //
  //   // 1) 組欄位
  //   final Map<String, String> fields = {};
  //   if (_isEditMode) {
  //     fields['ID'] = _editItem.id.toString();
  //   }
  //   fields['PRJ_ID'] = _selectedPrjId ?? '';
  //   fields['TYPE']   = 'PA';
  //
  //   // 解析 GPS
  //   double sl=0, sa=0, el=0, ea=0;
  //   if (_startGPSController.text.contains(',')) {
  //     final p = _startGPSController.text.split(',');
  //     sl = double.tryParse(p[0].trim()) ?? 0;
  //     sa = double.tryParse(p[1].trim()) ?? 0;
  //   }
  //   if (_endGPSController.text.contains(',')) {
  //     final p = _endGPSController.text.split(',');
  //     el = double.tryParse(p[0].trim()) ?? 0;
  //     ea = double.tryParse(p[1].trim()) ?? 0;
  //   }
  //
  //   fields.addAll({
  //     'DISPATCH_DATE':    _dispatchDateController.text,
  //     'DUE_DATE':         _deadlineController.text,
  //     'DISTRICT':         _selectedDistrict ?? '',
  //     'CAVLGE':           _villageController.text,
  //     'ADDRESS':          _roadNameController.text,
  //     'WORK_START_DATE':  _workDateController.text,
  //     'WORK_END_DATE':    _completeDateController.text,
  //     'START_LNG':        sl.toString(),
  //     'START_LAT':        sa.toString(),
  //     'END_LNG':          el.toString(),
  //     'END_LAT':          ea.toString(),
  //     'MATERIAL':         _selectedMaterial,
  //     'MATERIAL_SIZE':    _particleSizeController.text,
  //     'WORK_LENGTH':      _rangeLengthController.text,
  //     'WORK_WIDTH':       _rangeWidthController.text,
  //     'WORK_DEPTH_MILLING': _cutDepthController.text,
  //     'WORK_DEPTH_PAVING':  _paveDepthController.text,
  //     'REMARK':           _noteController.text,
  //   });
  //   req.fields.addAll(fields);
  //
  //   // 2) 四張主圖打包成 IMG_ZIP
  //   final mainArc = Archive();
  //   void addMain(File? f, String name) {
  //     if (f != null) mainArc.addFile(ArchiveFile(name, f.lengthSync(), f.readAsBytesSync()));
  //   }
  //   addMain(_photoBefore, 'IMG_BEFORE.jpg');
  //   addMain(_photoCut,    'IMG_CUT.jpg');
  //   addMain(_photoDuring, 'IMG_DURING.jpg');
  //   addMain(_photoAfter,  'IMG_AFTER.jpg');
  //   if (mainArc.isNotEmpty) {
  //     final data = ZipEncoder().encode(mainArc)!;
  //     req.files.add(
  //       http.MultipartFile.fromBytes(
  //         'IMG_ZIP',
  //         data,
  //         filename: 'IMG.zip',
  //         contentType: MediaType('application', 'zip'),
  //       ),
  //     );
  //   }
  //
  //   // 3) 其它照片打包
  //   final otherArc = Archive();
  //   for (int i = 0; i < _photoOthers.length; i++) {
  //     final name = 'IMG_OTHER_${(i + 1).toString().padLeft(2, '0')}.jpg';
  //     otherArc.addFile(
  //         ArchiveFile(name, _photoOthers[i].lengthSync(), _photoOthers[i].readAsBytesSync())
  //     );
  //   }
  //   if (otherArc.isNotEmpty) {
  //     final data = ZipEncoder().encode(otherArc)!;
  //     req.files.add(
  //       http.MultipartFile.fromBytes(
  //         'IMG_OTHER_ZIP',
  //         data,
  //         filename: 'IMG_OTHER.zip',
  //         contentType: MediaType('application', 'zip'),
  //       ),
  //     );
  //   }
  //   // —— 在這裡加上 debug prints ——
  //   print('==== UPLOAD DEBUG ====');
  //   print('Method: $method');
  //   print('URL: $uri');
  //   print('Fields:');
  //   fields.forEach((k, v) => print('  $k: $v'));
  //   print('Files to upload:');
  //   for (var f in req.files) {
  //     print('  fieldName: ${f.field}, filename: ${f.filename}, length: ${f.length}');
  //   }
  //   print('=======================');
  //
  //   // 4) 發送並處理回應
  //   try {
  //     final streamed = await req.send();
  //     final respBody = await streamed.stream.bytesToString();
  //
  //     if (streamed.statusCode == 200) {
  //       // 解析 JSON
  //       final Map<String, dynamic> respJson = jsonDecode(respBody);
  //
  //       if (respJson['status'] == true) {
  //         // 真正的成功
  //         showDialog(
  //           context: context,
  //           builder: (_) => AlertDialog(
  //             title: const Text('上傳成功'),
  //             content: const Text('派工單已成功傳送'),
  //             actions: [
  //               TextButton(
  //                 onPressed: () => Navigator.pop(context),
  //                 child: const Text('確定'),
  //               ),
  //             ],
  //           ),
  //         );
  //       } else {
  //         // 200 但 status=false
  //         _showErrorDialog(
  //           streamed.statusCode,
  //           '後端回傳 status=false\nmessage: ${respJson['message']}\nbody: $respBody',
  //           fields,
  //           mainArc.files.map((e) => e.name).toList(),
  //           otherArc,
  //         );
  //       }
  //     } else {
  //       // HTTP 非 200
  //       _showErrorDialog(
  //         streamed.statusCode,
  //         respBody,
  //         fields,
  //         mainArc.files.map((e) => e.name).toList(),
  //         otherArc,
  //       );
  //     }
  //   } catch (e) {
  //     showDialog(
  //       context: context,
  //       builder: (_) => AlertDialog(
  //         title: const Text('上傳例外'),
  //         content: Text('例外：$e'),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.pop(context),
  //             child: const Text('確定'),
  //           ),
  //         ],
  //       ),
  //     );
  //   }
  // }
  //
  // /// 上传失败时弹窗（可选 helper）
  // void _showErrorDialog(int code, String body, Map<String,String> fields, List<String> mainNames, Archive otherA) {
  //   final buf=StringBuffer()
  //     ..writeln('狀態：$code')
  //     ..writeln('\n── 表單欄位 ──');
  //   fields.forEach((k,v)=>buf.writeln('$k: $v'));
  //   if (mainNames.isNotEmpty) buf..writeln('\n── IMG.zip 包含 ──')..writeln(mainNames.join(', '));
  //   if (otherA.isNotEmpty) buf..writeln('\n── IMG_OTHER.zip 包含 ──')..writeln(otherA.files.map((f)=>f.name).join(', '));
  //   buf..writeln('\n── 伺服器回傳 ──')..writeln(body);
  //   showDialog(context: context, builder: (_) => AlertDialog(
  //     title: const Text('上傳失敗'),
  //     content: SingleChildScrollView(child: Text(buf.toString())),
  //     actions: [ TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('確定')) ],
  //   ));
  // }
  //
  // void _onSaveUpload() {
  //   _uploadData();
  // }
  // Future<String> _downloadAndCache(String url, String prefix) async {
  //   final resp = await http.get(Uri.parse(url));
  //   final dir  = await getApplicationDocumentsDirectory();
  //   final file= File('${dir.path}/$prefix-${const Uuid().v4()}.jpg');
  //   await file.writeAsBytes(resp.bodyBytes);
  //   return file.path;
  // }
  Future<String> _downloadToTemp(String url) async {
    final resp = await http.get(Uri.parse(url));
    final dir  = await getTemporaryDirectory();
    // 保留副檔名，方便 ZipDecoder 辨識
    final ext = url.contains('.') ? url.substring(url.lastIndexOf('.')) : '';
    final file = File('${dir.path}/${const Uuid().v4()}$ext');
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }

  Future<void> _onSaveUpload() async {
    final List<String> missingFields = [];

    // PRJ_ID（標案）
    if (_selectedPrjId == null || _selectedPrjId!.isEmpty) {
      missingFields.add('標案名稱');
    }
    // TYPE（在這支程式裡固定 'PA'，理論上先前必然有設定，這裡可略過）
    // WORKER_USER_ID（本範例硬寫為 'APP'，若改為動態請一併檢查）
    // DispatchDate（派工日期）
    if (_dispatchDateController.text.trim().isEmpty) {
      missingFields.add('派工日期');
    }
    // DISTRICT（行政區）
    if (_districtController.text.trim().isEmpty) {
      missingFields.add('行政區');
    }
    // CAVLGE（里別）
    if (_villageController.text.trim().isEmpty) {
      missingFields.add('里別');
    }
    // ADDRESS（施工地點）
    if (_roadNameController.text.trim().isEmpty) {
      missingFields.add('施工地點');
    }
    // 起點經緯度
    final startGps = _startGPSController.text.trim();
    if (startGps.isEmpty || !startGps.contains(',') || startGps.split(',').length < 2) {
      missingFields.add('起點 GPS 定位');
    } else {
      final parts = startGps.split(',');
      if (double.tryParse(parts[0].trim()) == null || double.tryParse(parts[1].trim()) == null) {
        missingFields.add('起點 GPS 定位');
      }
    }
    // 迄點經緯度
    final endGps = _endGPSController.text.trim();
    if (endGps.isEmpty || !endGps.contains(',') || endGps.split(',').length < 2) {
      missingFields.add('迄點 GPS 定位');
    } else {
      final parts = endGps.split(',');
      if (double.tryParse(parts[0].trim()) == null || double.tryParse(parts[1].trim()) == null) {
        missingFields.add('迄點 GPS 定位');
      }
    }
    // WORK_DATE（施工日期）
    if (_workDateController.text.trim().isEmpty) {
      missingFields.add('施工日期');
    }
    // COMPLETE_DATE（完工日期）
    if (_completeDateController.text.trim().isEmpty) {
      missingFields.add('完工日期');
    }
    // DUE_DATE（施工期限）
    if (_deadlineController.text.trim().isEmpty) {
      missingFields.add('施工期限');
    }
    // → 新增：施工範圍（長）
    if (_rangeLengthController.text.trim().isEmpty) {
      missingFields.add('施工範圍（長）');
    }
    // → 新增：施工範圍（寬）
    if (_rangeWidthController.text.trim().isEmpty) {
      missingFields.add('施工範圍（寬）');
    }
    // → 新增：深度（刨除）
    if (_cutDepthController.text.trim().isEmpty) {
      missingFields.add('刨除深度');
    }
    // → 新增：深度（鋪設）
    if (_paveDepthController.text.trim().isEmpty) {
      missingFields.add('鋪設深度');
    }

    // 如果有缺少欄位，跳提示框並中斷
    if (missingFields.isNotEmpty) {
      final content = missingFields.join('、');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('資料不完整'),
          content: Text('請填寫以下欄位：\n$content'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      return;
    }

    // ---- 2️⃣ 日期順序檢查：派工日期 <= 施工日期 <= 完工日期 <= 施工期限 ----
    DateTime? dispatchDate;
    DateTime? workDate;
    DateTime? completeDate;
    DateTime? dueDate;
    try {
      dispatchDate = DateFormat('yyyy-MM-dd').parse(_dispatchDateController.text.trim());
      workDate     = DateFormat('yyyy-MM-dd').parse(_workDateController.text.trim());
      completeDate = DateFormat('yyyy-MM-dd').parse(_completeDateController.text.trim());
      dueDate      = DateFormat('yyyy-MM-dd').parse(_deadlineController.text.trim());
    } catch (e) {
      // 若解析失敗，視為格式不符
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('日期格式錯誤'),
          content: const Text('請確認所有日期格式均為 yyyy-MM-dd'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      return;
    }

    // 檢查順序
    if (!(dispatchDate.isBefore(workDate) || dispatchDate.isAtSameMomentAs(workDate)) ||
        !(workDate.isBefore(completeDate) || workDate.isAtSameMomentAs(completeDate)) ||
        !(completeDate.isBefore(dueDate) || completeDate.isAtSameMomentAs(dueDate))) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('日期順序錯誤'),
          content: const Text('請確保：\n派工日期 ≤ 施工日期 ≤ 完工日期 ≤ 施工期限'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      return;
    }

    // ---- 3️⃣ 全部檢查通過後，進入既有的 UploadRecord 建立與 enqueue 流程 ----
    // 1. 組 body
    final body = <String, dynamic>{
      // 'WORKER_USER_ID': context.read<AppState>().userId,
      'WORKER_USER_ID': 'APP',
      'case_num':        _caseIdController.text,
      'TYPE':            'PA',
      'PRJ_ID':          _selectedPrjId ?? '',
      'DISPATCH_DATE':   _dispatchDateController.text,
      'DUE_DATE':        _deadlineController.text,
      'DISTRICT':        _districtController.text,
      'CAVLGE':          _villageController.text,
      'ADDRESS':         _roadNameController.text,
      'START_ADDR':      _startRoadNameController.text,  // 新增：傳送至後端
      'END_ADDR':        _endRoadNameController.text,
      'WORK_START_DATE': _workDateController.text,
      'WORK_END_DATE':   _completeDateController.text,
      'START_LNG':       _startGPSController.text.split(',')[0].trim(),
      'START_LAT':       _startGPSController.text.split(',')[1].trim(),
      'END_LNG':         _endGPSController.text.split(',')[0].trim(),
      'END_LAT':         _endGPSController.text.split(',')[1].trim(),
      'MATERIAL':        _selectedMaterial,
      'MATERIAL_SIZE':   _particleSizeController.text,
      'WORK_LENGTH':     _rangeLengthController.text,
      'WORK_WIDTH':      _rangeWidthController.text,
      'WORK_DEPTH_MILLING': _cutDepthController.text,
      'WORK_DEPTH_PAVING':  _paveDepthController.text,
      'REMARK':         _noteController.text,
    };
    if (_rawArgs is UploadRecord) {
      final orig = _rawArgs as UploadRecord;
      // 優先用原身上的 ID，否則 fallback case_num
      final idVal = orig.body['ID'];
      if (idVal != null && idVal.toString().isNotEmpty) {
        body['ID'] = idVal.toString();
      }
    }
    else if (_rawArgs is DispatchItem) {
      // 從伺服器編輯模式，取 DispatchItem.id
      body['ID'] = _editItem.id.toString();
    }

    // 2. 把每個階段的所有照片都編號放進 fileMap
    final fileMap = <String, String>{};

    // 「施工前」(IMG_BEFORE_ZIP)
    for (var i = 0; i < _photoBefore.length; i++) {
      fileMap['IMG_BEFORE_${i + 1}.jpg'] = _photoBefore[i].path;
    }

    // 「刨除後」(IMG_MILLING_AFTER_ZIP)
    for (var i = 0; i < _photoCut.length; i++) {
      fileMap['IMG_MILLING_AFTER_${i + 1}.jpg'] = _photoCut[i].path;
    }

    // 「施工中」(IMG_DURING_ZIP)
    for (var i = 0; i < _photoDuring.length; i++) {
      fileMap['IMG_DURING_${i + 1}.jpg'] = _photoDuring[i].path;
    }

    // 「施工後」(IMG_AFTER_ZIP)
    for (var i = 0; i < _photoAfter.length; i++) {
      fileMap['IMG_AFTER_${i + 1}.jpg'] = _photoAfter[i].path;
    }

    // 「其他照片」(IMG_OTHER_ZIP)
    for (var i = 0; i < _photoOthers.length; i++) {
      fileMap['IMG_OTHER_${(i + 1).toString().padLeft(2, '0')}.jpg'] = _photoOthers[i].path;
    }

    // 3. 建 UploadRecord 並加入背景上傳佇列
    final rec = UploadRecord(
      body:      body,
      isEditing: _isEditMode,
      filePathMap: fileMap,
    );
    UploadService.enqueue(context, rec);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已加入上傳佇列，背景上傳中')));
    Navigator.pushReplacementNamed(context, '/uploadList');
  }

  // ------------------ UI 建構 ------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(),
      endDrawer: MyEndDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8), // 與下方元件留點距離
              child: Text(
                '派工單 - 刨除加封',
                textAlign: TextAlign.center, // 文字置中
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF30475E), // 文字顏色可依需求調整
                ),
              ),
            ),
            // 1) 案件編號
            _buildField(
              label: '案件編號',
              child: TextField(
                controller: _caseIdController,
                readOnly: true,
                decoration: _inputDecoration(isSpecialField: true),
              ),
            ),
            // 2) 標案名稱
            _buildField(
              label: '標案名稱',
              child: DropdownButtonFormField<String>(
                value: _selectedPrjId,
                items: _tenders
                    .map((t) => DropdownMenuItem(value: t.prjId, child: Text(t.prjName)))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final tender = _tenders.firstWhere((t) => t.prjId == val);
                  setState(() {
                    _selectedPrjId = val;
                    _projectNameController.text = tender.prjName;
                    _districtOptions = tender.districts;
                    _selectedDistrict = tender.districts.isNotEmpty ? tender.districts.first : null;
                    _districtController.text = _selectedDistrict ?? '';
                  });
                },
                decoration: _inputDecoration(),
              ),
            ),
            // 3) 行政區 + 里別
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '行政區',
                    child: DropdownButtonFormField<String>(
                      value: _selectedDistrict,
                      items: _districtOptions
                          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() { _selectedDistrict = val; _districtController.text = val; });
                      },
                      decoration: _inputDecoration(isSpecialField: true),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildField(
                    label: '里別',
                    child: TextField(
                      controller: _villageController,
                      readOnly: true,
                      decoration: _inputDecoration(),
                    ),
                  ),
                ),
              ],
            ),
            // 4) 派工日期 / 施工期限 (同一行, 皆為日期選擇)
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '派工日期',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dispatchDateController,
                            readOnly: true,
                            decoration: _inputDecoration(hint: ''),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _pickDate(_dispatchDateController),
                          icon: const Icon(Icons.calendar_today, color: Color(0xFF003D79)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _buildField(
                    label: '施工期限',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _deadlineController,
                            readOnly: true,
                            decoration: _inputDecoration(hint: ''),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _pickDate(_deadlineController),
                          icon: const Icon(Icons.calendar_today, color: Color(0xFF003D79)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 5) 施工日期 / 完工日期 (同一行, 皆為日期選擇)
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '施工日期',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _workDateController,
                            readOnly: true,
                            decoration: _inputDecoration(hint: ''),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _pickDate(_workDateController),
                          icon: const Icon(Icons.calendar_today, color: Color(0xFF003D79)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _buildField(
                    label: '完工日期',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _completeDateController,
                            readOnly: true,
                            decoration: _inputDecoration(hint: ''),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _pickDate(_completeDateController),
                          icon: const Icon(Icons.calendar_today, color: Color(0xFF003D79)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 6) 施工路名
            _buildField(
              label: '施工地點',
              child: TextField(
                controller: _roadNameController,
                decoration: _inputDecoration(),
              ),
            ),
            // 7) 起點路名 + GPS
            _buildField(
              label: '施工起點',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _startRoadNameController,
                    decoration: _inputDecoration(hint: ''),
                  ),
                  Row(
                    children: [
                      const Text('GPS定位 ', style: TextStyle(color: Color(0xFF2F5597),fontWeight: FontWeight.bold)),
                      IconButton(
                        onPressed: () => _onEditGPS(_startGPSController),
                        icon: const Icon(Icons.edit, size: 20, color: Color(0xFF003D79)),
                      )
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _startGPSController,
                          readOnly: true,
                          decoration: _inputDecoration(
                            hint: '',
                            isSpecialField: true,
                          ),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero, // 移除預設 padding
                        constraints: const BoxConstraints(), // 移除預設 constraints
                        onPressed: () => _onLocateGPS(_startGPSController),
                        icon: const Icon(Icons.my_location, size: 20, color: Color(0xFF003D79)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 8) 迄點路名 + GPS
            _buildField(
              label: '施工迄點',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _endRoadNameController,
                    decoration: _inputDecoration(hint: ''),
                  ),
                  Row(
                    children: [
                      const Text('GPS定位 ', style: TextStyle(color: Color(0xFF2F5597),fontWeight: FontWeight.bold)),
                      IconButton(
                        onPressed: () => _onEditGPS(_endGPSController),
                        icon: const Icon(Icons.edit, size: 20, color: Color(0xFF003D79)),
                      )
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _endGPSController,
                          readOnly: true,
                          decoration: _inputDecoration(
                            hint: '',
                            isSpecialField: true,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _onLocateGPS(_endGPSController),
                        icon: const Icon(Icons.my_location, size: 20, color: Color(0xFF003D79)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 9) 材料 / 粒徑 (同一行，材料用下拉選單)
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '施工材料',
                    child: DropdownButtonFormField<String>(
                      value: _selectedMaterial,
                      items: _materials
                          .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedMaterial = val;
                          });
                        }
                      },
                      decoration: _inputDecoration(),
                    ),
                  ),
                ),
                Expanded(
                  child: _buildField(
                    label: '材料粒徑',
                    child: TextField(
                      controller: _particleSizeController,
                      decoration: _inputDecoration(hint: ''),
                    ),
                  ),
                ),
              ],
            ),
            // 10) 施工範圍 (長/寬)
            _buildField(
              label: '施工範圍',
              child: Row(
                children: [
                  const Text('長 ', style: TextStyle(color: Color(0xFF2F5597))),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _rangeLengthController,
                      decoration: _inputDecoration(hint: ''),
                    ),
                  ),
                  const Text(' m', style: TextStyle(color: Colors.black87)),
                  const SizedBox(width: 16),
                  const Text('寬 ', style: TextStyle(color: Color(0xFF2F5597))),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _rangeWidthController,
                      decoration: _inputDecoration(hint: ''),
                    ),
                  ),
                  const Text(' m', style: TextStyle(color: Colors.black87)),
                ],
              ),
            ),
            // 11) 深度 (刨/鋪)
            _buildField(
              label: '深度(cm)',
              child: Row(
                children: [
                  const Text('刨除 ', style: TextStyle(color: Color(0xFF2F5597))),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _cutDepthController,
                      decoration: _inputDecoration(hint: ''),
                    ),
                  ),
                  const Text(' cm', style: TextStyle(color: Colors.black87)),
                  const SizedBox(width: 16),
                  const Text('鋪設 ', style: TextStyle(color: Color(0xFF2F5597))),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _paveDepthController,
                      decoration: _inputDecoration(hint: ''),
                    ),
                  ),
                  const Text(' cm', style: TextStyle(color: Colors.black87)),
                ],
              ),
            ),
            // 12) 備註
            _buildField(
              label: '備註',
              child: TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: _inputDecoration(hint: '請輸入備註'),
              ),
            ),
            // 1. 照片(施工前) 與 (刨除後) 改成獨立欄位：
            // 照片區：先顯示本地解包＆使用者新拍，再加號
            _buildPhotoSection('照片(施工前)', _photoBefore, () => _pickPhotoDialog('施工前')),
            _buildPhotoSection('照片(刨除後)', _photoCut,    () => _pickPhotoDialog('刨除後')),
            _buildPhotoSection('照片(施工中)', _photoDuring, () => _pickPhotoDialog('施工中')),
            _buildPhotoSection('照片(施工後)', _photoAfter,  () => _pickPhotoDialog('施工後')),
            _buildPhotoSection('照片(其他)',   _photoOthers, () => _pickPhotoDialog('其他')),
            const SizedBox(height: 24),
            // 18) 儲存上傳按鈕
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _onSaveUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003D79),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  '儲存上傳',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------ 共用：欄位容器 ------------------
  /// 改寫後的 _buildPhotoSection：
  /// - files: 圖片檔案列表
  /// - onTapAdd: 點「+」時呼叫
  Widget _buildPhotoSection(String label, List<File> files, VoidCallback onTapAdd) {
    return _buildField(
      label: label,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // 先渲染每張圖，並加上刪除按鈕
          for (int i = 0; i < files.length; i++)
            Stack(
              children: [
                // 圖片本身
                Image.file(files[i], height: 60, width: 60, fit: BoxFit.cover),
                // 右上角的「X」
                Positioned(
                  right: -4,
                  top: -4,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        files.removeAt(i);
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          // 最後一格永遠是一個「+」按鈕
          InkWell(
            onTap: onTapAdd,
            child: Container(
              width: 60, height: 60,
              color: Colors.grey[300],
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
    Color bgColor = Colors.transparent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2F5597),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  // ------------------ 共用：拍照欄位 ------------------
  Widget _buildPhotoField({
    required String label,
    required File? file,
    required VoidCallback onTap,
  }) {
    return _buildField(
      label: label,
      child: Row(
        children: [
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
          ),
          const SizedBox(width: 8),
          if (file != null)
            Image.file(file, height: 60)
          else
            const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // ------------------ 共用：輸入框樣式 ------------------
  InputDecoration _inputDecoration({String? hint, bool isSpecialField = false}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      fillColor: isSpecialField ? const Color(0xFFDAE3F3) : const Color(0xFFD9D9D9),
      filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
