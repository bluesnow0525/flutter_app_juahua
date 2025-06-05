import 'package:flutter/material.dart';
import 'dart:io';
import '../components/upload_record.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AppState extends ChangeNotifier {
  // ── 原本的屬性略 ──
  String _currentPage = 'home';
  String _userId = '';
  String _token = '';
  DateTime? _expirationDate;

  String get currentPage => _currentPage;
  String get userId => _userId;
  String get token => _token;
  DateTime? get expirationDate => _expirationDate;

  void setCurrentPage(String page) {
    _currentPage = page;
    notifyListeners();
  }

  void setUserId(String id) {
    _userId = id;
    notifyListeners();
  }

  void setToken(String token, DateTime expiration) {
    _token = token;
    _expirationDate = expiration;
    notifyListeners();
  }

  // ── 巡修單記憶資料 ──
  final Map<String, dynamic> _inspectionForm = {};
  Map<String, dynamic> get inspectionForm => _inspectionForm;
  void setInspectionFormValue(String key, dynamic value) {
    _inspectionForm[key] = value;
    notifyListeners();
  }
  void resetInspectionForm() {
    _inspectionForm.clear();
    notifyListeners();
  }

  final List<UploadRecord> _uploadList = [];
  List<UploadRecord> get uploadList => List.unmodifiable(_uploadList);

  /// 啟動時呼叫：從 Hive 讀記錄
  Future<void> loadUploadsFromDisk() async {
    final box = Hive.box('uploadBox');
    final stored = box.get('records', defaultValue: []) as List;
    _uploadList
      ..clear()
      ..addAll(
        stored
            .cast<Map>()
            .map((j) => UploadRecord.fromJson(Map<String, dynamic>.from(j))),
      );
    notifyListeners();
  }

  /// 每次變動後寫回 Hive
  void _saveToDisk() {
    final box = Hive.box('uploadBox');
    box.put('records', _uploadList.map((r) => r.toJson()).toList());
  }

  void addUploadRecord(UploadRecord rec) {
    final exists = _uploadList.any((e) => e.id == rec.id);
    if (exists) return;
    _uploadList.add(rec);
    notifyListeners();
    _saveToDisk();
  }

  void updateUploadRecord(UploadRecord rec) {
    final idx = _uploadList.indexWhere((r) => r.id == rec.id);
    if (idx != -1) {
      _uploadList[idx] = rec;
      notifyListeners();
      _saveToDisk();
    }
  }

  /// 刪除指定記錄，也只刪掉沒有其他記錄在用的檔案
  void removeUploadRecords(Set<String> ids) {
    // 1) 先算出「未刪除的其他記錄」正在使用的所有路徑
    final inUse = _uploadList
    // 排除要刪的那些
        .where((r) => !ids.contains(r.id))
    // 展開所有還在用的 filePathMap
        .expand((r) => r.filePathMap?.values ?? [])
        .toSet();

    // 2) 刪除那些要刪記錄，而且又「沒在 inUse」的檔案
    for (var rec in _uploadList.where((r) => ids.contains(r.id))) {
      rec.filePathMap?.values.forEach((path) {
        if (!inUse.contains(path)) {
          final file = File(path);
          if (file.existsSync()) {
            try {
              file.deleteSync();
            } catch (e) {
              debugPrint('刪除檔案失敗: $e');
            }
          }
        }
      });
    }

    // 3) 再把記錄從清單移除、並寫回 Hive
    _uploadList.removeWhere((r) => ids.contains(r.id));
    notifyListeners();
    _saveToDisk();
  }

  /// 清除所有記錄，也把所有本機檔案刪除
  void clearUploadRecords() {
    // 1) 先刪所有實體檔案
    for (var rec in _uploadList) {
      rec.filePathMap?.values.forEach((path) {
        final file = File(path);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (e) {
            debugPrint('刪除檔案失敗: $e');
          }
        }
      });
    }

    // 2) 再清空清單並寫回 Hive
    _uploadList.clear();
    notifyListeners();
    _saveToDisk();
  }
}
