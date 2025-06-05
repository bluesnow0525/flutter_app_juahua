import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:convert'; // 用於 UTF8 解碼與 Base64
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:http_parser/http_parser.dart';
import 'package:xml/xml.dart' as xml;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'dart:async'; // for TimeoutException

import '../components/upload_record.dart';
import '../components/upload_services.dart';
import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';
import 'map_picker_page.dart';
import './inspection_list.dart';
import '../components/config.dart';

class Tender {
  final String prjId;
  final String prjName;
  final List<String> districts;
  Tender({
    required this.prjId,
    required this.prjName,
    required this.districts,
  });
  factory Tender.fromJson(Map<String, dynamic> json) {
    // cast 之後 toSet() 去重，再轉回 List
    final raw = (json['districts'] as List<dynamic>).cast<String>();
    final deduped = raw.toSet().toList();
    return Tender(
      prjId: json['prjId'] as String,
      prjName: json['prjName'] as String,
      districts: deduped,
    );
  }
}

class InspectionFormPage extends StatefulWidget {
  const InspectionFormPage({Key? key}) : super(key: key);

  @override
  _InspectionFormPageState createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends State<InspectionFormPage> {
  // ------------------ 控制器 ------------------
  final TextEditingController _caseIdController = TextEditingController();    // 案件編號 (唯讀)
  final TextEditingController _dateController = TextEditingController();      // 巡修日期
  String _amPmValue = '上午';                                                  // 時段(上/下午)
  String _weatherValue = '晴';                                                 // 天氣
  final TextEditingController _villageController = TextEditingController();   // 里別（自動填入且 read only）
  final TextEditingController _addressController = TextEditingController();   // 地址
  final TextEditingController _gpsController = TextEditingController();       // GPS定位

  List<Tender> _tenders = [];
  String?      _selectedPrjId;
  List<String> _districtOptions = [];
  String?      _selectedDistrict;

  // 巡查照片
  File? _inspectionPhoto;

  // 破壞範圍(長、寬)
  final TextEditingController _damageLengthController = TextEditingController();
  final TextEditingController _damageWidthController = TextEditingController();
  // 破壞類型
  String _damageTypeValue = '坑洞';
  // 備註
  final TextEditingController _descriptionController = TextEditingController();

  // ------------------ 施工回填 ------------------
  bool _enableFill = false; // 是否勾選「施工回填」
  final TextEditingController _fillLengthController = TextEditingController();
  final TextEditingController _fillWidthController = TextEditingController();
  String _materialValue = '高性能常溫瀝青（包）';
  final List<String> _materialOptions = [
    '高性能常溫瀝青（包）',
    '熱料（包）',
  ];
  final TextEditingController _materialQtyController = TextEditingController();
  // 三張照片：施工前、施工中、施工後
  File? _photoBeforeFill;
  File? _photoDuring;
  File? _photoAfter;

  // ─── 編輯模式控制 & 初始 URL ──────────────────────
  bool _isEditing = false;
  Object? _cachedArgs;
  bool _hasInitFromArgs = false;
  int? _editItemId;
  String? _initialInspectionPhotoUrl;
  String? _initialPhotoBeforeUrl;
  String? _initialPhotoDuringUrl;
  String? _initialPhotoAfterUrl;

  Uint8List? _inspectionPhotoBytes;
  Uint8List? _beforePhotoBytes;
  Uint8List? _duringPhotoBytes;
  Uint8List? _afterPhotoBytes;

  Map<String, String>? _origFilePathMap;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);

    // 模擬測試：案件編號唯讀，預設為空
    _caseIdController.text = '';
    // 預設今天
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // // 讀取記憶資料：時段 & 天氣 & 地址 & 里別
    _amPmValue    = appState.inspectionForm['amPmValue']   ?? '上午';
    _weatherValue = appState.inspectionForm['weatherValue'] ?? '晴';
    _addressController.text = appState.inspectionForm['address'] ?? '';
    // _villageController.text = appState.inspectionForm['village'] ?? '';

