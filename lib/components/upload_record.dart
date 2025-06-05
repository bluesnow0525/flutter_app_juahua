import 'package:uuid/uuid.dart';

enum UploadStatus { pending, running, success, failed }

class UploadRecord {
  final String id;
  final bool isEditing;
  final DateTime createdAt;
  final Map<String, dynamic> body;
  final Map<String, String>? filePathMap; // 只有編輯模式需要
  UploadStatus status;
  String? errorMsg;

  UploadRecord({
    String? id,
    DateTime? createdAt,
    required this.body,
    this.isEditing = false,
    this.filePathMap,
    this.status = UploadStatus.pending,
    this.errorMsg,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'isEditing': isEditing,
    'createdAt': createdAt.toIso8601String(),
    'body': body,
    'filePathMap': filePathMap,
    'status': status.index,
    'errorMsg': errorMsg,
  };

  factory UploadRecord.fromJson(Map<String, dynamic> json) {
    return UploadRecord(
      id: json['id'] as String,
      isEditing: json['isEditing'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      body: Map<String, dynamic>.from(json['body'] as Map),
      filePathMap: json['filePathMap'] != null
          ? Map<String, String>.from(json['filePathMap'] as Map)
          : null,
      status: UploadStatus.values[json['status'] as int],
      errorMsg: json['errorMsg'] as String?,
    );
  }
}
