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
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';
import 'map_picker_page.dart';
import './dispatch_list.dart';
import '../components/upload_services.dart';
import '../components/upload_record.dart';
import '../components/config.dart';

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
/// DispatchBaseFormPage: 路基改善 派工單（PB 表單）
class DispatchBaseFormPage extends StatefulWidget {
  const DispatchBaseFormPage({Key? key}) : super(key: key);

  @override
  _DispatchBaseFormPageState createState() => _DispatchBaseFormPageState();
}

class _DispatchBaseFormPageState extends State<DispatchBaseFormPage> {
  // ------------------ 控制器 ------------------
  final TextEditingController _caseIdController = TextEditingController();    // 案件編號
  final TextEditingController _projectNameController = TextEditingController();// 標案名稱 (顯示用)
  final TextEditingController _districtController = TextEditingController();   // 行政區 (顯示用)
  final TextEditingController _villageController = TextEditingController();    // 里別 (顯示用)

  final TextEditingController _dispatchDateController = TextEditingController(); // 派工日期
  final TextEditingController _deadlineController = TextEditingController();     // 施工期限
  final TextEditingController _workDateController = TextEditingController();     // 施工日期
  final TextEditingController _completeDateController = TextEditingController(); // 完工日期

  final TextEditingController _roadNameController = TextEditingController();     // 施工地點

  final TextEditingController _rangeLengthController = TextEditingController();  // 施工長度 m
  final TextEditingController _rangeWidthController = TextEditingController();   // 施工寬度 m
  final TextEditingController _cutDepthController = TextEditingController();     // 刨除深度 cm
  final TextEditingController _paveDepthController = TextEditingController();    // 鋪設深度 cm

  final TextEditingController _startRoadNameController = TextEditingController(); // 起點路名
  final TextEditingController _startGPSController = TextEditingController();      // 起點 GPS

  final TextEditingController _endRoadNameController = TextEditingController();   // 迄點路名
  final TextEditingController _endGPSController = TextEditingController();        // 迄點 GPS

  String _selectedMaterial = "新料";
  final List<String> _materials = ["新料", "再生料"];
  final TextEditingController _particleSizeController = TextEditingController();  // 材料粒徑

  final TextEditingController _noteController = TextEditingController();          // 備註

  bool _isSampling = false;                                                       // 是否取樣
  final TextEditingController _sampleDateController = TextEditingController();    // 取樣日期
  List<String> _selectedTestItems = [];                                    // 試驗項目下拉
  final List<String> _testItems = [
    "瀝青含油量試驗",
    "瀝青混凝土篩分析試驗",
    "瀝青混凝土黏滯度試驗",
    "瀝青混合料壓實試體容積比重及密度試驗法"
  ];
  List<File> _photoSamples = [];                                                             // 取樣照片

  // 18 張照片
  File? _photoBefore;
  File? _photoCutting;
  File? _photoCutDepthCheck;
  File? _photoCementPaving;
  File? _photoBaseDryMix;
  File? _photoMixDepthCheck;
  File? _photoVibrationRoller;
  File? _photoCompactionDepthCheck;
  File? _photoPrimeCoat;
  File? _photoBaseFirstPaving;
  File? _photoThreeWheelRoller;
  File? _photoFirstPavingDepthCheck;
  File? _photoTackCoat;
  File? _photoSurfaceSecondPaving;
  File? _photoRoadRolling;
  File? _photoAfter;
  File? _photoACSample;
  final List<File> _photoOthers = [];

  // tender 列表與選擇
  List<Tender> _tenders = [];
  String? _selectedPrjId;
  List<String> _districtOptions = [];
  String? _selectedDistrict;

  // 編輯模式
  UploadRecord? _initialRec;
  bool _hasInitRec = false;

  DispatchItem? _initialArgs;
  bool _hasInitFromArgs = false;
  bool _isEditMode = false;
  late DispatchItem _editItem;
  // 舊圖 URL
  String? _existingBeforeUrl;
  String? _existingCuttingUrl;
  String? _existingCutDepthCheckUrl;
  String? _existingCementPavingUrl;
  String? _existingBaseDryMixUrl;
  String? _existingMixDepthCheckUrl;
  String? _existingVibrationRollerUrl;
  String? _existingCompactionDepthCheckUrl;
  String? _existingPrimeCoatUrl;
  String? _existingBaseFirstPavingUrl;
  String? _existingThreeWheelRollerUrl;
  String? _existingFirstPavingDepthCheckUrl;
  String? _existingTackCoatUrl;
  String? _existingSurfaceSecondPavingUrl;
  String? _existingRoadRollingUrl;
  String? _existingAfterUrl;
  String? _existingACSampleUrl;
  String? _existingSampleZipUrl;
  String? _existingOtherZipUrl;
  List<Uint8List> _existingSampleImages = [];
  List<Uint8List> _existingOtherImages = [];

  // ImagePicker
  final ImagePicker _picker = ImagePicker();

  // 圖片命名表 (可自行修改)
  final Map<String, String> _imageNameMap = {
    '施工前': 'IMG_BEFORE.jpg',
    '刨除中': 'IMG_CUTTING.jpg',
    '刨除厚度檢測': 'IMG_CUT_DEPTH.jpg',
    '水泥鋪設': 'IMG_CEMENT.jpg',
    '路基翻修乾拌水泥': 'IMG_BASE_DRY.jpg',
    '拌合深度檢測': 'IMG_MIX_DEPTH.jpg',
    '震動機壓實路面': 'IMG_VIBRATION.jpg',
    '壓實厚度檢測': 'IMG_COMPACTION.jpg',
    '透層噴灑': 'IMG_PRIME_COAT.jpg',
    '底層鋪築-初次鋪設': 'IMG_BASE_FIRST.jpg',
    '三輪壓路機-初壓': 'IMG_THREE_ROLL.jpg',
    '第一次鋪築厚度檢測': 'IMG_FIRST_DEPTH.jpg',
    '黏層噴灑': 'IMG_TACK_COAT.jpg',
    '面層鋪築-二次鋪設': 'IMG_SURFACE_SECOND.jpg',
    '路面滾壓': 'IMG_ROLLING.jpg',
    '施工後': 'IMG_AFTER.jpg',
    'AC取樣': 'IMG_AC_SAMPLE.jpg',
    '取樣照片': 'IMG_SAMPLE.jpg',
  };