    // 抓標案列表，並根據記憶還原選擇
    _fetchTenders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只第一輪進來時取一次 args 不動它
    if (_cachedArgs == null) {
      _cachedArgs = ModalRoute.of(context)?.settings.arguments;
    }
  }

  void _applyArgs(Object? args) {
    if (args is InspectionItem) {
      _isEditing = true;
      _editItemId = args.id;
      _initialInspectionPhotoUrl = args.photoUrl.isNotEmpty ? args.photoUrl : null;
      _initialPhotoBeforeUrl = args.photoBefore;
      _initialPhotoDuringUrl = args.photoDuring;
      _initialPhotoAfterUrl = args.photoAfter;

      // 找到對應的標案與行政區
      _selectedPrjId = args.person;
      final tender = _tenders.firstWhere(
              (t) => t.prjId == _selectedPrjId, orElse: () => _tenders.first);
      final deduped = tender.districts.toSet().toList();
      final initialDistrict = deduped.contains(args.district)
          ? args.district
          : (deduped.isNotEmpty ? deduped.first : null);

      setState(() {
        _districtOptions = deduped;
        _selectedDistrict = initialDistrict;

        _caseIdController.text = args.caseNum;
        _dateController.text = DateFormat('yyyy-MM-dd').format(args.recordDate);
        _amPmValue = args.period;
        _weatherValue = args.weather;
        _gpsController.text = '${args.longitude}, ${args.latitude}';
        _villageController.text = args.village;
        _addressController.text = args.address;
        _damageTypeValue = args.damageType;
        _damageLengthController.text = args.damageLength.toString();
        _damageWidthController.text = args.damageWidth.toString();
        _descriptionController.text = args.remark;
        _enableFill = args.material != null;
        if (_enableFill) {
          _fillLengthController.text = args.refillLength?.toString() ?? '';
          _fillWidthController.text = args.refillWidth?.toString() ?? '';
          _materialValue = _materialOptions.firstWhere(
                (opt) => opt.contains(args.material ?? '') ||
                (args.material ?? '').contains(opt),
            orElse: () => _materialOptions.first,
          );
          _materialQtyController.text = args.quantity?.toString() ?? '';
        }
      });

      // 下載舊有 4 張網路圖到 /tmp
      _initOrigFilePathMapFromUrls();
    }
    else if (args is UploadRecord) {
      _isEditing = args.body['ID'] != null;
      _editItemId = int.tryParse(args.body['ID']?.toString() ?? '');
      _origFilePathMap = args.filePathMap;

      final m = args.body;
      setState(() {
        _caseIdController.text = m['case_num']?.toString() ?? '';
        _selectedPrjId = m['PRJ_ID']?.toString();
        final tender = _tenders.firstWhere(
                (t) => t.prjId == _selectedPrjId, orElse: () => _tenders.first);
        _districtOptions = tender.districts.toSet().toList();
        _selectedDistrict = m['DISTRICT']?.toString();
        _dateController.text = m['SURVEY_DATE']?.toString() ?? _dateController.text;
        _amPmValue = m['PERIOD']?.toString() ?? _amPmValue;
        _weatherValue = m['WEATHER']?.toString() ?? _weatherValue;
        _gpsController.text = '${m['LNG']}, ${m['LAT']}';
        _villageController.text = m['CAVLGE']?.toString() ?? '';
        _addressController.text = m['ADDRESS']?.toString() ?? '';
        _damageTypeValue = m['DTYPE']?.toString() ?? _damageTypeValue;
        _damageLengthController.text = m['DTYPE_LENGTH']?.toString() ?? '';
        _damageWidthController.text = m['DTYPE_WIDTH']?.toString() ?? '';
        _descriptionController.text = m['REMARK']?.toString() ?? '';
        if (m['TYPE'] == 'RB') {
          _enableFill = true;
          _fillLengthController.text = m['REFILL_LENGTH']?.toString() ?? '';
          _fillWidthController.text = m['REFILL_WIDTH']?.toString() ?? '';
          _materialValue = _materialOptions.firstWhere(
                (opt) => opt.contains(m['MATERIAL']?.toString() ?? '') ||
                (m['MATERIAL']?.toString() ?? '').contains(opt),
            orElse: () => _materialOptions.first,
          );
          _materialQtyController.text = m['QUANTITY']?.toString() ?? '';
        }
      });

      // 圖片回填：優先 filePathMap，否則 decode base64
      if (args.filePathMap != null && args.filePathMap!.isNotEmpty) {
        args.filePathMap!.forEach((name, path) {
          final f = File(path);
          if (name == 'inspection.jpg') _inspectionPhoto = f;
          if (name == 'before.jpg')     _photoBeforeFill = f;
          if (name == 'during.jpg')     _photoDuring    = f;
          if (name == 'after.jpg')      _photoAfter     = f;
        });
      } else {
        void decode(String? s, void Function(Uint8List) assign) {
          if (s != null && s.isNotEmpty) {
            try { assign(base64Decode(s)); } catch (_) {}
          }
        }
        decode(m['IMG'] as String?,       (b) => _inspectionPhotoBytes = b);
        decode(m['IMG_BEFORE'] as String?, (b) => _beforePhotoBytes      = b);
        decode(m['IMG_DURING'] as String?, (b) => _duringPhotoBytes      = b);
        decode(m['IMG_AFTER'] as String?,  (b) => _afterPhotoBytes       = b);
      }
    }
    else {
      // 無 args 時，保持 initState 內已有的記憶 & GPS 自動機制
      final mem = Provider.of<AppState>(context, listen: false).inspectionForm;
      _amPmValue = mem['amPmValue']   ?? _amPmValue;
      _weatherValue = mem['weatherValue'] ?? _weatherValue;
      _addressController.text = mem['address'] ?? _addressController.text;
      _villageController.text = mem['village'] ?? _villageController.text;
      print('6');
      _fetchVillageName();
    }
  }

  /// 下載 args 傳入的 URL 圖片到 /tmp，並填 _origFilePathMap
  /// 下載 args 傳入的 URL 圖片到 /tmp，並填 _origFilePathMap
  Future<void> _initOrigFilePathMapFromUrls() async {
    final tempMap = <String,String>{};
    final urlMap = {
      'inspection.jpg': _initialInspectionPhotoUrl,
      'before.jpg':     _initialPhotoBeforeUrl,
      'during.jpg':     _initialPhotoDuringUrl,
      'after.jpg':      _initialPhotoAfterUrl,
    };
    final futures = urlMap.entries.map((e) async {
      final key = e.key, url = e.value;
      if (url == null || url.isEmpty) return;
      try {
        final resp = await http.get(Uri.parse(url))
            .timeout(Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final file = File('${Directory.systemTemp.path}/$key');
          await file.writeAsBytes(resp.bodyBytes);
          tempMap[key] = file.path;
        }
      } catch (_) { /* 忽略 */ }
    });
    await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      _origFilePathMap = tempMap;
    });
  }

  Future<void> _fetchTenders() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final token = appState.token;
    final savedProjectName = appState.inspectionForm['projectName'] as String?;
    final savedDistrict    = appState.inspectionForm['district']    as String?;

    final resp = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/get/tender'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode == 200) {
      final list = (jsonDecode(resp.body)['data'] as List)
          .map((e) => Tender.fromJson(e)).toList();
      if (list.isNotEmpty) {
        final chosenTender = savedProjectName != null
            ? list.firstWhere((t) => t.prjName == savedProjectName,
            orElse: () => list.first)
            : list.first;
        final chosenDistrict = savedDistrict != null &&
            chosenTender.districts.contains(savedDistrict)
            ? savedDistrict
            : (chosenTender.districts.isNotEmpty
            ? chosenTender.districts.first
            : null);

        setState(() {
          _tenders = list;
          _selectedPrjId = chosenTender.prjId;
          _districtOptions = chosenTender.districts.toSet().toList();
          _selectedDistrict = chosenDistrict;
        });

        // 取得完標案後，才真正回填 args
        if (!_hasInitFromArgs) {
          _applyArgs(_cachedArgs);   // _cachedArgs 可能是 null，就會走到 else { print('6'); ... }
          _hasInitFromArgs = true;
        }
      }
    } else {
      // TODO: 處理錯誤
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('取得標案失敗'),
          content: Text('伺服器回傳狀態：${resp.statusCode}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _caseIdController.dispose();
    _dateController.dispose();
    _villageController.dispose();
    _addressController.dispose();
    _gpsController.dispose();
    _damageLengthController.dispose();
    _damageWidthController.dispose();
    _descriptionController.dispose();
    _fillLengthController.dispose();
    _fillWidthController.dispose();
    _materialQtyController.dispose();
    super.dispose();
  }

  // ------------------ 選擇日期 ------------------
  Future<void> _pickDate() async {
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
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // ------------------ 實際拍照/選圖功能 ------------------
  Future<void> _pickPhotoDialog(String title) async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Text('選擇來源'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final XFile? file = await _picker.pickImage(source: ImageSource.camera);
              if (file != null) {
                setState(() {
                  _assignPickedFile(title, File(file.path));
                });
              }
            },
            child: const Text('拍照'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
              if (file != null) {
                setState(() {
                  _assignPickedFile(title, File(file.path));
                });
              }
            },
            child: const Text('相簿'),
          ),
        ],
      ),
    );
  }

  // 根據 title 將選取的圖片存入對應變數
  void _assignPickedFile(String title, File file) {
    if (title == '巡查照片') {
      _inspectionPhoto = file;
    } else if (title == '施工前') {
      _photoBeforeFill = file;
    } else if (title == '施工中') {
      _photoDuring = file;
    } else if (title == '施工後') {
      _photoAfter = file;
    }
  }

  // ------------------ 使用 GPS 取得目前位置後呼叫 API 取得里別資訊 ------------------
  Future<void> _fetchVillageName() async {
    try {
      // 檢查並請求定位權限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        return; // 權限未授予，直接退出
      }

      // 取得目前位置（高精度）
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() {
        _gpsController.text = '${pos.longitude.toStringAsFixed(6)}, ${pos.latitude.toStringAsFixed(6)}';
      });

      // 呼叫國土API
      final url = 'https://api.nlsc.gov.tw/other/TownVillagePointQuery/${pos.longitude}/${pos.latitude}/4326';
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final decodedXml = utf8.decode(response.bodyBytes);
        final document = xml.XmlDocument.parse(decodedXml);
        final villageElements = document.findAllElements('villageName');

        if (villageElements.isNotEmpty) {
          final villageName = villageElements.first.text;
          if (!mounted) return;
          setState(() {
            _villageController.text = villageName;
          });
          Provider.of<AppState>(context, listen: false)
              .setInspectionFormValue('village', villageName);
        }
      }
    } catch (e) {
      // 出錯也不要用 setState
      debugPrint('取得里別資訊時發生錯誤: $e');
    }
  }
  Future<void> _fetchVillageNameAt(double lng, double lat) async {
    try {
      final url = 'https://api.nlsc.gov.tw/other/TownVillagePointQuery/$lng/$lat/4326';
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final decodedXml = utf8.decode(response.bodyBytes);
        final document = xml.XmlDocument.parse(decodedXml);
        final elems = document.findAllElements('villageName');

        if (elems.isNotEmpty) {
          final villageName = elems.first.text;
          if (!mounted) return;
          setState(() {
            _villageController.text = villageName;
          });
          Provider.of<AppState>(context, listen: false)
              .setInspectionFormValue('village', villageName);
        }
      }
    } catch (e) {
      debugPrint('查里別例外：$e');
    }
  }

  // ------------------ 壓縮圖片 (確保每張圖片不超過 1MB) ------------------
  Future<String> _encodeImageBase64(File? file) async {
    if (file == null) return '';
    Uint8List? compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      quality: 85,
    );
    if (compressed != null && compressed.lengthInBytes > 1024 * 1024) {
      compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        quality: 70,
      );
    }
    return compressed != null ? base64Encode(compressed) : '';
  }

  // ------------------ 收集表單資料並上船 ------------------
