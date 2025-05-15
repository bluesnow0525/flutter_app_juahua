import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
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

  // ------------------------- 巡修單記憶資料 -------------------------
  Map<String, dynamic> _inspectionForm = {};

  Map<String, dynamic> get inspectionForm => _inspectionForm;

  void setInspectionFormValue(String key, dynamic value) {
    _inspectionForm[key] = value;
    notifyListeners();
  }

  void resetInspectionForm() {
    _inspectionForm = {};
    notifyListeners();
  }
}