  @override
  void initState() {
    super.initState();
    _caseIdController.text = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is UploadRecord) {
        // 本地重傳
        _initialRec = args;
        _isEditMode =  true;
        _populateFromRecord(args);
      } else if (args is DispatchItem) {
        // 從伺服器編輯
        _initialArgs = args;
        _isEditMode = true;
        // _editItem = args;
        // _populateFields(args);
        // _populateExistingImageUrls(args);
        // if (_existingSampleZipUrl != null) _loadSampleZip();
        // if (_existingOtherZipUrl != null)   _loadOtherZip();
      } else {
        // 新增模式：預設抓起點 GPS
        _onLocateGPS(_startGPSController);
      }
      // 取得標案列表，並依模式回填行政區／里別等
      _fetchTenders();
    });
  }

  @override
  void dispose() {
    for (final c in [
      _caseIdController,
      _projectNameController,
      _districtController,
      _villageController,
      _dispatchDateController,
      _deadlineController,
      _workDateController,
      _completeDateController,
      _roadNameController,
      _rangeLengthController,
      _rangeWidthController,
      _cutDepthController,
      _paveDepthController,
      _startRoadNameController,
      _startGPSController,
      _endRoadNameController,
      _endGPSController,
      _particleSizeController,
      _noteController,
      _sampleDateController
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchTenders() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final resp = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/get/tender'),
      headers: {'Authorization': 'Bearer ${appState.token}'},
    );
    if (resp.statusCode == 200) {
      final raw = jsonDecode(resp.body)['data'] as List<dynamic>;
      final list = raw.map((e) => Tender.fromJson(e)).toList();

      setState(() {
        _tenders = list;
        if (_initialRec != null) {
          // UploadRecord 里有 PRJ_ID
          final recId = _initialRec!.body['PRJ_ID'] as String?;
          _selectedPrjId = list.firstWhere(
                (t) => t.prjId == recId,
            orElse: () => list.first,
          ).prjId;
        } else if (_initialArgs != null) {
          // DispatchItem 里直接取 prjId
          _selectedPrjId = list.firstWhere(
                (t) => t.prjId == _initialArgs!.prjId,
            orElse: () => list.first,
          ).prjId;
        } else {
          // 新增，第一筆
          _selectedPrjId = list.first.prjId;
        }
      });
      if (_initialArgs != null && !_hasInitFromArgs) {
        _hasInitFromArgs = true;
        _onProjectChanged(_initialArgs!.prjId);
        _populateFields(_initialArgs!);
        _populateExistingImageUrls(_initialArgs!);
        if (_existingSampleZipUrl != null) await _loadSampleZip();
        if (_existingOtherZipUrl   != null) await _loadOtherZip();
      }

      // 再跑一次，初始化 projectName + district
      _onProjectChanged(_selectedPrjId!);
    } else {
      _showSimpleDialog('取得標案失敗', '狀態：${resp.statusCode}');
    }
  }

  void _onProjectChanged(String prjId) {
    final tender = _tenders.firstWhere((t) => t.prjId == prjId);
    final districts = tender.districts.toSet().toList();

    String chosenDistrict;
    if (_initialRec != null) {
      // 本地重传里的 DISTRICT
      chosenDistrict = (_initialRec!.body['DISTRICT'] as String?) ?? districts.first;
    } else if (_initialArgs != null) {
      // DispatchItem 里的 district
      chosenDistrict = districts.contains(_initialArgs!.district)
          ? _initialArgs!.district
          : districts.first;
    } else {
      // 新增
      chosenDistrict = districts.first;
    }

    setState(() {
      _selectedPrjId = prjId;
      _projectNameController.text = tender.prjName;
      _districtOptions = districts;
      _selectedDistrict = chosenDistrict;
      _districtController.text = chosenDistrict;
    });
  }

  void _populateFields(DispatchItem item) {
    _caseIdController.text = item.caseNum;
    _onProjectChanged(item.prjId);

    _villageController.text = item.village;
    _dispatchDateController.text = DateFormat('yyyy-MM-dd').format(item.dispatchDate);
    _deadlineController.text = DateFormat('yyyy-MM-dd').format(item.dueDate);
    _workDateController.text = DateFormat('yyyy-MM-dd').format(item.workStartDate);
    _completeDateController.text = DateFormat('yyyy-MM-dd').format(item.workEndDate);
    _roadNameController.text = item.address;
    _startRoadNameController.text = item.startAddr;
    _endRoadNameController.text = item.endAddr;

    _startGPSController.text = '${item.startLng}, ${item.startLat}';
    _endGPSController.text = '${item.endLng}, ${item.endLat}';

    _selectedMaterial = item.material;
    _particleSizeController.text = item.materialSize.toString();
    _rangeLengthController.text = item.workLength.toString();
    _rangeWidthController.text = item.workWidth.toString();
    _cutDepthController.text = item.workDepthMilling.toString();
    _paveDepthController.text = item.workDepthPaving.toString();
    _noteController.text = item.remark;

    _isSampling = item.sampleTaken ?? false;
    if (_isSampling) {
      _sampleDateController.text = DateFormat('yyyy-MM-dd').format(item.sampleDate!);
      // 如果後端回傳是一整串「、」分隔，就拆開；否則若為 List<String>，直接取用
      _selectedTestItems = item.testItem != null
           ? List<String>.from(item.testItem!)
           : [];
    }

    // 清空本地圖檔，顯示網路圖
    _photoBefore = null;
    _photoCutting = null;
    _photoCutDepthCheck = null;
    _photoCementPaving = null;
    _photoBaseDryMix = null;
    _photoMixDepthCheck = null;
    _photoVibrationRoller = null;
    _photoCompactionDepthCheck = null;
    _photoPrimeCoat = null;
    _photoBaseFirstPaving = null;
    _photoThreeWheelRoller = null;
    _photoFirstPavingDepthCheck = null;
    _photoTackCoat = null;
    _photoSurfaceSecondPaving = null;
    _photoRoadRolling = null;
    _photoAfter = null;
    _photoACSample = null;
    _photoSamples.clear();
    _photoOthers.clear();
  }

  /// 依 DispatchItem 的 images 欄位，把所有照片下載到本地 File
  Future<void> _populateExistingImageUrls(DispatchItem item) async {
    // 先清空所有本地檔案引用
    _photoBefore = null;
    _photoCutting = null;
    _photoCutDepthCheck = null;
    _photoCementPaving = null;
    _photoBaseDryMix = null;
    _photoMixDepthCheck = null;
    _photoVibrationRoller = null;
    _photoCompactionDepthCheck = null;
    _photoPrimeCoat = null;
    _photoBaseFirstPaving = null;
    _photoThreeWheelRoller = null;
    _photoFirstPavingDepthCheck = null;
    _photoTackCoat = null;
    _photoSurfaceSecondPaving = null;
    _photoRoadRolling = null;
    _photoAfter = null;
    _photoACSample = null;

    _photoSamples.clear();
    _photoOthers.clear();

    // 逐一處理每個 image 條目
    for (var img in item.images) {
      final imgType = img['img_type'] as String;
      final url     = '${ApiConfig.baseUrl}/${img['img_path']}';

      switch (imgType) {
      // 單張照片：下載並存到對應的 File 變數
        case 'IMG_BEFORE':
          _photoBefore = File(await _downloadToTemp(url));
          break;
        case 'IMG_CUTTING':
          _photoCutting = File(await _downloadToTemp(url));
          break;
        case 'IMG_CUT_DEPTH':
          _photoCutDepthCheck = File(await _downloadToTemp(url));
          break;
        case 'IMG_CEMENT':
          _photoCementPaving = File(await _downloadToTemp(url));
          break;
        case 'IMG_BASE_DRY':
          _photoBaseDryMix = File(await _downloadToTemp(url));
          break;
        case 'IMG_MIX_DEPTH':
          _photoMixDepthCheck = File(await _downloadToTemp(url));
          break;
        case 'IMG_VIBRATION':
          _photoVibrationRoller = File(await _downloadToTemp(url));
          break;
        case 'IMG_COMPACTION':
          _photoCompactionDepthCheck = File(await _downloadToTemp(url));
          break;
        case 'IMG_PRIME_COAT':
          _photoPrimeCoat = File(await _downloadToTemp(url));
          break;
        case 'IMG_BASE_FIRST':
          _photoBaseFirstPaving = File(await _downloadToTemp(url));
          break;
        case 'IMG_THREE_ROLL':
          _photoThreeWheelRoller = File(await _downloadToTemp(url));
          break;
        case 'IMG_FIRST_DEPTH':
          _photoFirstPavingDepthCheck = File(await _downloadToTemp(url));
          break;
        case 'IMG_TACK_COAT':
          _photoTackCoat = File(await _downloadToTemp(url));
          break;
        case 'IMG_SURFACE_SECOND':
          _photoSurfaceSecondPaving = File(await _downloadToTemp(url));
          break;
        case 'IMG_ROLLING':
          _photoRoadRolling = File(await _downloadToTemp(url));
          break;
        case 'IMG_AFTER':
          _photoAfter = File(await _downloadToTemp(url));
          break;
        case 'IMG_AC_SAMPLE':
          _photoACSample = File(await _downloadToTemp(url));
          break;

      // 取樣 ZIP：先存 URL，再解壓到 _photoSamples
        case 'IMG_SAMPLE_ZIP':
          _existingSampleZipUrl = url;
          await _loadSampleZip();
          break;

      // 其他 ZIP：先存 URL，再解壓到 _photoOthers
        case 'IMG_OTHER_ZIP':
          _existingOtherZipUrl = url;
          await _loadOtherZip();
          break;
      }
    }

    // 最後更新 UI
    setState(() {});
  }

  Future<void> _populateFromRecord(UploadRecord rec) async {
    final m = rec.body;

    // 1) 回填文字欄位
    _caseIdController.text       = m['case_num']    ?? m['caseNum']    ?? '';
    _dispatchDateController.text = m['DISPATCH_DATE']               ?? '';
    _deadlineController.text     = m['DUE_DATE']                   ?? '';
    _workDateController.text     = m['WORK_START_DATE']            ?? '';
    _completeDateController.text = m['WORK_END_DATE']              ?? '';
    _roadNameController.text     = m['ADDRESS']                    ?? '';
    _startRoadNameController.text = m['START_ADDR'] ?? '';
    _endRoadNameController.text   = m['END_ADDR']   ?? '';
    _villageController.text      = m['CAVLGE']                     ?? '';

    // 回填 GPS
    _startGPSController.text = '${m['START_LNG']}, ${m['START_LAT']}';
    _endGPSController.text   = '${m['END_LNG']}, ${m['END_LAT']}';

    // 回填其他欄位
    _selectedMaterial            = m['MATERIAL']   ?? _selectedMaterial;
    _particleSizeController.text = m['MATERIAL_SIZE']              ?? '';
    _rangeLengthController.text  = m['WORK_LENGTH']                ?? '';
    _rangeWidthController.text   = m['WORK_WIDTH']                 ?? '';
    _cutDepthController.text     = m['WORK_DEPTH_MILLING']         ?? '';
    _paveDepthController.text    = m['WORK_DEPTH_PAVING']          ?? '';
    _noteController.text         = m['REMARK']                     ?? '';

    // 取樣相關
    _isSampling = (m['SAMPLE_TAKEN'] == 'true');
    if (_isSampling) {
      _sampleDateController.text = m['SAMPLE_DATE'] ?? '';
      final raw = m['TEST_ITEM'];
      if (raw is List) {
        _selectedTestItems = List<String>.from(raw.cast<String>());
      } else if (raw is String) {
        _selectedTestItems = raw.contains('、')
            ? raw.split('、')
            : [raw];
      }
    }

    // 2) 清空原本的圖片檔案引用
    _photoBefore = null;
    _photoCutting = null;
    _photoCutDepthCheck = null;
    _photoCementPaving = null;
    _photoBaseDryMix = null;
    _photoMixDepthCheck = null;
    _photoVibrationRoller = null;
    _photoCompactionDepthCheck = null;
    _photoPrimeCoat = null;
    _photoBaseFirstPaving = null;
    _photoThreeWheelRoller = null;
    _photoFirstPavingDepthCheck = null;
    _photoTackCoat = null;
    _photoSurfaceSecondPaving = null;
    _photoRoadRolling = null;
    _photoAfter = null;
    _photoACSample = null;

    _photoSamples.clear();
    _photoOthers.clear();

    // 3) 依 filePathMap 回填所有圖檔
    for (final entry in rec.filePathMap!.entries) {
      var tag = entry.key;
      var src = entry.value;
      if (src.startsWith('http')) {
        src = await _downloadToTemp(src);
      }
      final f = File(src);

      if (tag.startsWith('IMG_SAMPLE_')) {
        // 多選取樣照片
        _photoSamples.add(f);
      } else if (tag.startsWith('IMG_OTHER_')) {
        // 其他多選照片
        _photoOthers.add(f);
      } else {
        // 主流程單張照片
        switch (tag) {
          case '施工前':       _photoBefore = f;              break;
          case '刨除中':       _photoCutting = f;             break;
          case '刨除厚度檢測': _photoCutDepthCheck = f;       break;
          case '水泥鋪設':     _photoCementPaving = f;        break;
          case '路基翻修乾拌水泥': _photoBaseDryMix = f;     break;
          case '拌合深度檢測': _photoMixDepthCheck = f;       break;
          case '震動機壓實路面': _photoVibrationRoller = f;   break;
          case '壓實厚度檢測': _photoCompactionDepthCheck = f; break;
          case '透層噴灑':     _photoPrimeCoat = f;           break;
          case '底層鋪築-初次鋪設': _photoBaseFirstPaving = f; break;
          case '三輪壓路機-初壓': _photoThreeWheelRoller = f;  break;
          case '第一次鋪築厚度檢測': _photoFirstPavingDepthCheck = f; break;
          case '黏層噴灑':     _photoTackCoat = f;            break;
          case '面層鋪築-二次鋪設': _photoSurfaceSecondPaving = f; break;
          case '路面滾壓':     _photoRoadRolling = f;         break;
          case '施工後':       _photoAfter = f;               break;
          case 'AC取樣':       _photoACSample = f;            break;
        }
      }
    }

    // 4) 更新 UI
    setState(() {});
  }

  Future<String> _downloadToTemp(String url) async {
    final resp = await http.get(Uri.parse(url));
    final dir = await getTemporaryDirectory();
    final ext = url.contains('.') ? url.substring(url.lastIndexOf('.')) : '';
    final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}$ext');
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }

  /// 2) 解壓後寫成 File，放到 _photoSamples
  Future<void> _loadSampleZip() async {
    if (_existingSampleZipUrl == null) return;
    try {
      final resp = await http.get(Uri.parse(_existingSampleZipUrl!));
      if (resp.statusCode == 200) {
        final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
        final imgs = <Uint8List>[];
        for (final f in archive.files) {
          if (f.isFile) {
            imgs.add(Uint8List.fromList(f.content as List<int>));
          }
        }
        setState(() {
          _existingSampleImages = imgs;
        });
      }
    } catch (e) {
      debugPrint('解壓取樣照片失敗: $e');
    }
  }

  /// 3) 同樣寫成 File，放到 _photoOthers
  Future<void> _loadOtherZip() async {
    if (_existingOtherZipUrl == null) return;
    try {
      final resp = await http.get(Uri.parse(_existingOtherZipUrl!));
      if (resp.statusCode == 200) {
        final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
        final tempDir = await getTemporaryDirectory();
        final imgs = <Uint8List>[];

        for (final f in archive) {
          if (f.isFile) {
            final bytes = Uint8List.fromList(f.content as List<int>);
            imgs.add(bytes);

            final file = File('${tempDir.path}/${f.name}');
            await file.writeAsBytes(bytes);
            _photoOthers.add(file);
          }
        }
        setState(() => _existingOtherImages = imgs);
      }
    } catch (e) {
      debugPrint('解壓其他照片失敗: $e');
    }
  }

  /// 多選取樣照片
  Future<void> _pickSamplePhotos() async {
    final files = await _picker.pickMultiImage();  // pickMultiImage()
    if (files != null) {
      setState(() {
        _photoSamples = files.map((f) => File(f.path)).toList();
      });
    }
  }

  Future<void> _pickDate(TextEditingController ctr) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('zh', 'TW'),
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      ctr.text = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {});
    }
  }

  void _showMultiSelectTestItems() async {
    // 先把目前的已选项拷贝出来做临时列表
    final tempSelected = List<String>.from(_selectedTestItems);

    await showDialog(
      context: context,
      builder: (context) {
        // 用 StatefulBuilder，让对话框内的 setState 只重建对话框内容
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('請選擇試驗項目'),
              content: SizedBox(
                height: 250,
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _testItems.map((item) {
                      final isChecked = tempSelected.contains(item);
                      return CheckboxListTile(
                        title: Text(item, style: const TextStyle(fontSize: 14)),
                        value: isChecked,
                        onChanged: (checked) {
                          // 这里调用的是对话框内部的 setState
                          setDialogState(() {
                            if (checked == true) {
                              tempSelected.add(item);
                            } else {
                              tempSelected.remove(item);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), // 不保存，直接关
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    // 把临时列表复制回页面状态，然后关对话框
                    setState(() {
                      _selectedTestItems = List.from(tempSelected);
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('確定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 透过国土署 API 抓里别
  Future<void> _fetchVillageNameAt(double lng, double lat) async {
    final url = 'https://api.nlsc.gov.tw/other/TownVillagePointQuery/$lng/$lat/4326';
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final decoded = utf8.decode(resp.bodyBytes);
        final doc = xml.XmlDocument.parse(decoded);
        final elems = doc.findAllElements('villageName');
        if (elems.isNotEmpty) {
          setState(() {
            _villageController.text = elems.first.text;
          });
        }
      }
    } catch (e) {
      debugPrint('抓里别失败：$e');
    }
  }

  /// 修改 _onLocateGPS，抓到 GPS 后若是起点就顺便抓里别
  Future<void> _onLocateGPS(TextEditingController gpsCtr) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        final text = '${pos.longitude.toStringAsFixed(6)}, ${pos.latitude.toStringAsFixed(6)}';
        setState(() => gpsCtr.text = text);

        // **如果是在「施工起点」那支 GPS Controller，就呼叫抓里别**
        if (gpsCtr == _startGPSController) {
          await _fetchVillageNameAt(pos.longitude, pos.latitude);
        }
      }
    } catch (e) {
      debugPrint('GPS 取得失败: $e');
    }
  }

  /// 修改 _onEditGPS，使用地图选点后若是起点也抓里别
  Future<void> _onEditGPS(TextEditingController gpsCtr) async {
    LatLng init = LatLng(25.0330, 121.5654);
    if (gpsCtr.text.contains(',')) {
      final parts = gpsCtr.text.split(',');
      final lng = double.parse(parts[0].trim());
      final lat = double.parse(parts[1].trim());
      init = LatLng(lat, lng);
    }
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerPage(initialPosition: init)),
    );
    if (result != null) {
      final text = '${result.longitude.toStringAsFixed(6)}, ${result.latitude.toStringAsFixed(6)}';
      setState(() => gpsCtr.text = text);

      // **如果是在「施工起点」那支 GPS Controller，就呼叫抓里别**
      if (gpsCtr == _startGPSController) {
        await _fetchVillageNameAt(result.longitude, result.latitude);
      }
    }
  }

  Future<void> _pickPhoto(String tag, {bool multiple = false}) async {
    if (multiple) {
      final files = await _picker.pickMultiImage();
      if (files != null) {
        setState(() {
          for (var f in files) _photoOthers.add(File(f.path));
        });
      }
    } else {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) _assignPhoto(tag, File(file.path));
    }
  }

  void _assignPhoto(String tag, File f) {
    switch (tag) {
      case '施工前': _photoBefore = f; break;
      case '刨除中': _photoCutting = f; break;
      case '刨除厚度檢測': _photoCutDepthCheck = f; break;
      case '水泥鋪設': _photoCementPaving = f; break;
      case '路基翻修乾拌水泥': _photoBaseDryMix = f; break;
      case '拌合深度檢測': _photoMixDepthCheck = f; break;
      case '震動機壓實路面': _photoVibrationRoller = f; break;
      case '壓實厚度檢測': _photoCompactionDepthCheck = f; break;
      case '透層噴灑': _photoPrimeCoat = f; break;
      case '底層鋪築-初次鋪設': _photoBaseFirstPaving = f; break;
      case '三輪壓路機-初壓': _photoThreeWheelRoller = f; break;
      case '第一次鋪築厚度檢測': _photoFirstPavingDepthCheck = f; break;
      case '黏層噴灑': _photoTackCoat = f; break;
      case '面層鋪築-二次鋪設': _photoSurfaceSecondPaving = f; break;
      case '路面滾壓': _photoRoadRolling = f; break;
      case '施工後': _photoAfter = f; break;
      case 'AC取樣': _photoACSample = f; break;
    }
    setState(() {});
  }

  void _showSimpleDialog(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('確定')),
        ],
      ),
    );
  }

  /// 組裝並上傳
//   Future<void> _uploadData() async {
//     final appState = Provider.of<AppState>(context, listen: false);
//     final method = _isEditMode ? 'PATCH' : 'POST';
//     final uri = Uri.parse('http://211.23.157.201/api/app/workorder/repairDispatch');
//     final req = http.MultipartRequest(method, uri)
//       ..headers['Authorization'] = 'Bearer ${appState.token}';
//
//     // Fields
//     final fields = <String,String>{
//       if (_isEditMode) 'ID': _editItem.id.toString(),
//       'PRJ_ID': _selectedPrjId ?? '',
//       'TYPE': 'PB',
//       'DISPATCH_DATE': _dispatchDateController.text,
//       'DUE_DATE': _deadlineController.text,
//       'DISTRICT': _selectedDistrict ?? '',
//       'CAVLGE': _villageController.text,
//       'ADDRESS': _roadNameController.text,
//       'WORK_START_DATE': _workDateController.text,
//       'WORK_END_DATE': _completeDateController.text,
//       'MATERIAL': _selectedMaterial,
//       'MATERIAL_SIZE': _particleSizeController.text,
//       'WORK_LENGTH': _rangeLengthController.text,
//       'WORK_WIDTH': _rangeWidthController.text,
//       'WORK_DEPTH_MILLING': _cutDepthController.text,
//       'WORK_DEPTH_PAVING': _paveDepthController.text,
//       'REMARK': _noteController.text,
//       'SAMPLE_TAKEN': _isSampling.toString(),
//       if (_isSampling) 'SAMPLE_DATE': _sampleDateController.text,
//       if (_isSampling) 'TEST_ITEM': _selectedTestItem,
//     };
//
//     // parse GPS
//     double sl=0, st=0, el=0, et=0;
//     if (_startGPSController.text.contains(',')) {
//       final p = _startGPSController.text.split(',');
//       sl = double.tryParse(p[0].trim()) ?? 0;
//       st = double.tryParse(p[1].trim()) ?? 0;
//     }
//     if (_endGPSController.text.contains(',')) {
//       final p = _endGPSController.text.split(',');
//       el = double.tryParse(p[0].trim()) ?? 0;
//       et = double.tryParse(p[1].trim()) ?? 0;
//     }
//     fields['START_LAT']= sl.toString();
//     fields['START_LNG']= st.toString();
//     fields['END_LAT']  = el.toString();
//     fields['END_LNG']  = et.toString();
//
//     req.fields.addAll(fields);
//
//     // 1) 有 key 的主圖 ZIP
//     final mainArc = Archive();
//     void _addMain(File? f, String key) {
//       if (f != null) {
//         final name = _imageNameMap[key]!;  // 這裡不會再有 '取樣照片'
//         final bytes = f.readAsBytesSync();
//         mainArc.addFile(ArchiveFile(name, bytes.length, bytes));
//       }
//     }
//     _addMain(_photoBefore, '施工前');
//     _addMain(_photoCutting, '刨除中');
//     _addMain(_photoCutDepthCheck, '刨除厚度檢測');
//     _addMain(_photoCementPaving, '水泥鋪設');
//     _addMain(_photoBaseDryMix, '路基翻修乾拌水泥');
//     _addMain(_photoMixDepthCheck, '拌合深度檢測');
//     _addMain(_photoVibrationRoller, '震動機壓實路面');
//     _addMain(_photoCompactionDepthCheck, '壓實厚度檢測');
//     _addMain(_photoPrimeCoat, '透層噴灑');
//     _addMain(_photoBaseFirstPaving, '底層鋪築-初次鋪設');
//     _addMain(_photoThreeWheelRoller, '三輪壓路機-初壓');
//     _addMain(_photoFirstPavingDepthCheck, '第一次鋪築厚度檢測');
//     _addMain(_photoTackCoat, '黏層噴灑');
//     _addMain(_photoSurfaceSecondPaving, '面層鋪築-二次鋪設');
//     _addMain(_photoRoadRolling, '路面滾壓');
//     _addMain(_photoAfter, '施工後');
//     _addMain(_photoACSample, 'AC取樣');
//     // _addMain(_photoSample, '取樣照片');
//     if (mainArc.isNotEmpty) {
//       final data = ZipEncoder().encode(mainArc)!;
//       req.files.add(http.MultipartFile.fromBytes(
//         'IMG_ZIP',
//         data,
//         filename: 'IMG.zip',
//         contentType: MediaType('application', 'zip'),
//       ));
//     }
//
// // 2) 取樣照片單獨成一包 ZIP
//     if (_isSampling && _photoSample != null) {
//       final sampleArc = Archive();
//       // 內部檔名用 map 裡對應的那個 IMG_SAMPLE.jpg
//       final name = _imageNameMap['取樣照片']!;
//       final bytes = _photoSample!.readAsBytesSync();
//       sampleArc.addFile(ArchiveFile(name, bytes.length, bytes));
//       final sampleData = ZipEncoder().encode(sampleArc)!;
//       req.files.add(http.MultipartFile.fromBytes(
//         'IMG_SAMPLE_ZIP',
//         sampleData,
//         filename: 'IMG_SAMPLE.zip',
//         contentType: MediaType('application', 'zip'),
//       ));
//     }
//
// // 3) 其他照片 ZIP（不變）
//     final otherArc = Archive();
//     for (var f in _photoOthers) {
//       final name = p.basename(f.path);
//       otherArc.addFile(ArchiveFile(name, f.lengthSync(), f.readAsBytesSync()));
//     }
//     if (otherArc.isNotEmpty) {
//       final data = ZipEncoder().encode(otherArc)!;
//       req.files.add(http.MultipartFile.fromBytes(
//         'IMG_OTHER_ZIP',
//         data,
//         filename: 'IMG_OTHER.zip',
//         contentType: MediaType('application', 'zip'),
//       ));
//     }
//
//     // 送出
//     try {
//       final streamed = await req.send();
//       final respBody = await streamed.stream.bytesToString();
//
//       if (streamed.statusCode == 200) {
//         final Map<String, dynamic> respJson = jsonDecode(respBody);
//         if (respJson['status'] == true) {
//           _showSimpleDialog('上傳成功', '派工單已送出');
//         } else {
//           _showSimpleDialog(
//             '上傳失敗',
//             '後端回傳 status = false\n'
//                 'message: ${respJson['message']}\n'
//                 'body: $respBody',
//           );
//         }
//       } else {
//         _showSimpleDialog(
//           '上傳失敗',
//           'HTTP 狀態：${streamed.statusCode}\n'
//               'body: $respBody',
//         );
//       }
//     } catch (e) {
//       _showSimpleDialog('上傳例外', e.toString());
//     }
//   }
  Future<void> _onSaveUpload() async {
    // ---- 1️⃣ 欄位檢查 ----
    final List<String> missingFields = [];

    // PRJ_ID（標案名稱）
    if (_selectedPrjId == null || _selectedPrjId!.isEmpty) {
      missingFields.add('標案名稱');
    }
    // WORKER_USER_ID（這裡寫死為 'APP'，如需動態請自行改）
    // TYPE 就寫成 'PB'，而這支頁面本身不會讓使用者改，因此可略過。

    // DISPATCH_DATE（派工日期）
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
      missingFields.add('施工起點 GPS');
    } else {
      final parts = startGps.split(',');
      if (double.tryParse(parts[0].trim()) == null ||
          double.tryParse(parts[1].trim()) == null) {
        missingFields.add('施工起點 GPS');
      }
    }
    // 迄點經緯度
    final endGps = _endGPSController.text.trim();
    if (endGps.isEmpty || !endGps.contains(',') || endGps.split(',').length < 2) {
      missingFields.add('施工迄點 GPS');
    } else {
      final parts = endGps.split(',');
      if (double.tryParse(parts[0].trim()) == null ||
          double.tryParse(parts[1].trim()) == null) {
        missingFields.add('施工迄點 GPS');
      }
    }

    // // WORK_DATE（施工日期）
    // if (_workDateController.text.trim().isEmpty) {
    //   missingFields.add('施工日期');
    // }
    // // COMPLETE_DATE（完工日期）
    // if (_completeDateController.text.trim().isEmpty) {
    //   missingFields.add('完工日期');
    // }
    // // DUE_DATE（施工期限）
    // if (_deadlineController.text.trim().isEmpty) {
    //   missingFields.add('施工期限');
    // }
    // // → 新增：施工範圍（長）
    // if (_rangeLengthController.text.trim().isEmpty) {
    //   missingFields.add('施工範圍（長）');
    // }
    // // → 新增：施工範圍（寬）
    // if (_rangeWidthController.text.trim().isEmpty) {
    //   missingFields.add('施工範圍（寬）');
    // }
    // // → 新增：深度（刨除）
    // if (_cutDepthController.text.trim().isEmpty) {
    //   missingFields.add('刨除深度');
    // }
    // // → 新增：深度（鋪設）
    // if (_paveDepthController.text.trim().isEmpty) {
    //   missingFields.add('鋪設深度');
    // }

    // SAMPLE_TAKEN 若勾選，則 SAMPLE_DATE 必填、TEST_ITEM 必填
    if (_isSampling) {
      if (_sampleDateController.text.trim().isEmpty) {
        missingFields.add('取樣日期');
      }
      if (_selectedTestItems.isEmpty) {
        missingFields.add('試驗項目');
      }
    }

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

    // ---- 2️⃣ 日期順序檢查：只檢查有填的那幾個日期 ----
    DateTime dispatchDate;
    DateTime? workDate;
    DateTime? completeDate;
    DateTime? dueDate;

    // 1) 先解析「派工日期」（必填）：
    try {
      dispatchDate = DateFormat('yyyy-MM-dd').parse(_dispatchDateController.text.trim());
    } catch (e) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('日期格式錯誤'),
          content: const Text('請確認「派工日期」格式為 yyyy-MM-dd'),
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

    // 2) 如果使用者有填「施工日期」，就解析；否則保持 null
    if (_workDateController.text.trim().isNotEmpty) {
      try {
        workDate = DateFormat('yyyy-MM-dd').parse(_workDateController.text.trim());
      } catch (e) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('日期格式錯誤'),
            content: const Text('請確認「施工日期」格式為 yyyy-MM-dd'),
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
    }

    // 3) 如果使用者有填「完工日期」，就解析；否則保持 null
    if (_completeDateController.text.trim().isNotEmpty) {
      try {
        completeDate = DateFormat('yyyy-MM-dd').parse(_completeDateController.text.trim());
      } catch (e) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('日期格式錯誤'),
            content: const Text('請確認「完工日期」格式為 yyyy-MM-dd'),
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
    }

    // 4) 如果使用者有填「施工期限」，就解析；否則保持 null
    if (_deadlineController.text.trim().isNotEmpty) {
      try {
        dueDate = DateFormat('yyyy-MM-dd').parse(_deadlineController.text.trim());
      } catch (e) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('日期格式錯誤'),
            content: const Text('請確認「施工期限」格式為 yyyy-MM-dd'),
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
    }

    // 5) 按照先後順序檢查：dispatchDate → workDate → completeDate → dueDate
    //    只要該階段有填，就要比對與前一個已填日期的先後關係
    DateTime prev = dispatchDate;
    if (workDate != null) {
      if (prev.isAfter(workDate)) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('日期順序錯誤'),
            content: const Text('「施工日期」需不早於「派工日期」'),
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
      prev = workDate;
    }
    if (completeDate != null) {
      // 如果施工日期沒填，就直接用派工日期與完工日期比對
      if (prev.isAfter(completeDate)) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('日期順序錯誤'),
            content: const Text('「完工日期」需不早於「施工日期」或「派工日期」'),
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
      prev = completeDate;
    }
    if (dueDate != null) {
      // 檢查完工日期或施工日期／派工日期 與施工期限
      if (prev.isAfter(dueDate)) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('日期順序錯誤'),
            content: const Text('「施工期限」需不早於之前所有已填日期'),
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
      prev = dueDate;
    }

    // ---- 3️⃣ 全部檢查通過後，組裝 body、fileMap，並 enqueue UploadRecord ----
    String? serverId;
    if (_initialRec != null) {
      // 這個 ID 是 UploadService 在第一次上傳成功後填進 rec.body['ID'] 的那個
      serverId = _initialRec!.body['ID']?.toString();
    } else if (_initialArgs != null) {
      // 如果是從伺服器來的 DispatchItem 編輯
      serverId = _initialArgs!.id.toString();
    }
    // 1) 組 body
    final body = <String, dynamic>{
      if (serverId != null) 'ID': serverId,
      'case_num':        _caseIdController.text,
      'PRJ_ID': _selectedPrjId ?? '',
      'TYPE': 'PB',
      'DISPATCH_DATE': _dispatchDateController.text,
      'DUE_DATE': _deadlineController.text,
      'DISTRICT': _selectedDistrict ?? '',
      'CAVLGE': _villageController.text,
      'ADDRESS': _roadNameController.text,
      'START_ADDR': _startRoadNameController.text,  // 新增
      'END_ADDR':   _endRoadNameController.text,
      'WORK_START_DATE': _workDateController.text,
      'WORK_END_DATE': _completeDateController.text,
      'MATERIAL': _selectedMaterial,
      'MATERIAL_SIZE': _particleSizeController.text,
      'WORK_LENGTH': _rangeLengthController.text,
      'WORK_WIDTH': _rangeWidthController.text,
      'WORK_DEPTH_MILLING': _cutDepthController.text,
      'WORK_DEPTH_PAVING': _paveDepthController.text,
      'REMARK': _noteController.text,
      'SAMPLE_TAKEN': _isSampling.toString(),
      if (_isSampling) 'SAMPLE_DATE': _sampleDateController.text,
      if (_isSampling) 'TEST_ITEM': _selectedTestItems,
      // 'WORKER_USER_ID': context.read<AppState>().userId,
      'WORKER_USER_ID': 'APP',
    };
    // GPS
    final sp = _startGPSController.text.split(',');
    if (sp.length==2) {
      body['START_LNG']=sp[0].trim();
      body['START_LAT']=sp[1].trim();
    }
    final ep = _endGPSController.text.split(',');
    if (ep.length==2) {
      body['END_LNG']=ep[0].trim();
      body['END_LAT']=ep[1].trim();
    }

    // 2) 收集檔案
    final fileMap = <String,String>{};
    // 主流程 tags
    final tags = _imageNameMap.keys.where((k)=>k!='取樣照片').toList();
    final files = [
      _photoBefore, _photoCutting, _photoCutDepthCheck, _photoCementPaving,
      _photoBaseDryMix, _photoMixDepthCheck, _photoVibrationRoller, _photoCompactionDepthCheck,
      _photoPrimeCoat, _photoBaseFirstPaving, _photoThreeWheelRoller, _photoFirstPavingDepthCheck,
      _photoTackCoat, _photoSurfaceSecondPaving, _photoRoadRolling, _photoAfter, _photoACSample,
    ];
    for (int i=0; i<tags.length; i++){
      final f = files[i];
      if (f!=null) fileMap[tags[i]] = f.path;
    }
    // 取樣
    for (int i = 0; i < _photoSamples.length; i++) {
      final filename = 'IMG_SAMPLE_${(i + 1).toString().padLeft(2, '0')}.jpg';
      fileMap[filename] = _photoSamples[i].path;
    }
    // 其他
    for (int i=0; i<_photoOthers.length; i++){
      fileMap['IMG_OTHER_${(i+1).toString().padLeft(2,'0')}.jpg'] = _photoOthers[i].path;
    }

    // 3) 建 Record + enqueue
    final rec = UploadRecord(
      body: body,
      isEditing: _isEditMode,
      filePathMap: fileMap,
    );
    UploadService.enqueue(context, rec);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已加入上傳佇列，背景上傳中')));
    Navigator.pushReplacementNamed(context, '/uploadList');
  }

  @override
  Widget build(BuildContext context) {
    final allKeys = _imageNameMap.keys.toList();
    // 過濾掉「取樣照片」
    final displayKeys = allKeys.where((k) => k != '取樣照片').toList();

    // 同樣排除對應的檔案 (最後一個就是 _photoSample)
    final displayFiles = <File?>[
      _photoBefore,
      _photoCutting,
      _photoCutDepthCheck,
      _photoCementPaving,
      _photoBaseDryMix,
      _photoMixDepthCheck,
      _photoVibrationRoller,
      _photoCompactionDepthCheck,
      _photoPrimeCoat,
      _photoBaseFirstPaving,
      _photoThreeWheelRoller,
      _photoFirstPavingDepthCheck,
      _photoTackCoat,
      _photoSurfaceSecondPaving,
      _photoRoadRolling,
      _photoAfter,
      _photoACSample,
    ];
    final rowCount = (displayKeys.length / 2).ceil();

    return Scaffold(
      appBar: AppHeader(),
      endDrawer: MyEndDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              '派工單 - 路基改善',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF30475E),
              ),
            ),
            const SizedBox(height: 8),

            // 案件編號
            _buildField(
              label: '案件編號',
              child: TextField(
                controller: _caseIdController,
                readOnly: true,
                decoration: _inputDecoration(isSpecialField: true),
              ),
            ),

            // 標案 + 區里
            _buildField(
              label: '標案名稱',
              child: DropdownButtonFormField<String>(
                value: _selectedPrjId,
                items: _tenders
                    .map((t) => DropdownMenuItem(
                  value: t.prjId,
                  child: Text(t.prjName),
                ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) _onProjectChanged(v);
                },
                decoration: _inputDecoration(),
              ),
            ),
            Row(children: [
              Expanded(
                child: _buildField(
                  label: '行政區',
                  child: DropdownButtonFormField<String>(
                    value: _selectedDistrict,
                    items: _districtOptions
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedDistrict = v;
                          _districtController.text = v;
                        });
                      }
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
            ]),

            // 日期群組
            Row(children: [
              Expanded(child: _buildDateField('派工日期', _dispatchDateController)),
              const SizedBox(width: 8),
              Expanded(child: _buildDateField('施工期限', _deadlineController)),
            ]),
            Row(children: [
              Expanded(child: _buildDateField('施工日期', _workDateController)),
              const SizedBox(width: 8),
              Expanded(child: _buildDateField('完工日期', _completeDateController)),
            ]),

            // 施工地點
            _buildField(
              label: '施工地點',
              child: TextField(
                controller: _roadNameController,
                decoration: _inputDecoration(),
              ),
            ),

            // 起迄點 + GPS
            _buildLocationField(
              '施工起點',
              _startRoadNameController,
              _startGPSController,
            ),
            _buildLocationField(
              '施工迄點',
              _endRoadNameController,
              _endGPSController,
            ),

            // 材料 / 粒徑
            Row(children: [
              Expanded(
                child: _buildField(
                  label: '施工材料',
                  child: DropdownButtonFormField<String>(
                    value: _selectedMaterial,
                    items: _materials
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedMaterial = v);
                    },
                    decoration: _inputDecoration(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildField(
                  label: '材料粒徑',
                  child: TextField(
                    controller: _particleSizeController,
                    decoration: _inputDecoration(),
                  ),
                ),
              ),
            ]),

            // 範圍 / 深度
            _buildField(
              label: '施工範圍',
              child: Row(children: [
                const Text('長', style: TextStyle(color: Color(0xFF2F5597))),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _rangeLengthController,
                    decoration: _inputDecoration(),
                  ),
                ),
                const Text('m  '),
                const Text('寬', style: TextStyle(color: Color(0xFF2F5597))),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _rangeWidthController,
                    decoration: _inputDecoration(),
                  ),
                ),
                const Text('m'),
              ]),
            ),
            _buildField(
              label: '深度(cm)',
              child: Row(children: [
                const Text('刨除', style: TextStyle(color: Color(0xFF2F5597))),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _cutDepthController,
                    decoration: _inputDecoration(),
                  ),
                ),
                const Text('cm  '),
                const Text('鋪設', style: TextStyle(color: Color(0xFF2F5597))),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _paveDepthController,
                    decoration: _inputDecoration(),
                  ),
                ),
                const Text('cm'),
              ]),
            ),

            // 備註
            _buildField(
              label: '備註',
              child: TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: _inputDecoration(hint: '請輸入備註'),
              ),
            ),

            // 取樣區
            Container(
              margin: EdgeInsets.only(top: 12, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      '取樣',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Checkbox(
                      value: _isSampling,
                      onChanged: (val) {
                        setState(() {
                          _isSampling = val ?? false;
                        });
                      },
                    ),
                    const Text('是否取樣'),
                  ]),
                  if (_isSampling) ...[
                    Row(children: [
                      Expanded(child: _buildDateField('取樣日期', _sampleDateController, labelColor: Colors.orange)),
                      const SizedBox(width: 8),
                      // 在 Row 裡的時候，要用 Expanded 搭配 Flexible／isExpanded 才能自適應寬度
                      Expanded(
                        child: _buildField(
                          label: '試驗項目',
                          labelColor: Colors.orange,
                          child: GestureDetector(
                            onTap: _showMultiSelectTestItems,  // 點擊開啟多選對話框的方法
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9D9D9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _selectedTestItems.isEmpty
                                    ? '請選擇試驗項目'
                                    : _selectedTestItems.join('、'),
                                style: TextStyle(
                                  color: _selectedTestItems.isEmpty ? Colors.grey : Colors.black,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                    _buildField(
                      label: '取樣照片',
                      labelColor: Colors.orange,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickSamplePhotos,
                            icon: const Icon(Icons.photo_camera, color: Colors.white),
                            label: const Text('從相簿選取 (可多張)', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF003D79),
                              minimumSize: const Size(120, 36),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (_photoSamples.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (int i = 0; i < _photoSamples.length; i++)
                                  Stack(
                                    children: [
                                      Image.file(_photoSamples[i], height: 60, width: 60, fit: BoxFit.cover),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _photoSamples.removeAt(i);
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
                              ],
                            )
                          else if (_existingSampleImages.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (int i = 0; i < _existingSampleImages.length; i++)
                                  Stack(
                                    children: [
                                      Image.memory(_existingSampleImages[i], height: 60, width: 60, fit: BoxFit.cover),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _existingSampleImages.removeAt(i);
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
                              ],
                            )
                          else
                            const Text('尚未選取取樣照片', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 18 張有 key 的照片（動態排版）
            // 下面這段，改用 displayKeys / displayFiles
            for (int row = 0; row < rowCount; row++)
              Row(
                children: [
                  Expanded(
                    child: _buildPhotoItem(
                      label: '(${displayKeys[row * 2]})',
                      tag: displayKeys[row * 2],
                      file: displayFiles[row * 2],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: row * 2 + 1 < displayKeys.length
                        ? _buildPhotoItem(
                      label: '(${displayKeys[row * 2 + 1]})',
                      tag: displayKeys[row * 2 + 1],
                      file: displayFiles[row * 2 + 1],
                    )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),

            const SizedBox(height: 16),
            // 其他照片那一欄
            _buildField(
              label: '照片 (其他)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickPhoto('其他', multiple: true),
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    label: const Text('從相簿選取 (可多張)', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003D79)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_existingOtherImages.isNotEmpty) ...[
                        for (int i = 0; i < _existingOtherImages.length; i++)
                          Stack(
                            children: [
                              Image.memory(_existingOtherImages[i], height: 60, width: 60, fit: BoxFit.cover),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _existingOtherImages.removeAt(i);
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
                      ] else ...[
                        for (int i = 0; i < _photoOthers.length; i++)
                          Stack(
                            children: [
                              Image.file(_photoOthers[i], height: 60, width: 60, fit: BoxFit.cover),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _photoOthers.removeAt(i);
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
                      ],
                      // 保留「+」按鈕
                      InkWell(
                        onTap: () => _pickPhoto('其他', multiple: true),
                        child: Container(
                          width: 60,
                          height: 60,
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
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _onSaveUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003D79),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  '儲存上傳',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
    Color labelColor = const Color(0xFF2F5597),
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        child,
      ]),
    );
  }

  Widget _buildDateField(String label, TextEditingController ctr, {Color labelColor = const Color(0xFF2F5597)}) {
    return _buildField(
      label: label,
      child: Row(children: [
        Expanded(child: TextField(controller: ctr, readOnly: true, decoration: _inputDecoration())),
        IconButton(onPressed: () => _pickDate(ctr), icon: const Icon(Icons.calendar_today, color: Color(0xFF003D79))),
      ]),
    );
  }

  Widget _buildLocationField(String label, TextEditingController nameCtr, TextEditingController gpsCtr) {
    return _buildField(
      label: label,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: nameCtr, decoration: _inputDecoration()),
        Row(children: [
          const Text('GPS定位', style: TextStyle(color: Color(0xFF2F5597), fontWeight: FontWeight.bold)),
          IconButton(onPressed: () => _onEditGPS(gpsCtr), icon: const Icon(Icons.edit, size:20, color: Color(0xFF003D79))),
        ]),
        Row(children: [
          Expanded(child: TextField(controller: gpsCtr, readOnly: true, decoration: _inputDecoration(isSpecialField: true))),
          IconButton(onPressed: () => _onLocateGPS(gpsCtr), icon: const Icon(Icons.my_location, size:20, color: Color(0xFF003D79))),
        ]),
      ]),
    );
  }

  Widget _buildPhotoItem({ required String label, required String tag, required File? file }) {
    return _buildField(
      label: label,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ElevatedButton.icon(
          onPressed: () => _pickPhoto(tag, multiple: false),
          icon: const Icon(Icons.photo_library, color: Colors.white),
          label: const Text('從相簿選取', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003D79), minimumSize: const Size(120,36)),
        ),
        const SizedBox(height:4),
        file != null
            ? Image.file(file, height:60)
            : (_getExistingUrl(tag) != null
            ? Image.network(_getExistingUrl(tag)!, height:60)
            : const Text('尚未上傳照片', style: TextStyle(color:Colors.grey))),
      ]),
    );
  }

  String? _getExistingUrl(String tag) {
    switch (tag) {
      case '施工前': return _existingBeforeUrl;
      case '刨除中': return _existingCuttingUrl;
      case '刨除厚度檢測': return _existingCutDepthCheckUrl;
      case '水泥鋪設': return _existingCementPavingUrl;
      case '路基翻修乾拌水泥': return _existingBaseDryMixUrl;
      case '拌合深度檢測': return _existingMixDepthCheckUrl;
      case '震動機壓實路面': return _existingVibrationRollerUrl;
      case '壓實厚度檢測': return _existingCompactionDepthCheckUrl;
      case '透層噴灑': return _existingPrimeCoatUrl;
      case '底層鋪築-初次鋪設': return _existingBaseFirstPavingUrl;
      case '三輪壓路機-初壓': return _existingThreeWheelRollerUrl;
      case '第一次鋪築厚度檢測': return _existingFirstPavingDepthCheckUrl;
      case '黏層噴灑': return _existingTackCoatUrl;
      case '面層鋪築-二次鋪設': return _existingSurfaceSecondPavingUrl;
      case '路面滾壓': return _existingRoadRollingUrl;
      case '施工後': return _existingAfterUrl;
      case 'AC取樣': return _existingACSampleUrl;
      default: return null;
    }
  }

  InputDecoration _inputDecoration({bool isSpecialField = false, String? hint}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: isSpecialField ? const Color(0xFFDAE3F3) : const Color(0xFFD9D9D9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(4)),
    );
  }
}