//   /// 上傳巡修單（符合後端 API 格式）
//   Future<void> _uploadData() async {
//     final appState = Provider.of<AppState>(context, listen: false);
//     final token = appState.token;
//
//     // 1️⃣ 當下時間
//     String surveyDate = _dateController.text.isNotEmpty
//         ? _dateController.text           // 格式已是 "yyyy-MM-dd"
//         : DateFormat('yyyy-MM-dd').format(DateTime.now());
//
//     // 2️⃣ 解析經緯度
//     String lng = '', lat = '';
//     if (_gpsController.text.contains(',')) {
//       final parts = _gpsController.text.split(',');
//       lng = parts[0].trim();
//       lat = parts[1].trim();
//     }
//
//     // 3️⃣ 建立符合後端的參數 map
//     Map<String, dynamic> body = {
//       'PRJ_ID': _selectedPrjId ?? '',
//       'TYPE': _enableFill ? 'RB' : 'RA',
//       'SURVEY_DATE': surveyDate,
//       'PERIOD': _amPmValue,
//       'WEATHER': _weatherValue,
//       'DTYPE': _damageTypeValue,
//       'DTYPE_LENGTH': _damageLengthController.text,
//       'DTYPE_WIDTH': _damageWidthController.text,
//       'DISTRICT': _selectedDistrict ?? '',
//       'CAVLGE': _villageController.text,
//       'ADDRESS': _addressController.text,
//       'LNG': lng,
//       'LAT': lat,
//       'REMARK': _descriptionController.text,
//     };
//
// // 只有勾選「施工回填」時，才加入這些欄位
//     if (_enableFill) {
//       body.addAll({
//         'REFILL_LENGTH': _fillLengthController.text,
//         'REFILL_WIDTH':  _fillWidthController.text,
//         'MATERIAL':      _materialValue,
//         'QUANTITY':      _materialQtyController.text,
//       });
//     }
//
//     // 圖片 Base64
//     if (!_isEditing || _inspectionPhoto != null) {
//       body['IMG'] = await _encodeImageBase64(_inspectionPhoto);
//     }
//     if (_enableFill) {
//       if (!_isEditing || _photoBeforeFill != null) {
//         body['IMG_BEFORE'] = await _encodeImageBase64(_photoBeforeFill);
//       }
//       if (!_isEditing || _photoDuring != null) {
//         body['IMG_DURING'] = await _encodeImageBase64(_photoDuring);
//       }
//       if (!_isEditing || _photoAfter != null) {
//         body['IMG_AFTER'] = await _encodeImageBase64(_photoAfter);
//       }
//     }
//
//     final baseUrl = 'http://211.23.157.201/api/app/workorder/maintenance';
//     late http.Response response;
//
//     if (_isEditing) {
//       // ─── PATCH 更新模式 ───────────────────────────────────────
//       final archive = Archive();
//       void addFileToArchive(File? file, String name) {
//         if (file != null) {
//           final bytes = file.readAsBytesSync();
//           archive.addFile(ArchiveFile(name, bytes.length, bytes));
//         }
//       }
//       addFileToArchive(_inspectionPhoto, 'inspection.jpg');
//       addFileToArchive(_photoBeforeFill, 'before.jpg');
//       addFileToArchive(_photoDuring, 'during.jpg');
//       addFileToArchive(_photoAfter, 'after.jpg');
//       final zipData = ZipEncoder().encode(archive)!;
//
//       final uri = Uri.parse(baseUrl);
//       final req = http.MultipartRequest('PATCH', uri)
//         ..headers['Authorization'] = 'Bearer $token';
//
//       // 加入文字欄位
//       req.fields['ID'] = _editItemId?.toString() ?? '';
//       req.fields['PRJ_ID'] = _selectedPrjId ?? '';
//       req.fields['TYPE'] = _enableFill ? 'RB' : 'RA';
//       req.fields['SURVEY_DATE'] = surveyDate;
//       req.fields['PERIOD'] = _amPmValue;
//       req.fields['WEATHER'] = _weatherValue;
//       req.fields['DTYPE'] = _damageTypeValue;
//       req.fields['DTYPE_LENGTH'] = _damageLengthController.text;
//       req.fields['DTYPE_WIDTH'] = _damageWidthController.text;
//       req.fields['DISTRICT'] = _selectedDistrict ?? '';
//       req.fields['CAVLGE'] = _villageController.text;
//       req.fields['ADDRESS'] = _addressController.text;
//       req.fields['LNG'] = lng;
//       req.fields['LAT'] = lat;
//       req.fields['REMARK'] = _descriptionController.text;
//       if (_enableFill) {
//         req.fields['REFILL_LENGTH'] = _fillLengthController.text;
//         req.fields['REFILL_WIDTH'] = _fillWidthController.text;
//         req.fields['MATERIAL'] = _materialValue;
//         req.fields['QUANTITY'] = _materialQtyController.text;
//       }
//
//       // 加入 ZIP 檔
//       req.files.add(
//         http.MultipartFile.fromBytes(
//           'IMG_ZIP',
//           zipData,
//           filename: 'images.zip',
//           contentType: MediaType('application', 'zip'),
//         ),
//       );
//
//       final streamed = await req.send();
//       final resp = await http.Response.fromStream(streamed);
//
//       if (resp.statusCode == 200) {
//         showDialog(
//           context: context,
//           builder: (_) => AlertDialog(
//             title: const Text('上傳成功'),
//             content: const Text('巡修單已成功更新'),
//             actions: [
//               TextButton(onPressed: () => Navigator.pop(context), child: const Text('確定')),
//             ],
//           ),
//         );
//       } else {
//         // debug 輸出文字欄位 & 檔案
//         final fieldsDebug = req.fields.entries
//             .map((e) => '${e.key}: ${e.value}')
//             .join('\n');
//         final filesDebug = req.files.map((f) => f.filename).join(', ');
//
//         showDialog(
//           context: context,
//           builder: (_) => AlertDialog(
//             title: const Text('更新失敗'),
//             content: SingleChildScrollView(
//               child: Text(
//                 '狀態碼：${resp.statusCode}\n'
//                     '回傳 Body：\n${resp.body}\n\n'
//                     '上傳的文字欄位：\n$fieldsDebug\n\n'
//                     '上傳的檔案：\n$filesDebug',
//               ),
//             ),
//             actions: [
//               TextButton(onPressed: () => Navigator.pop(context), child: const Text('確定')),
//             ],
//           ),
//         );
//       }
//     } else {
//       // ─── POST 新增模式 ────────────────────────────────────────
//       final requestJson = jsonEncode(body);
//       response = await http.post(
//         Uri.parse(baseUrl),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $token',
//         },
//         body: requestJson,
//       );
//
//       final Map<String, dynamic> respJson = jsonDecode(response.body);
//       if (response.statusCode == 200 && respJson['status'] == true) {
//         showDialog(
//           context: context,
//           builder: (_) => AlertDialog(
//             title: const Text('上傳成功'),
//             content: const Text('巡修單已成功上傳'),
//             actions: [
//               TextButton(onPressed: () => Navigator.pop(context), child: const Text('確定')),
//             ],
//           ),
//         );
//       } else {
//         showDialog(
//           context: context,
//           builder: (_) => AlertDialog(
//             title: const Text('上傳失敗'),
//             content: SingleChildScrollView(
//               child: Text(
//                 '狀態碼：${response.statusCode}\n'
//                     '回傳 Body：\n${response.body}',
//               ),
//             ),
//             actions: [
//               TextButton(onPressed: () => Navigator.pop(context), child: const Text('確定')),
//             ],
//           ),
//         );
//       }
//     }
//   }
//
//   // ------------------ 上傳資料按鈕觸發 ------------------
//   void _onSaveUpload() {
//     _uploadData();
//   }
  Future<void> _onSaveUpload() async {
    // ---- 1️⃣ 欄位檢查 ----
    final List<String> missingFields = [];

    // 1) PRJ_ID（標案名稱）
    if (_selectedPrjId == null || _selectedPrjId!.isEmpty) {
      missingFields.add('標案名稱');
    }
    // 2) TYPE（巡修單類型，自動透過 _enableFill 判斷，不須另外檢查）
    //    如果未選擇 _enableFill，TYPE 依舊會有預設值 'RA' 或 'RB'，因此不用另外檢查 TYPE 本身

    // 3) SURVEY_DATE（巡修日期）
    if (_dateController.text.trim().isEmpty) {
      missingFields.add('巡修日期');
    }
    // 4) PERIOD（時段）
    if (_amPmValue.trim().isEmpty) {
      missingFields.add('時段');
    }
    // 5) WEATHER（天氣）
    if (_weatherValue.trim().isEmpty) {
      missingFields.add('天氣');
    }
    // 6) DTYPE（破壞類型）
    if (_damageTypeValue.trim().isEmpty) {
      missingFields.add('破壞類型');
    }
    // 7) DISTRICT（行政區）
    if (_selectedDistrict == null || _selectedDistrict!.isEmpty) {
      missingFields.add('行政區');
    }
    // 8) CAVLGE（里別）
    if (_villageController.text.trim().isEmpty) {
      missingFields.add('里別');
    }
    // 9) ADDRESS（地址）
    if (_addressController.text.trim().isEmpty) {
      missingFields.add('地址');
    }
    // 10) LNG / LAT（GPS 定位，需同時有經度與緯度）
    final gpsText = _gpsController.text.trim();
    if (gpsText.isEmpty || !gpsText.contains(',') || gpsText.split(',').length < 2) {
      missingFields.add('GPS 定位');
    } else {
      // 再確認能否解析成數字
      final parts = gpsText.split(',');
      final lng = double.tryParse(parts[0].trim());
      final lat = double.tryParse(parts[1].trim());
      if (lng == null || lat == null) {
        missingFields.add('GPS 定位');
      }
    }

    // 11) 根據 TYPE 類型額外檢查
    //    TYPE == 'RA'（_enableFill == false）時，需檢查 IMG（巡查照片）必填
    if (!_enableFill) {
      final hasInspectionImage = _inspectionPhoto != null ||
          _inspectionPhotoBytes != null ||
          _initialInspectionPhotoUrl != null;
      if (!hasInspectionImage) {
        missingFields.add('巡查照片');
      }
    }
    //    TYPE == 'RB'（_enableFill == true）時，需檢查 MATERIAL（施工材料）與 IMG_AFTER（施工後照片）必填
    if (_enableFill) {
      if (_materialValue.trim().isEmpty) {
        missingFields.add('施工材料');
      }
      final hasAfterImage = _photoAfter != null ||
          _afterPhotoBytes != null ||
          _initialPhotoAfterUrl != null;
      if (!hasAfterImage) {
        missingFields.add('施工後照片');
      }
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
    if (_isEditing) {
      // 如果还没下载初始四张图，就先下载
      if (_origFilePathMap == null || _origFilePathMap!.isEmpty) {
        await _initOrigFilePathMapFromUrls();
      }

      // 1️⃣ 准备文字字段
      final fields = <String, dynamic>{
        'case_num':      _caseIdController.text,
        'ID':            _editItemId?.toString() ?? '',
        'PRJ_ID':        _selectedPrjId ?? '',
        'TYPE':          _enableFill ? 'RB' : 'RA',
        'SURVEY_DATE':   _dateController.text,
        'PERIOD':        _amPmValue,
        'WEATHER':       _weatherValue,
        'DTYPE':         _damageTypeValue,
        'DTYPE_LENGTH':  _damageLengthController.text,
        'DTYPE_WIDTH':   _damageWidthController.text,
        'DISTRICT':      _selectedDistrict ?? '',
        'CAVLGE':        _villageController.text,
        'ADDRESS':       _addressController.text,
        'LNG':           _gpsController.text.split(',')[0].trim(),
        'LAT':           _gpsController.text.split(',')[1].trim(),
        'REMARK':        _descriptionController.text,
      };
      if (_enableFill) {
        fields.addAll({
          'REFILL_LENGTH': _fillLengthController.text,
          'REFILL_WIDTH':  _fillWidthController.text,
          'MATERIAL':      _materialValue,
          'QUANTITY':      _materialQtyController.text,
        });
      }

      // 2️⃣ 合并旧有 + 新选的文件路径
      final fileMap = <String,String>{};
      if (_origFilePathMap != null) fileMap.addAll(_origFilePathMap!);
      if (_inspectionPhoto  != null) fileMap['inspection.jpg'] = _inspectionPhoto!.path;
      if (_photoBeforeFill  != null) fileMap['before.jpg']     = _photoBeforeFill!.path;
      if (_photoDuring      != null) fileMap['during.jpg']     = _photoDuring!.path;
      if (_photoAfter       != null) fileMap['after.jpg']      = _photoAfter!.path;

      final rec = UploadRecord(
        body:      fields,
        isEditing: true,
        filePathMap: fileMap,
      );
      UploadService.enqueue(context, rec);
    } else {
      // ── 新增模式 ──
      final body = <String, dynamic>{
        'PRJ_ID':       _selectedPrjId ?? '',
        'TYPE':         _enableFill ? 'RB' : 'RA',
        'SURVEY_DATE':  _dateController.text,
        'PERIOD':       _amPmValue,
        'WEATHER':      _weatherValue,
        'DTYPE':        _damageTypeValue,
        'DTYPE_LENGTH': _damageLengthController.text,
        'DTYPE_WIDTH':  _damageWidthController.text,
        'DISTRICT':     _selectedDistrict ?? '',
        'CAVLGE':       _villageController.text,
        'ADDRESS':      _addressController.text,
        'LNG':          (_gpsController.text.split(',')[0]).trim(),
        'LAT':          (_gpsController.text.split(',')[1]).trim(),
        'REMARK':       _descriptionController.text,
        if (_enableFill) ...{
          'REFILL_LENGTH': _fillLengthController.text,
          'REFILL_WIDTH':  _fillWidthController.text,
          'MATERIAL':      _materialValue,
          'QUANTITY':      _materialQtyController.text,
        },
      };

      // 圖片 Base64（保留在 body 裡，uploadservice JSON POST 時用）
      body['IMG'] = await _encodeImageBase64(_inspectionPhoto);
      if (_enableFill) {
        body['IMG_BEFORE'] = await _encodeImageBase64(_photoBeforeFill);
        body['IMG_DURING'] = await _encodeImageBase64(_photoDuring);
        body['IMG_AFTER']  = await _encodeImageBase64(_photoAfter);
      }

      // **重點：把檔案路徑也存起來，讓後續編輯能打包 ZIP**
      final filePathMap = <String, String>{};
      if (_inspectionPhoto   != null) filePathMap['inspection.jpg'] = _inspectionPhoto!.path;
      if (_photoBeforeFill   != null) filePathMap['before.jpg']     = _photoBeforeFill!.path;
      if (_photoDuring       != null) filePathMap['during.jpg']     = _photoDuring!.path;
      if (_photoAfter        != null) filePathMap['after.jpg']      = _photoAfter!.path;

      final rec = UploadRecord(
        body: body,
        isEditing: false,
        filePathMap: filePathMap,  // ← 一定要給它
      );
      UploadService.enqueue(context, rec);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入上傳佇列，背景上傳中')),
    );

    Navigator.pushReplacementNamed(context, '/uploadList');
  }

  @override
  Widget build(BuildContext context) {
    // 從 Provider 取得 AppState（若需要即時更新 state 可取得）
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppHeader(),
      endDrawer: MyEndDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '巡修單',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF30475E),
                ),
              ),
            ),
            // 1) 案件編號 (唯讀)
            _buildField(
              label: '案件編號',
              child: TextField(
                controller: _caseIdController,
                readOnly: true,
                decoration: _inputDecoration(isSpecialField: true),
              ),
            ),
            // 2) 巡修日期 (含日曆 icon)
            _buildField(
              label: '巡修日期',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateController,
                      readOnly: true,
                      decoration: _inputDecoration(),
                    ),
                  ),
                  IconButton(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, color: Color(0xFF003D79)),
                  ),
                ],
              ),
            ),
            // 3) 時段 + 天氣 (同一欄)
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '時段',
                    child: DropdownButtonFormField<String>(
                      value: _amPmValue,
                      items: ['上午', '下午']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _amPmValue = val);
                          appState.setInspectionFormValue('amPmValue', val);
                        }
                      },
                      decoration: _inputDecoration(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildField(
                    label: '天氣',
                    child: DropdownButtonFormField<String>(
                      value: _weatherValue,
                      items: ['晴', '陰', '雨']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _weatherValue = val);
                          appState.setInspectionFormValue('weatherValue', val);
                        }
                      },
                      decoration: _inputDecoration(),
                    ),
                  ),
                ),
              ],
            ),
            // 4) 標案名稱
            _buildField(
              label: '標案名稱',
              child: DropdownButtonFormField<String>(
                value: _selectedPrjId,
                items: _tenders.map((t) =>
                    DropdownMenuItem(value: t.prjId, child: Text(t.prjName))
                ).toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final tender = _tenders.firstWhere((t) => t.prjId == val);
                  setState(() {
                    _selectedPrjId = tender.prjId;
                    // 這裡也 toSet()
                    _districtOptions = tender.districts.toSet().toList();
                    _selectedDistrict = _districtOptions.isNotEmpty ? _districtOptions.first : null;
                  });
                  // … 存到 AppState …
                },
                decoration: _inputDecoration(),
              ),
            ),
            // 5) 行政區 + 里別
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '行政區',
                    child: DropdownButtonFormField<String>(
                      value: _selectedDistrict,
                      items: _districtOptions.map((d) =>
                          DropdownMenuItem(value: d, child: Text(d))
                      ).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => _selectedDistrict = val);
                        // 存到 AppState
                        appState.setInspectionFormValue('district', val);
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
            // 6) GPS定位
            _buildField(
              label: 'GPS定位',
              labelAction: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.edit, size: 20, color: Color(0xFF003D79)),
                onPressed: () async {
                  LatLng? initPos;
                  // 如果欄位裡已經有「lng, lat」，就當作初始座標
                  if (_gpsController.text.contains(',')) {
                    final parts = _gpsController.text.split(',');
                    final lng = double.tryParse(parts[0].trim());
                    final lat = double.tryParse(parts[1].trim());
                    if (lng != null && lat != null) {
                      initPos = LatLng(lat, lng);
                    }
                  }
                  // 跳到地圖選點頁面，帶入初始座標
                  final result = await Navigator.push<LatLng>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapPickerPage(initialPosition: initPos),
                    ),
                  );
                  if (result != null) {
                    setState(() {
                      // 經度, 緯度
                      _gpsController.text =
                      '${result.longitude.toStringAsFixed(6)}, ${result.latitude.toStringAsFixed(6)}';
                    });
                    // 反查里別
                    await _fetchVillageNameAt(result.longitude, result.latitude);
                  }
                },
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _gpsController,
                      readOnly: true,
                      decoration: _inputDecoration(isSpecialField: true),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.my_location, color: Color(0xFF003D79)),
                    onPressed: () async {
                      try {
                        LocationPermission permission =
                        await Geolocator.checkPermission();
                        if (permission == LocationPermission.denied ||
                            permission == LocationPermission.deniedForever) {
                          permission = await Geolocator.requestPermission();
                        }
                        if (permission == LocationPermission.whileInUse ||
                            permission == LocationPermission.always) {
                          Position pos = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high);
                          setState(() {
                            _gpsController.text =
                            '${pos.longitude.toStringAsFixed(6)}, ${pos.latitude.toStringAsFixed(6)}';
                          });
                          await _fetchVillageNameAt(pos.longitude, pos.latitude);
                        } else {
                          print("定位權限未授予");
                        }
                      } catch (e) {
                        print("取得定位時發生錯誤: $e");
                      }
                    },
                  ),
                ],
              ),
            ),
            // 7) 地址
            _buildField(
              label: '地址',
              child: TextField(
                controller: _addressController,
                decoration: _inputDecoration(),
              ),
            ),
            // 8) 破壞類型
            _buildField(
              label: '破壞類型',
              child: DropdownButtonFormField<String>(
                value: _damageTypeValue,
                items: [
                  '坑洞','龜裂','下陷','掏空','管線回填','補綻','人手孔','車轍','車道與路肩高差','縱橫向裂縫',
                  '塊狀裂縫','邊緣裂縫','反射裂縫','滑動裂縫','粒料光滑','跨越鐵道','波浪型鋪面','凸起',
                  '推擠','隆起','剝脫','風化','冒油'
                ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _damageTypeValue = val);
                },
                decoration: _inputDecoration(),
              ),
            ),
            // 9) 破壞範圍
            _buildField(
              label: '破壞範圍(長/寬)',
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Text('長', style: TextStyle(color: Colors.black87)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _damageLengthController,
                            decoration: _inputDecoration(hint: ''),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('m', style: TextStyle(color: Colors.black87)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        const Text('寬', style: TextStyle(color: Colors.black87)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _damageWidthController,
                            decoration: _inputDecoration(hint: ''),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('m', style: TextStyle(color: Colors.black87)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 10) 備註
            _buildField(
              label: '備註',
              child: TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: _inputDecoration(),
              ),
            ),
            // 11) 巡查照片
            _buildField(
              label: '巡查照片',
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      _pickPhotoDialog('巡查照片');
                    },
                    icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                  ),
                  // const SizedBox(width: 8),
                  // if (_inspectionPhoto != null)
                  //   Image.file(_inspectionPhoto!, height: 60)
                  // else if (_initialInspectionPhotoUrl != null)
                  //   Image.network(_initialInspectionPhotoUrl!, height: 60, fit: BoxFit.cover)
                  // else
                  //   const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey)),
                  const SizedBox(width: 8),
                  // 顯示順序：File > Memory > Network > 提示
                  // 巡查照片
                  if (_inspectionPhoto != null)
                    _buildRemovableImage(
                      child: Image.file(_inspectionPhoto!, height: 60, width: 60, fit: BoxFit.cover),
                      onRemove: () => setState(() { _inspectionPhoto = null; }),
                    )
                  else if (_inspectionPhotoBytes != null)
                    _buildRemovableImage(
                      child: Image.memory(_inspectionPhotoBytes!, height: 60, width: 60, fit: BoxFit.cover),
                      onRemove: () => setState(() { _inspectionPhotoBytes = null; }),
                    )
                  else if (_initialInspectionPhotoUrl != null)
                      _buildRemovableImage(
                        child: Image.network(_initialInspectionPhotoUrl!, height: 60, width: 60, fit: BoxFit.cover),
                        onRemove: () => setState(() { _initialInspectionPhotoUrl = null; }),
                      )
                  else
                    const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            // 12) 施工回填
            Row(
              children: [
                Checkbox(
                  value: _enableFill,
                  onChanged: (val) {
                    setState(() => _enableFill = val ?? false);
                  },
                  activeColor: const Color(0xFF2E7D32),
                ),
                const Text(
                  '施工回填',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (_enableFill) ...[
              _buildField(
                label: '回填範圍(長/寬)',
                labelColor: const Color(0xFF2E7D32),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text('長', style: TextStyle(color: Colors.black87)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _fillLengthController,
                              decoration: _inputDecoration(hint: ''),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('m', style: TextStyle(color: Colors.black87)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          const Text('寬', style: TextStyle(color: Colors.black87)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _fillWidthController,
                              decoration: _inputDecoration(hint: ''),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('m', style: TextStyle(color: Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildField(
                label: '施工材料',
                labelColor: const Color(0xFF2E7D32),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _materialValue,
                        items: _materialOptions.map((m) =>
                            DropdownMenuItem(value: m, child: Text(m))
                        ).toList(),
                        onChanged: (v) => setState(() => _materialValue = v!),
                        decoration: _inputDecoration(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _materialQtyController,
                        decoration: _inputDecoration(hint: '數量'),
                      ),
                    ),
                  ],
                ),
              ),
              _buildField(
                label: '照片-施工前',
                labelColor: const Color(0xFF2E7D32),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        _pickPhotoDialog('施工前');
                      },
                      icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                    ),
                    // 施工前照片
                    const SizedBox(width: 8),
                    // 顯示順序：File > Memory > Network > 提示

                    // 施工前
                    if (_photoBeforeFill != null)
                      _buildRemovableImage(
                        child: Image.file(_photoBeforeFill!, height: 60, width: 60, fit: BoxFit.cover),
                        onRemove: () => setState(() { _photoBeforeFill = null; }),
                      )
                    else if (_beforePhotoBytes != null)
                      _buildRemovableImage(
                        child: Image.memory(_beforePhotoBytes!, height: 60, width: 60, fit: BoxFit.cover),
                        onRemove: () => setState(() { _beforePhotoBytes = null; }),
                      )
                    else if (_initialPhotoBeforeUrl != null)
                        _buildRemovableImage(
                          child: Image.network(_initialPhotoBeforeUrl!, height: 60, width: 60, fit: BoxFit.cover),
                          onRemove: () => setState(() { _initialPhotoBeforeUrl = null; }),
                        )
                    else
                      const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              _buildField(
                label: '照片-施工中',
                labelColor: const Color(0xFF2E7D32),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        _pickPhotoDialog('施工中');
                      },
                      icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                    ),
                    // 施工中照片
                    const SizedBox(width: 8),
                    // 施工中
                    if (_photoDuring != null)
                      _buildRemovableImage(
                        child: Image.file(_photoDuring!, height: 60, width: 60, fit: BoxFit.cover),
                        onRemove: () => setState(() { _photoDuring = null; }),
                      )
                    else if (_duringPhotoBytes != null)
                      _buildRemovableImage(
                        child: Image.memory(_duringPhotoBytes!, height: 60, width: 60, fit: BoxFit.cover),
                        onRemove: () => setState(() { _duringPhotoBytes = null; }),
                      )
                    else if (_initialPhotoDuringUrl != null)
                        _buildRemovableImage(
                          child: Image.network(_initialPhotoDuringUrl!, height: 60, width: 60, fit: BoxFit.cover),
                          onRemove: () => setState(() { _initialPhotoDuringUrl = null; }),
                        )
                    else
                      const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              _buildField(
                label: '照片-施工後',
                labelColor: const Color(0xFF2E7D32),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        _pickPhotoDialog('施工後');
                      },
                      icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                    ),
                    // 施工後照片
                    const SizedBox(width: 8),
                    // 施工後
                    if (_photoAfter != null)
                      _buildRemovableImage(
                        child: Image.file(_photoAfter!, height: 60, width: 60, fit: BoxFit.cover),
                        onRemove: () => setState(() { _photoAfter = null; }),
                      )
                    else if (_afterPhotoBytes != null)
                      _buildRemovableImage(
                        child: Image.memory(_afterPhotoBytes!, height: 60, width: 60, fit: BoxFit.cover),
                        onRemove: () => setState(() { _afterPhotoBytes = null; }),
                      )
                    else if (_initialPhotoAfterUrl != null)
                        _buildRemovableImage(
                          child: Image.network(_initialPhotoAfterUrl!, height: 60, width: 60, fit: BoxFit.cover),
                          onRemove: () => setState(() { _initialPhotoAfterUrl = null; }),
                        )
                    else
                      const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            // 13) 儲存上傳按鈕
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async => await _onSaveUpload(),
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

  // ------------------ 共用：產生單一欄位 ------------------
  /// 通用欄位容器：支援在 label 旁放一個 action widget（例如 IconButton）
  Widget _buildField({
    required String label,
    required Widget child,
    Color bgColor = Colors.transparent,
    String? hint,
    Color? labelColor,
    Widget? labelAction,        // ← 多加這行
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
          // 這裡把原來的 Text(label) 改成 Row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: labelColor ?? const Color(0xFF2F5597),
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (labelAction != null) ...[
                const SizedBox(width: 4),        // label 跟 icon 之間留點空隙
                labelAction,
              ],
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  /// 圖片右上角加個「X」可移除
  Widget _buildRemovableImage({
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 0,
          top: 0,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

// ------------------ 共用：TextField/Dropdown 樣式 ------------------
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
