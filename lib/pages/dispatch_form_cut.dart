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

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';
import 'map_picker_page.dart';
import './dispatch_list.dart';

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
  File? _photoBefore;
  File? _photoCut;
  File? _photoDuring;
  File? _photoAfter;
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

  @override
  void initState() {
    super.initState();
    _caseIdController.text = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is DispatchItem) {
        _initialArgs = args;
      } else {
        // 只有「新增模式」才一開始抓 GPS
        _onLocateGPS(_startGPSController);
      }
      _fetchTenders();
    });
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
    final tender    = _tenders.firstWhere((t) => t.prjId == prjId);
    final districts = tender.districts.toSet().toList();
    String? chosen  = districts.isNotEmpty ? districts.first : null;

    // 編輯模式要還原原本那筆的 district
    if (_isEditMode
        && prjId == _editItem.prjId
        && districts.contains(_editItem.district)) {
      chosen = _editItem.district;
    }

    setState(() {
      _selectedPrjId       = prjId;
      _projectNameController.text = tender.prjName;
      _districtOptions     = districts;
      _selectedDistrict    = chosen;
      _districtController.text = chosen ?? '';
    });
  }


  /// 根据 DispatchItem.images 填充网络图片 URL
  void _populateExistingImageUrls(DispatchItem item) {
    for (var img in item.images) {
      final url = 'http://211.23.157.201/${img['img_path']}';
      switch (img['img_type']) {
        case 'IMG_BEFORE':    _existingBeforeUrl   = url; break;
        case 'IMG_CUT':       _existingCutUrl      = url; break;
        case 'IMG_DURING':    _existingDuringUrl   = url; break;
        case 'IMG_AFTER':     _existingAfterUrl    = url; break;
        case 'IMG_OTHER_ZIP': _existingOtherZipUrl = url; break;
        case 'IMG_ZIP':       _existingImgZipUrl   = url; break;
      }
    }
  }

  /// 將 DispatchItem 的值注入各欄位
  void _populateFields(DispatchItem item) {
    _caseIdController.text       = item.caseNum;
    // 先透過 onProjectChanged 設定 prjId + prjName + districtOptions
    _onProjectChanged(item.prjId);

    _villageController.text      = item.village;
    _dispatchDateController.text = DateFormat('yyyy-MM-dd').format(item.dispatchDate);
    _deadlineController.text     = DateFormat('yyyy-MM-dd').format(item.dueDate);
    _workDateController.text     = DateFormat('yyyy-MM-dd').format(item.workStartDate);
    _completeDateController.text = DateFormat('yyyy-MM-dd').format(item.workEndDate);
    _roadNameController.text     = item.address;

    _startGPSController.text     = '${item.startLng}, ${item.startLat}';
    _endGPSController.text       = '${item.endLng}, ${item.endLat}';

    _selectedMaterial            = item.material;
    _particleSizeController.text = item.materialSize.toString();
    _rangeLengthController.text  = item.workLength.toString();
    _rangeWidthController.text   = item.workWidth.toString();
    _cutDepthController.text     = item.workDepthMilling.toString();
    _paveDepthController.text    = item.workDepthPaving.toString();
    _noteController.text         = item.remark;

    // 清空 local 檔案，維持顯示 network 圖片
    _photoBefore = null;
    _photoCut    = null;
    _photoDuring = null;
    _photoAfter  = null;
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
  Future<void> _fetchTenders() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final resp = await http.get(
      Uri.parse('http://211.23.157.201/api/get/tender'),
      headers: {'Authorization': 'Bearer ${appState.token}'},
    );
    if (resp.statusCode == 200) {
      final raw  = jsonDecode(resp.body)['data'] as List<dynamic>;
      final list = raw.map((e) => Tender.fromJson(e)).toList();
      if (list.isNotEmpty) {
        setState(() {
          _tenders       = list;
          // 預設選擇：編輯時用傳入的 prjId，否則第一筆
          _selectedPrjId = _initialArgs?.prjId ?? list.first.prjId;
          _onProjectChanged(_selectedPrjId!);
        });
        // 編輯回填
        if (_initialArgs != null && !_hasInitFromArgs) {
          _isEditMode   = true;
          _editItem     = _initialArgs!;
          _populateFields(_editItem);
          _populateExistingImageUrls(_editItem);
          if (_existingOtherZipUrl != null) {
            await _loadOtherZipImages();
          }
          _hasInitFromArgs = true;
        }

      }
    } else {
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
    }
  }

  // ------------------ 選日期 ------------------
  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
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
    if (title == '其他') {
      final List<XFile>? files = await _picker.pickMultiImage();
      if (files != null && files.isNotEmpty) {
        setState(() {
          for (var f in files) {
            _photoOthers.add(File(f.path));
          }
        });
      }
    } else {
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
                    _assignPhoto(title, File(file.path));
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
                    _assignPhoto(title, File(file.path));
                  });
                }
              },
              child: const Text('相簿'),
            ),
          ],
        ),
      );
    }
  }

  void _assignPhoto(String title, File file) {
    switch (title) {
      case '施工前':
        _photoBefore = file;
        break;
      case '刨除後':
        _photoCut = file;
        break;
      case '施工中':
        _photoDuring = file;
        break;
      case '施工後':
        _photoAfter = file;
        break;
      default:
        break;
    }
  }

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
  Future<void> _uploadData() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final method   = _isEditMode ? 'PATCH' : 'POST';
    final uri      = Uri.parse('http://211.23.157.201/api/app/workorder/repairDispatch');
    final req      = http.MultipartRequest(method, uri)
      ..headers['Authorization'] = 'Bearer ${appState.token}';

    // 1) 組欄位
    final Map<String, String> fields = {};
    if (_isEditMode) {
      fields['ID'] = _editItem.id.toString();
    }
    fields['PRJ_ID'] = _selectedPrjId ?? '';
    fields['TYPE']   = 'PA';

    // 解析 GPS
    double sl=0, sa=0, el=0, ea=0;
    if (_startGPSController.text.contains(',')) {
      final p = _startGPSController.text.split(',');
      sl = double.tryParse(p[0].trim()) ?? 0;
      sa = double.tryParse(p[1].trim()) ?? 0;
    }
    if (_endGPSController.text.contains(',')) {
      final p = _endGPSController.text.split(',');
      el = double.tryParse(p[0].trim()) ?? 0;
      ea = double.tryParse(p[1].trim()) ?? 0;
    }

    fields.addAll({
      'DISPATCH_DATE':    _dispatchDateController.text,
      'DUE_DATE':         _deadlineController.text,
      'DISTRICT':         _selectedDistrict ?? '',
      'CAVLGE':           _villageController.text,
      'ADDRESS':          _roadNameController.text,
      'WORK_START_DATE':  _workDateController.text,
      'WORK_END_DATE':    _completeDateController.text,
      'START_LNG':        sl.toString(),
      'START_LAT':        sa.toString(),
      'END_LNG':          el.toString(),
      'END_LAT':          ea.toString(),
      'MATERIAL':         _selectedMaterial,
      'MATERIAL_SIZE':    _particleSizeController.text,
      'WORK_LENGTH':      _rangeLengthController.text,
      'WORK_WIDTH':       _rangeWidthController.text,
      'WORK_DEPTH_MILLING': _cutDepthController.text,
      'WORK_DEPTH_PAVING':  _paveDepthController.text,
      'REMARK':           _noteController.text,
    });
    req.fields.addAll(fields);

    // 2) 四張主圖打包成 IMG_ZIP
    final mainArc = Archive();
    void addMain(File? f, String name) {
      if (f != null) mainArc.addFile(ArchiveFile(name, f.lengthSync(), f.readAsBytesSync()));
    }
    addMain(_photoBefore, 'IMG_BEFORE.jpg');
    addMain(_photoCut,    'IMG_CUT.jpg');
    addMain(_photoDuring, 'IMG_DURING.jpg');
    addMain(_photoAfter,  'IMG_AFTER.jpg');
    if (mainArc.isNotEmpty) {
      final data = ZipEncoder().encode(mainArc)!;
      req.files.add(
        http.MultipartFile.fromBytes(
          'IMG_ZIP',
          data,
          filename: 'IMG.zip',
          contentType: MediaType('application', 'zip'),
        ),
      );
    }

    // 3) 其它照片打包
    final otherArc = Archive();
    for (int i = 0; i < _photoOthers.length; i++) {
      final name = 'IMG_OTHER_${(i + 1).toString().padLeft(2, '0')}.jpg';
      otherArc.addFile(
          ArchiveFile(name, _photoOthers[i].lengthSync(), _photoOthers[i].readAsBytesSync())
      );
    }
    if (otherArc.isNotEmpty) {
      final data = ZipEncoder().encode(otherArc)!;
      req.files.add(
        http.MultipartFile.fromBytes(
          'IMG_OTHER_ZIP',
          data,
          filename: 'IMG_OTHER.zip',
          contentType: MediaType('application', 'zip'),
        ),
      );
    }
    // —— 在這裡加上 debug prints ——
    print('==== UPLOAD DEBUG ====');
    print('Method: $method');
    print('URL: $uri');
    print('Fields:');
    fields.forEach((k, v) => print('  $k: $v'));
    print('Files to upload:');
    for (var f in req.files) {
      print('  fieldName: ${f.field}, filename: ${f.filename}, length: ${f.length}');
    }
    print('=======================');

    // 4) 發送並處理回應
    try {
      final streamed = await req.send();
      final respBody = await streamed.stream.bytesToString();

      if (streamed.statusCode == 200) {
        // 解析 JSON
        final Map<String, dynamic> respJson = jsonDecode(respBody);

        if (respJson['status'] == true) {
          // 真正的成功
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('上傳成功'),
              content: const Text('派工單已成功傳送'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('確定'),
                ),
              ],
            ),
          );
        } else {
          // 200 但 status=false
          _showErrorDialog(
            streamed.statusCode,
            '後端回傳 status=false\nmessage: ${respJson['message']}\nbody: $respBody',
            fields,
            mainArc.files.map((e) => e.name).toList(),
            otherArc,
          );
        }
      } else {
        // HTTP 非 200
        _showErrorDialog(
          streamed.statusCode,
          respBody,
          fields,
          mainArc.files.map((e) => e.name).toList(),
          otherArc,
        );
      }
    } catch (e) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('上傳例外'),
          content: Text('例外：$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    }
  }

  /// 上传失败时弹窗（可选 helper）
  void _showErrorDialog(int code, String body, Map<String,String> fields, List<String> mainNames, Archive otherA) {
    final buf=StringBuffer()
      ..writeln('狀態：$code')
      ..writeln('\n── 表單欄位 ──');
    fields.forEach((k,v)=>buf.writeln('$k: $v'));
    if (mainNames.isNotEmpty) buf..writeln('\n── IMG.zip 包含 ──')..writeln(mainNames.join(', '));
    if (otherA.isNotEmpty) buf..writeln('\n── IMG_OTHER.zip 包含 ──')..writeln(otherA.files.map((f)=>f.name).join(', '));
    buf..writeln('\n── 伺服器回傳 ──')..writeln(body);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('上傳失敗'),
      content: SingleChildScrollView(child: Text(buf.toString())),
      actions: [ TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('確定')) ],
    ));
  }

  void _onSaveUpload() {
    _uploadData();
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
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '照片(施工前)',
                    child: Column(
                      children: [
                        IconButton(
                          onPressed: () => _pickPhotoDialog('施工前'),
                          icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                        ),
                        _photoBefore != null
                            ? Image.file(_photoBefore!, height: 60)
                            : (_existingBeforeUrl != null
                            ? Image.network(_existingBeforeUrl!, height: 60)
                            : const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey))
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildField(
                    label: '照片(刨除後)',
                    child: Column(
                      children: [
                        IconButton(
                          onPressed: () => _pickPhotoDialog('刨除後'),
                          icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                        ),
                        _photoCut != null
                            ? Image.file(_photoCut!, height: 60)
                            : (_existingCutUrl != null
                            ? Image.network(_existingCutUrl!, height: 60)
                            : const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey))
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 2. 照片(施工中) 與 (施工後) 改成獨立欄位：
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    label: '照片(施工中)',
                    child: Column(
                      children: [
                        IconButton(
                          onPressed: () => _pickPhotoDialog('施工中'),
                          icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                        ),
                        _photoDuring != null
                            ? Image.file(_photoDuring!, height: 60)
                            : (_existingDuringUrl != null
                            ? Image.network(_existingDuringUrl!, height: 60)
                            : const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey))
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildField(
                    label: '照片(施工後)',
                    child: Column(
                      children: [
                        IconButton(
                          onPressed: () => _pickPhotoDialog('施工後'),
                          icon: const Icon(Icons.camera_alt, color: Color(0xFF003D79)),
                        ),
                        _photoAfter != null
                            ? Image.file(_photoAfter!, height: 60)
                            : (_existingAfterUrl != null
                            ? Image.network(_existingAfterUrl!, height: 60)
                            : const Text('點擊拍照/相簿', style: TextStyle(color: Colors.grey))
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 17) 照片(其他)
            _buildField(
              label: '照片(其他)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 顯示解壓後的舊圖
                      for (final bytes in _existingOtherImages)
                        Image.memory(bytes, height: 60),
                      // 顯示使用者自己再拍或選的
                      for (final file in _photoOthers)
                        Image.file(file, height: 60),
                      // 加號按鈕
                      InkWell(
                        onTap: () => _pickPhotoDialog('其他'),
                        child: Container(
                          width: 60, height: 60,
                          color: Colors.grey[300],
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
