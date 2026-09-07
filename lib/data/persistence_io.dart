import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../providers/library_provider.dart';
import '../services/image_pick_service.dart';
import 'library_store.dart';
import 'persistence.dart';

/// 手机 / 桌面启动装配：接入本地 JSON 持久化。
///
/// 数据目录 = 应用支持目录/data（macOS: ~/Library/Application Support/<bundle>/data）。
/// v0.9.0 起不再内置演示种子：首启写空库，由用户自己录入（mock_data.dart
/// 仅保留给测试与 Web 内存预览）。此后以盘为准。
/// 图片：注入系统相册 picker（image_picker），编辑页「从相册选择」据此可见。
Future<AppBootstrap> bootstrapApp() async {
  final base = await getApplicationSupportDirectory();
  final store = LibraryStore(
    Directory('${base.path}${Platform.pathSeparator}data'),
    seed: const LibrarySnapshot(books: [], movies: [], actors: []),
  );
  final provider = LibraryProvider(
    store: store,
    picker: SystemImagePickService(),
  );
  await provider.init();
  return AppBootstrap(library: provider, store: store);
}
