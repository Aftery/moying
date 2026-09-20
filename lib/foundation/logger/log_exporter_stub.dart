import 'package:share_plus/share_plus.dart';

/// Web 实现：无文件系统，直接把文本交给平台分享（不落盘）。
Future<String> exportLogText(String text, String fileName) async {
  await Share.share(text, subject: '墨影错误日志');
  return fileName;
}
