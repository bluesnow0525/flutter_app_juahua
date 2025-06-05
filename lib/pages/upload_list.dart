import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../components/app_header.dart';
import '../components/my_end_drawer.dart';
import '../components/upload_record.dart';
import '../components/upload_services.dart';
import '../components/config.dart';
// import 'inspection_list.dart';
// import 'dispatch_list.dart';

class UploadListPage extends StatefulWidget {
  const UploadListPage({Key? key}) : super(key: key);

  @override
  _UploadListPageState createState() => _UploadListPageState();
}

class _UploadListPageState extends State<UploadListPage> {
  // 存被勾選的 record.id
  final Set<String> _selectedIds = {};

  Color _statusColor(UploadStatus s) {
    switch (s) {
      case UploadStatus.running:
        return Colors.amber;
      case UploadStatus.success:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
      case UploadStatus.pending:
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // 先複製一份，再依 createdAt 由新到舊排序
    final sorted = [...appState.uploadList]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppHeader(),
      endDrawer: MyEndDrawer(),
      body: Column(
        children: [
          // 標題 + 動作選單
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '上傳列表',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'reupload_failed':
                        {
                          // 1. 先把所有「failed」的紀錄挑出來
                          final failedList = sorted.where((r) => r.status == UploadStatus.failed);
                          for (var rec in failedList) {
                            // 2. 不做 addUploadRecord；改用「覆蓋」同一個 ID
                            //    建一份新的 UploadRecord：同 ID、新的 createdAt、同 body、同 filePathMap
                            final newRec = UploadRecord(
                              id: rec.id,
                              createdAt: DateTime.now(),
                              body: Map<String, dynamic>.from(rec.body),
                              isEditing: rec.isEditing,
                              filePathMap: rec.filePathMap == null
                                  ? null
                                  : Map<String, String>.from(rec.filePathMap!),
                            );

                            // 3. 把新建的 newRec 覆蓋到 AppState 裡（replace 原本那筆）
                            final appState = Provider.of<AppState>(context, listen: false);
                            appState.updateUploadRecord(newRec);

                            // 4. 把 newRec 送去背景上傳（enqueue）
                            UploadService.reuploadWithoutAdding(context, newRec);
                          }
                        }
                        break;
                      case 'reupload_selected':
                        {
                          // 把勾選的那些 ID 全部挑出來
                          final selectedList = sorted.where((r) => _selectedIds.contains(r.id));
                          for (var rec in selectedList) {
                            // 如果這筆「原本就已經是 success」
                            if (rec.status == UploadStatus.success) {
                              // 5A. 建立一筆「全新」的 UploadRecord（不帶 id，讓系統自動產生新 id）
                              //     當作「patch 編輯再上傳」：
                              final cloneBody = Map<String, dynamic>.from(rec.body);
                              final cloneFiles = rec.filePathMap == null
                                  ? null
                                  : Map<String, String>.from(rec.filePathMap!);

                              final newRec = UploadRecord(
                                body: cloneBody,
                                isEditing: true,     // 因為本來是成功的，我們要做 PATCH，所以把 isEditing 設 true
                                filePathMap: cloneFiles,
                              );

                              final appState = Provider.of<AppState>(context, listen: false);
                              appState.addUploadRecord(newRec);
                              UploadService.enqueue(context, newRec);
                            }
                            // 如果這筆原本是 failed，跟上面 reupload_failed 一樣：「覆蓋」那筆
                            else if (rec.status == UploadStatus.failed) {
                              // 用新的 createdAt 覆蓋原有那筆（id 一样）
                              final newRec = UploadRecord(
                                id: rec.id,
                                createdAt: DateTime.now(),
                                body: Map<String, dynamic>.from(rec.body),
                                isEditing: rec.isEditing,
                                filePathMap: rec.filePathMap == null
                                    ? null
                                    : Map<String, String>.from(rec.filePathMap!),
                              );
                              final appState = Provider.of<AppState>(context, listen: false);
                              appState.updateUploadRecord(newRec);

                              // **改為** 只做上傳，不走 addUploadRecord
                              UploadService.reuploadWithoutAdding(context, newRec);
                            }
                            // 如果原本是 pending 或 running，就不應該去重傳？這裡可以視需求決定是否要忽略
                            // 例如：if (rec.status == UploadStatus.pending) { ... }
                            // 但這種情況通常不該被點重傳，我們這裡就先忽略。
                          }
                          // 重新上傳完後把勾選清空
                          _selectedIds.clear();
                        }
                        break;
                      case 'delete_selected':
                        appState.removeUploadRecords(_selectedIds);
                        _selectedIds.clear();
                        break;
                      case 'clear_all':
                        appState.clearUploadRecords();
                        _selectedIds.clear();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'reupload_failed', child: Text('失敗案件重新上傳')),
                    PopupMenuItem(value: 'reupload_selected', child: Text('指定案件重新上傳')),
                    PopupMenuItem(value: 'delete_selected', child: Text('刪除指定記錄')),
                    PopupMenuItem(value: 'clear_all', child: Text('清除所有記錄')),
                  ],
                  child: Row(children: const [
                    Text('動作'),
                    Icon(Icons.arrow_drop_down),
                  ]),
                ),
              ],
            ),
          ),

          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: const [
                SizedBox(width: 40, child: Text('勾選')),
                SizedBox(width: 36, child: Text('狀態')),
                SizedBox(width: 60, child: Text('項目')),
                Expanded(flex: 2, child: Text('案件編號')),
                Expanded(flex: 2, child: Text('上傳日期')),
                Expanded(flex: 1, child: Text('時間')),
              ],
            ),
          ),
          const Divider(),

          // Table body
          Expanded(
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final rec    = sorted[i];
                final taipei = rec.createdAt.toUtc().add(const Duration(hours: 8));
                final date = DateFormat('yyyy-MM-dd').format(taipei);
                final time = DateFormat('HH:mm').format(taipei);
                final caseNo = (rec.body['caseNum'] as String?)?.isNotEmpty == true
                    ? rec.body['caseNum']
                    : (rec.body['case_num'] as String?)?.isNotEmpty == true
                        ? rec.body['case_num']
                        : '';

                // 根据 TYPE 映射成中文項目
                final type = (rec.body['TYPE'] == 'PA' || rec.body['TYPE'] == 'PB')
                    ? '派工單'
                    : (rec.body['TYPE']=='RB' ? '巡修單' : '巡查單');

                return InkWell(
                  onTap: () {
                    if (rec.body['TYPE']=='PA') {
                        // 直接把整条上传记录给表单
                        Navigator.pushNamed(context, '/dispatchCutForm', arguments: rec);
                    }
                    else if (rec.body['TYPE']=='PB') {
                      Navigator.pushNamed(context, '/dispatchBaseForm', arguments: rec);
                    }
                    else {
                      Navigator.pushNamed(context, '/inspectionForm', arguments: rec);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // 勾選
                        SizedBox(
                          width: 40,
                          child: Checkbox(
                            value: _selectedIds.contains(rec.id),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) _selectedIds.add(rec.id);
                                else _selectedIds.remove(rec.id);
                              });
                            },
                          ),
                        ),
                        // 狀態色塊
                        Container(
                          width: 16,
                          height: 16,
                          color: _statusColor(rec.status),
                        ),
                        const SizedBox(width: 8),
                        // **項目**
                        SizedBox(
                          width: 60,
                          child: Text(type),
                        ),
                        const SizedBox(width: 8),
                        // 案件編號
                        Expanded(flex: 2, child: Text(caseNo)),
                        const SizedBox(width: 8),
                        // 上傳日期
                        Expanded(flex: 2,child: Text(date)),
                        // 時間
                        Expanded(flex: 1,child: Text(time)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
