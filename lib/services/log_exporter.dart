import 'log_exporter_stub.dart'
    if (dart.library.io) 'log_exporter_io.dart' as impl;

/// 导出日志内容：手机 / 桌面写成本地 `.txt` 后交给系统分享面板；
/// Web 无文件系统，直接走平台分享（文本）。
///
/// 返回结果描述（文件名）以便 UI 提示；抛出则视为导出失败。
Future<String> exportLogText(String text, String fileName) =>
    impl.exportLogText(text, fileName);
