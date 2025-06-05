import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import 'upload_record.dart';
import 'config.dart';

/// 在 isolate 中做 ZIP，避免卡主 UI 线程
Uint8List _zipFiles(Map<String, String> fileMap) {
  final archive = Archive();

  // 把原本的檔名（inspection.jpg、before.jpg…）對應到 IMG、IMG_BEFORE…
  const nameMap = {
    'inspection.jpg': 'IMG.jpg',
    'before.jpg':     'IMG_BEFORE.jpg',
    'during.jpg':     'IMG_DURING.jpg',
    'after.jpg':      'IMG_AFTER.jpg',
  };

  fileMap.forEach((origName, path) {
    final bytes = File(path).readAsBytesSync();
    // lookup 如果找不到就 fallback 用 origName
    final entryName = nameMap[origName] ?? origName;
    archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
  });

  final data = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(data);
}

Uint8List _zipWithName(Map<String, dynamic> params) {
  final fileMap = Map<String, String>.from(params['fileMap'] as Map);
  final nameMap = Map<String, String>.from(params['nameMap'] as Map);
  final archive = Archive();
  fileMap.forEach((origName, path) {
    final entryName = nameMap[origName] ?? origName;
    final bytes = File(path).readAsBytesSync();
    archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

String _previewBase64(String s) {
  return s.length > 20 ? '${s.substring(0,20)}...' : s;
}

Map<String, dynamic> _makePreview(Map<String, dynamic> body) {
  return body.map((k, v) {
    if (k.startsWith('IMG')) {
      return MapEntry(k, _previewBase64(v.toString()));
    }
    return MapEntry(k, v);
  });
}

class UploadService {
  /// 將新任務加到 Provider 佇列，並非同步啟動上傳
  static Future<void> reuploadWithoutAdding(BuildContext context, UploadRecord rec) async {
    final appState = Provider.of<AppState>(context, listen: false);
    rec.status = UploadStatus.running;
    appState.updateUploadRecord(rec);

    await _run(context, rec);
  }

  static Future<void> enqueue(BuildContext context, UploadRecord rec) async {
    final appState = Provider.of<AppState>(context, listen: false);
    appState.addUploadRecord(rec);
    _run(context, rec);
  }

  static void _showErrorDialog(String title, String message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  /// 背景執行上傳：根據 rec.isEditing 分流
  static Future<void> _run(BuildContext context, UploadRecord rec) async {
    final appState = Provider.of<AppState>(context, listen: false);
    rec.status = UploadStatus.running;
    appState.updateUploadRecord(rec);

    try {
      final filteredBody = <String, dynamic>{};
      rec.body.forEach((k, v) {
        if (v.toString().isNotEmpty) {
          filteredBody[k] = v;
        }
      });
      // ─── 派工單 (TYPE == 'PA') ───────────────────────
      if (rec.body['TYPE'] == 'PA') {
        // 1) 分類收集各階段檔案路徑
        final beforeMap = <String,String>{};
        final cutMap    = <String,String>{};
        final duringMap = <String,String>{};
        final afterMap  = <String,String>{};
        final otherMap  = <String,String>{};

        rec.filePathMap?.forEach((key, path) {
          if (key.startsWith('IMG_BEFORE'))      beforeMap[key] = path;
          else if (key.startsWith('IMG_CUT')    // 如果是 IMG_CUT_...
              || key.startsWith('IMG_MILLING_AFTER')) // 或 IMG_MILLING_AFTER_...
              cutMap[key] = path;
          else if (key.startsWith('IMG_DURING')) duringMap[key] = path;
          else if (key.startsWith('IMG_AFTER'))  afterMap[key]  = path;
          else if (key.startsWith('IMG_OTHER'))  otherMap[key]  = path;
        });

        // 2) 並行 Zip 各類別（UI 保持流暢）
        final zipBefore = await compute(_zipFiles, beforeMap);
        final zipCut    = await compute(_zipFiles, cutMap);
        final zipDuring = await compute(_zipFiles, duringMap);
        final zipAfter  = await compute(_zipFiles, afterMap);
        final zipOther  = await compute(_zipFiles, otherMap);

        // 3) 建立 MultipartRequest → repairDispatch
        final uri = Uri.parse('${ApiConfig.baseUrl}/api/app/workorder/repairDispatch');
        final method = rec.body.containsKey('ID') ? 'PATCH' : 'POST';
        final req = http.MultipartRequest(method, uri)
          ..headers['Authorization'] = 'Bearer ${appState.token}';

        // Debug：印出欄位與檔案資訊
        print('🛠 UploadService PA → $method $uri');
        print('📋 fields: ${filteredBody.keys.where((k)=>k!='case_num')}');
        print('📦 zips: before=${zipBefore.length}, cut=${zipCut.length}, during=${zipDuring.length}, after=${zipAfter.length}, other=${zipOther.length}');

        // 4) 填文字欄位
        filteredBody.forEach((k, v) {
          if (k != 'case_num') {
            req.fields[k] = v.toString();
          }
        });

        // 5) 加入 ZIP 檔案（欄位名對照後端）
        if (zipBefore.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes('IMG_BEFORE_ZIP', zipBefore,
              filename: 'before.zip', contentType: MediaType('application', 'zip')));
        }
        if (zipCut.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes('IMG_MILLING_AFTER_ZIP', zipCut,
              filename: 'cut.zip', contentType: MediaType('application', 'zip')));
        }
        if (zipDuring.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes('IMG_DURING_ZIP', zipDuring,
              filename: 'during.zip', contentType: MediaType('application', 'zip')));
        }
        if (zipAfter.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes('IMG_AFTER_ZIP', zipAfter,
              filename: 'after.zip', contentType: MediaType('application', 'zip')));
        }
        if (zipOther.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes('IMG_OTHER_ZIP', zipOther,
              filename: 'other.zip', contentType: MediaType('application', 'zip')));
        }

        // 6) 發送並處理回應
        final streamed = await req.send();
        final resp     = await http.Response.fromStream(streamed);
        print('🚀 UploadService PA response: ${resp.statusCode} ${resp.body}');
        if (resp.statusCode == 200) {
          // 如果是新增（POST）模式，尝试解析 JSON 并取出 caseNum
          if (!rec.isEditing) {
            try {
              final Map<String, dynamic> json = jsonDecode(resp.body);
              if (json['status'] == true) {
                final data = json['data'] as Map<String, dynamic>?;
                if (data != null && data['caseNum'] != null) {
                  final String cn = data['caseNum'].toString();
                  rec.body['caseNum']    = cn;
                  rec.body['case_num']   = cn;
                  print('✅ 取得派工單 caseNum: ${rec.body['caseNum']}');
                }
                if (data != null && data['id'] != null) {
                  final String id = data['id'].toString();
                  rec.body['ID'] = id;
                  print('✅ 取得派工單 ID: $id');
                }
                rec.status = UploadStatus.success;
              } else {
                print('⚠️ 伺服器回傳 status=false, message=${json['message']}');
                rec.status   = UploadStatus.failed;
              }
            } catch (e) {
              print('⚠️ 解析派工單回傳 JSON 失败：$e');
            }
          }else{
            final Map<String, dynamic> json = jsonDecode(resp.body);
            if (json['status'] == true) {
              // final data = json['data'] as Map<String, dynamic>?;
              rec.status = UploadStatus.success;
            } else {
              print('⚠️ 伺服器回傳 status=false, message=${json['message']}');
              rec.status   = UploadStatus.failed;
            }
          }
        } else {
          rec.status   = UploadStatus.failed;
          rec.errorMsg = '狀態 ${resp.statusCode}，${resp.body}';
          print('❌ UploadService PA 失敗：${rec.errorMsg}');
          final preview = _makePreview(rec.body);
          print('📋 fields preview: ${jsonEncode(preview)}');
          _showErrorDialog(
            '派工單上傳失敗',
            '狀態：${rec.errorMsg}\n\n'
                '欄位預覽：\n${jsonEncode(preview)}\n\n'
                '完整檔案列表：\n${jsonEncode(rec.filePathMap)}',
          );
        }
        appState.updateUploadRecord(rec);
        return;
      }

      // ─── PB 路基改善上傳 ─────────────────────────
      // ─── PB 路基改善上傳 ─────────────────────────
      else if (rec.body['TYPE'] == 'PB') {
        // 1) 拆分 filePathMap
        final mainMap   = <String,String>{};
        final sampleMap = <String,String>{};
        final otherMap  = <String,String>{};
        rec.filePathMap?.forEach((tag, path) {
          if (tag.startsWith('IMG_SAMPLE_'))         sampleMap[tag] = path;
          else if (tag.startsWith('IMG_OTHER'))      otherMap[tag]  = path;
          else                                        mainMap[tag]   = path;
        });

        // 2) 定義 entryName 映射
        const nameMap = {
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
        };

        // 3) 並行 Zip 各類別
        final zipMain   = await compute(_zipWithName, {'fileMap': mainMap,   'nameMap': nameMap});
        final zipSample = await compute(_zipWithName, {'fileMap': sampleMap, 'nameMap': nameMap});
        final zipOther  = await compute(_zipWithName, {'fileMap': otherMap,  'nameMap': nameMap});

        final mainEntryNames = mainMap.keys
            .map((orig) => nameMap[orig] ?? orig)
            .join(', ');
        final sampleEntryNames = sampleMap.keys
            .map((orig) => nameMap[orig] ?? orig)
            .join(', ');
        final otherEntryNames = otherMap.keys.join(', ');

        print('📦 IMG_ZIP entries: $mainEntryNames');
        print('📦 IMG_SAMPLE_ZIP entries: $sampleEntryNames');
        print('📦 IMG_OTHER_ZIP entries: $otherEntryNames');

        // 4) 準備 MultipartRequest
        final uri = Uri.parse('${ApiConfig.baseUrl}/api/app/workorder/repairDispatch');
        final method = rec.body.containsKey('ID') ? 'PATCH' : 'POST';
        final req = http.MultipartRequest(method, uri)
          ..headers['Authorization'] = 'Bearer ${appState.token}';

        // 5) 填文字欄位
        filteredBody.forEach((k, v) {
          // 如果是 TEST_ITEM 且 v 為 List<String>
          if (k == 'TEST_ITEM' && v is List<String>) {
            for (var single in v) {
              if (single.toString().isNotEmpty) {
                req.files.add(
                  http.MultipartFile.fromString(
                    'TEST_ITEM',
                    single,
                    contentType: MediaType('text', 'plain'),
                  ),
                );
              }
            }
          } else {
            req.fields[k] = v.toString();
          }
        });

        // 6) 加 ZIP 檔案
        if (zipMain.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes(
            'IMG_ZIP', zipMain,
            filename: 'IMG.zip', contentType: MediaType('application','zip'),
          ));
        }
        if (zipSample.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes(
            'IMG_SAMPLE_ZIP', zipSample,
            filename: 'IMG_SAMPLE.zip', contentType: MediaType('application','zip'),
          ));
        }
        if (zipOther.isNotEmpty) {
          req.files.add(http.MultipartFile.fromBytes(
            'IMG_OTHER_ZIP', zipOther,
            filename: 'IMG_OTHER.zip', contentType: MediaType('application','zip'),
          ));
        }

        // 7) 發送並處理回應
        final streamed = await req.send();
        final resp     = await http.Response.fromStream(streamed);
        print('🚀 UploadService PB response: ${resp.statusCode} ${resp.body}');

        if (resp.statusCode == 200) {
          try {
            // 1. 只解码一次
            final decoded = jsonDecode(resp.body) as Map<String, dynamic>;

            // 2. status=true 时，解析 data
            if (decoded['status'] == true) {
              final dataRaw = decoded['data'];
              final Map<String, dynamic>? data =
              dataRaw is Map<String, dynamic> ? dataRaw : null;

              // 3. 仅在「新增」模式下，保存 caseNum 和 ID
              if (data != null) {
                if (data['caseNum'] != null) {
                  final String cn = data['caseNum'].toString();
                  rec.body['caseNum']  = cn;
                  rec.body['case_num'] = cn;
                  print('✅ 取得路基改善 caseNum: $cn');
                }
                if (data['id'] != null) {
                  final String id = data['id'].toString();
                  rec.body['ID'] = id;
                  print('✅ 取得路基改善 ID: $id');
                }
              }

              // 4. 标记成功
              rec.status = UploadStatus.success;
            }
            else {
              rec.status = UploadStatus.failed;
              print('⚠️ 伺服器回傳 status=false, message=${decoded['message']}');
              final preview = _makePreview(rec.body);
              _showErrorDialog(
                '路基改善上傳失敗',
                '狀態: status=false\n'
                    'message: ${decoded['message']}\n\n'
                    '欄位預覽：\n${jsonEncode(preview)}\n\n'
                    '完整檔案列表：\n${jsonEncode(rec.filePathMap)}',
              );
            }
          } catch (e) {
            // JSON 解析失败也算一次失败
            rec.status   = UploadStatus.failed;
            rec.errorMsg = '解析回傳資料時失敗: $e';
            final preview = _makePreview(rec.body);
            _showErrorDialog(
              '路基改善上傳失敗',
              '解析回傳資料時發生錯誤：$e\n\n'
                  '欄位預覽：\n${jsonEncode(preview)}\n\n'
                  '完整檔案列表：\n${jsonEncode(rec.filePathMap)}',
            );
          }
        } else {
          // HTTP code != 200
          rec.status   = UploadStatus.failed;
          rec.errorMsg = 'HTTP ${resp.statusCode}，body=${resp.body}';
          final preview = _makePreview(rec.body);
          _showErrorDialog(
            '路基改善上傳失敗',
            '狀態：${rec.errorMsg}\n\n'
                '欄位預覽：\n${jsonEncode(preview)}\n\n'
                '完整檔案列表：\n${jsonEncode(rec.filePathMap)}',
          );
        }

// **最关键：在任何分支结束后，一定要把 rec 更新回 AppState**
//         final appState = Provider.of<AppState>(context, listen: false);
        appState.updateUploadRecord(rec);
        return;
      }

      // ─── 巡修／巡查單編輯 (PATCH) ───────────────────
      else if (rec.isEditing) {
        // 1️⃣ ZIP 所有文件
        final zipData = await compute(_zipFiles, rec.filePathMap!);

        // 2️⃣ 创建 MultipartRequest
        final uri = Uri.parse('${ApiConfig.baseUrl}/api/app/workorder/maintenance');
        final req = http.MultipartRequest('PATCH', uri)
          ..headers['Authorization'] = 'Bearer ${appState.token}';

        // 3️⃣ 填入所有 form-data 文本字段
        //    （务必包含 PRJ_ID, TYPE, SURVEY_DATE…）
        filteredBody.forEach((k, v) {
          if (k != 'case_num') {
            req.fields[k] = v.toString();
          }
        });

        // 4️⃣ 只加一个 IMG_ZIP 文件
        req.files.add(
          http.MultipartFile.fromBytes(
            'IMG_ZIP',
            zipData,
            filename: 'images.zip',
            contentType: MediaType('application', 'zip'),
          ),
        );

        // 5️⃣ 发送
        final streamed = await req.send();
        final resp     = await http.Response.fromStream(streamed);

        // 如果 HTTP 不是 200，就直接判定失敗
        if (resp.statusCode != 200) {
          rec.status   = UploadStatus.failed;
          rec.errorMsg = 'HTTP ${resp.statusCode}，${resp.body}';

          // 顯示錯誤對話框（選擇性）
          final shortBody = rec.body.map((k, v) {
            final s = v.toString();
            return MapEntry(k, s.length > 20 ? '${s.substring(0,20)}…' : s);
          });
          const nameMap = {
            'inspection.jpg': 'IMG.jpg',
            'before.jpg':     'IMG_BEFORE.jpg',
            'during.jpg':     'IMG_DURING.jpg',
            'after.jpg':      'IMG_AFTER.jpg',
          };
          final zippedNames = rec.filePathMap!.keys
              .map((orig) => nameMap[orig] ?? orig)
              .join(', ');

          _showErrorDialog(
            '巡修單更新失敗',
            'HTTP ${resp.statusCode}，${resp.body}\n\n'
                'Fields Preview:\n${jsonEncode(shortBody)}\n\n'
                'ZIP 檔內容：IMG_ZIP{${zippedNames}}',
          );
        } else {
          // HTTP 200 → 進一步解析 JSON，檢查 status 和 code
          try {
            final decoded = jsonDecode(resp.body) as Map<String, dynamic>;

            final bool statusOk = decoded['status'] == true;
            final bool codeOk   = decoded.containsKey('code')
                && decoded['code']?.toString() == '200';

            if (statusOk && codeOk) {
              // 成功
              rec.status = UploadStatus.success;
            } else {
              // HTTP 200 但 status=false 或 code != 200 → 視為失敗
              rec.status = UploadStatus.failed;

              final msgCode = decoded['code']?.toString() ?? 'unknown';
              final msgText = decoded['message'] ?? '(無錯誤訊息)';
              final shortBody = rec.body.map((k, v) {
                final s = v.toString();
                return MapEntry(k, s.length > 20 ? '${s.substring(0,20)}…' : s);
              });
              const nameMap = {
                'inspection.jpg': 'IMG.jpg',
                'before.jpg':     'IMG_BEFORE.jpg',
                'during.jpg':     'IMG_DURING.jpg',
                'after.jpg':      'IMG_AFTER.jpg',
              };
              final zippedNames = rec.filePathMap!.keys
                  .map((orig) => nameMap[orig] ?? orig)
                  .join(', ');

              _showErrorDialog(
                '巡修單更新失敗',
                '伺服器回傳 status=${decoded['status']}，code=$msgCode\n'
                    'message: $msgText\n\n'
                    'Fields Preview:\n${jsonEncode(shortBody)}\n\n'
                    'ZIP 檔內容：IMG_ZIP{${zippedNames}}',
              );
            }
          } catch (e) {
            // JSON 解析失敗也視為失敗
            rec.status   = UploadStatus.failed;
            rec.errorMsg = '解析回傳 JSON 失敗: $e';
            final shortBody = rec.body.map((k, v) {
              final s = v.toString();
              return MapEntry(k, s.length > 20 ? '${s.substring(0,20)}…' : s);
            });
            const nameMap = {
              'inspection.jpg': 'IMG.jpg',
              'before.jpg':     'IMG_BEFORE.jpg',
              'during.jpg':     'IMG_DURING.jpg',
              'after.jpg':      'IMG_AFTER.jpg',
            };
            final zippedNames = rec.filePathMap!.keys
                .map((orig) => nameMap[orig] ?? orig)
                .join(', ');

            _showErrorDialog(
              '巡修單更新失敗',
              '解析回傳資料時錯誤：$e\n\n'
                  'Fields Preview:\n${jsonEncode(shortBody)}\n\n'
                  'ZIP 檔內容：IMG_ZIP{${zippedNames}}',
            );
          }
        }

        // 7️⃣ 最後務必更新狀態到 AppState，才能讓 UploadListPage 刷新顏色
        appState.updateUploadRecord(rec);
      }
      // ─── 巡修／巡查單新增 (JSON POST) ────────────────
      else {
        final uri = Uri.parse('${ApiConfig.baseUrl}/api/app/workorder/maintenance');
        print('🛠 UploadService POST inspection → $uri');

        final filteredBody = <String, dynamic>{};
        rec.body.forEach((k, v) {
          if (v.toString().isNotEmpty) {
            filteredBody[k] = v;
          }
        });
        print('📋 [Filtered] json body: ${jsonEncode(filteredBody)}');

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${appState.token}',
          },
          body: jsonEncode(filteredBody),
        );
        print('🚀 UploadService POST response: ${response.statusCode} ${response.body}');
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 200 && result['status'] == true) {
          rec.status = UploadStatus.success;
          final data = result['data'] as Map<String, dynamic>?;
          if (data != null && data['caseNum'] != null) {
            rec.body['caseNum'] = data['caseNum'].toString();
            rec.body['case_num'] = data['caseNum'].toString();
          }
          if (data != null && data['id'] != null) {
            final String id = data['id'].toString();
            rec.body['ID'] = id;
            print('✅ 取得巡修單 ID: $id');
          }
        } else {
          rec.status   = UploadStatus.failed;
          rec.errorMsg = '狀態 ${response.statusCode}，${response.body}';
          print('❌ UploadService POST 失敗：${rec.errorMsg}');
          // 新增：彈出 dialog 顯示所有欄位&檔案
          final preview = _makePreview(rec.body);
          print('📋 fields preview: ${jsonEncode(preview)}');
          _showErrorDialog(
            '巡修單上傳失敗',
            '狀態：${rec.errorMsg}\n\n'
                '欄位預覽：\n${jsonEncode(preview)}\n\n'
                '完整檔案列表：\n${jsonEncode(rec.filePathMap)}',
          );
        }
      }
    } catch (e, st) {
      rec.status   = UploadStatus.failed;
      rec.errorMsg = e.toString();
      print('🔥 UploadService 例外：$e\n$st');
    }

    appState.updateUploadRecord(rec);
  }
}
