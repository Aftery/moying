import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../providers/library_provider.dart';
import '../services/image_pick_service.dart';
import 'library_store.dart';
import 'mock_data.dart';
import 'persistence.dart';

/// 手机 / 桌面启动装配：接入本地 JSON 持久化。
///
/// 数据目录 = 应用支持目录/data（macOS: ~/Library/Application Support/<bundle>/data）。
/// seed 用 mock 三集合，由 store 首启写入；此后以盘为准。
/// 图片：注入系统相册 picker（image_picker），编辑页「从相册选择」据此可见。
Future<AppBootstrap> bootstrapApp() async {
  final base = await getApplicationSupportDirectory();
  final store = LibraryStore(
    Directory('${base.path}${Platform.pathSeparator}data'),
    seed: LibrarySnapshot(
      books: kAllBooks,
      movies: kMovieList,
      actors: kActors,
    ),
  );
  final provider = LibraryProvider(
    store: store,
    picker: SystemImagePickService(),
  );
  await provider.init();
  return AppBootstrap(library: provider, store: store);
}
