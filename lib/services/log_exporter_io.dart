import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// 手机 / 桌面实现：写入临时目录 → 系统分享面板。
///
/// 与 `SyncProvider` 的备份导出同构——桌面可在分享面板选「保存到文件夹」，
/// Android / iOS 直接选微信 / 邮件等；不依赖 file_picker 的 saveFile。
Future<String> exportLogText(String text, String fileName) async {
  final tmp = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
  );
  await tmp.writeAsString(text);
  try {
    await Share.shareXFiles([XFile(tmp.path)], subject: '墨影错误日志');
    return fileName;
  } finally {
    // 分享面板异步持有文件，先按 SyncProvider 的做法即时清理；
    // 抛出也兜底删除，避免临时目录长期堆积用户数据。
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } on Object catch (_) {
        // 忽略
      }
    }
  }
}
