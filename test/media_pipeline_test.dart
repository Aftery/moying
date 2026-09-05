import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moying/data/library_store.dart';
import 'package:moying/data/mock_data.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/media_ref.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/book_edit_screen.dart';
import 'package:moying/services/image_pick_service.dart';
import 'package:provider/provider.dart';

/// 1×1 透明 PNG（极小合法图片，供 decode/复制验证）
final List<int> kPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  late Directory tmpDir;

  Future<LibraryProvider> makePersistent({ImagePickService? picker}) async {
    final store = LibraryStore(
      tmpDir,
      seed: LibrarySnapshot(
        books: kAllBooks,
        movies: kMovieList,
        actors: kActors,
      ),
    );
    final provider = LibraryProvider(store: store, picker: picker);
    await provider.init();
    return provider;
  }

  /// 造一个「源图片」文件（内容不校验，copyImage 仅要求存在）
  Future<File> makeSourceImage(String name) async {
    final f = File('${tmpDir.path}/$name');
    await f.writeAsBytes(kPngBytes);
    return f;
  }

  /// 直接往 images/ 放一张图（模拟既有 localFile）
  Future<void> plantImage(String localFile) async {
    final dir = Directory('${tmpDir.path}/images');
    await dir.create(recursive: true);
    await File('${dir.path}/$localFile').writeAsBytes(kPngBytes);
  }

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('moying_media_test');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  // ==================== attach 与孤儿回收（单元） ====================

  group('图片管线：attach / 回收', () {
    test('attachImage 复制进 images/ 并返回 <id><ext> 相对名', () async {
      final p = await makePersistent();
      final src = await makeSourceImage('photo.png');
      final rel = await p.attachImage(src, 'b_custom');
      expect(rel, 'b_custom.png');
      expect(File('${tmpDir.path}/images/$rel').existsSync(), isTrue);
      expect(p.resolveLocalImage(rel)!.existsSync(), isTrue);
    });

    test('内存模式：attach 返回 null、resolveLocalImage 返回 null', () async {
      final p = LibraryProvider();
      final src = await makeSourceImage('photo.png');
      expect(await p.attachImage(src, 'x'), isNull);
      expect(p.resolveLocalImage('x.png'), isNull);
      expect(p.canPickImage, isFalse);
    });

    test('本地封面落盘：保存 → 重启后 localFile 与文件均保留', () async {
      final p = await makePersistent();
      final src = await makeSourceImage('cover.png');
      final rel = (await p.attachImage(src, 'b_pic_book'))!;
      final book = Book(
        id: 'b_pic_book',
        title: '带封面书',
        author: '作者',
        totalPages: 100,
        createdAt: DateTime(2026, 9, 5),
        cover: MediaRef.local(rel),
      );
      p.addBook(book);
      await p.flush();

      final p2 = await makePersistent(); // 重启
      final after = p2.books.firstWhere((b) => b.id == 'b_pic_book');
      expect(after.cover?.localFile, rel);
      expect(p2.resolveLocalImage(after.cover!.localFile)!.existsSync(),
          isTrue);
    });

    test('网络图落盘：重启后 remoteUrl 保留', () async {
      final p = await makePersistent();
      p.addBook(Book(
        id: 'b_net_book',
        title: '网络封面书',
        author: '作者',
        totalPages: 100,
        createdAt: DateTime(2026, 9, 5),
        cover: MediaRef.network('https://example.com/a.jpg'),
      ));
      await p.flush();

      final p2 = await makePersistent();
      final after = p2.books.firstWhere((b) => b.id == 'b_net_book');
      expect(after.cover?.remoteUrl, 'https://example.com/a.jpg');
    });

    test('updateBook 换图：旧图文件被回收、新图保留', () async {
      final p = await makePersistent();
      await plantImage('b_swap_a.png');
      await plantImage('b_swap_b.png');
      final original = p.books.first;
      p.updateBook(original.copyWith(cover: MediaRef.local('b_swap_a.png')));
      await p.flush();

      // 换到 b 图
      p.updateBook(
          p.books.first.copyWith(cover: MediaRef.local('b_swap_b.png')));
      await p.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20)); // 回收异步
      expect(File('${tmpDir.path}/images/b_swap_a.png').existsSync(), isFalse,
          reason: '旧封面文件应被回收');
      expect(File('${tmpDir.path}/images/b_swap_b.png').existsSync(), isTrue);
    });

    test('deleteBook：删除时回收其封面文件', () async {
      final p = await makePersistent();
      await plantImage('b_gone.png');
      final original = p.books.first;
      p.updateBook(original.copyWith(cover: MediaRef.local('b_gone.png')));
      await p.flush();

      p.deleteBook(original.id);
      await p.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(File('${tmpDir.path}/images/b_gone.png').existsSync(), isFalse);
    });

    test('删除电影回收海报文件', () async {
      final p = await makePersistent();
      await plantImage('m_poster.png');
      final m = p.movieList.first;
      p.updateMovie(m.copyWith(poster: MediaRef.local('m_poster.png')));
      await p.flush();

      p.deleteMovie(m.id);
      await p.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(File('${tmpDir.path}/images/m_poster.png').existsSync(), isFalse);
    });

    test('演员头像：被引用删除被拒时文件保留；引用清空后删除才回收', () async {
      final p = await makePersistent();
      final a = p.actors.first;
      await plantImage('a_avatar.png');
      p.updateActor(a.copyWith(avatar: MediaRef.local('a_avatar.png')));
      await p.flush();

      // 被引用：删除被拒，文件保留
      expect(p.deleteActor(a.id), isFalse);
      expect(File('${tmpDir.path}/images/a_avatar.png').existsSync(), isTrue);

      // 清空引用后删除成功且回收
      for (final m in p.moviesByActor(a.id).toList()) {
        p.deleteMovie(m.id);
      }
      expect(p.deleteActor(a.id), isTrue);
      await p.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(File('${tmpDir.path}/images/a_avatar.png').existsSync(), isFalse);
    });
  });

  // ==================== 编辑页封面流程（widget） ====================

  group('编辑页封面流程', () {
    Future<void> pumpEdit(
      WidgetTester tester,
      LibraryProvider provider,
    ) async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BookEditScreen()),
                  ),
                  child: const Text('打开编辑页'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('打开编辑页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> fillRequired(tester) async {
      await tester.enterText(find.byType(TextField).at(0), '测试新书');
      await tester.enterText(find.byType(TextField).at(1), '测试作者');
    }

    /// 有界推进动画（route/bottom sheet/dialog），避免 pumpAndSettle 无限等待
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('内存模式：更换封面菜单不出现「从相册选择」', (tester) async {
      final p = LibraryProvider();
      await pumpEdit(tester, p);
      await tester.ensureVisible(find.text('更换封面'));
      await settle(tester);
      await tester.tap(find.text('更换封面'));
      await settle(tester);
      expect(find.text('从相册选择'), findsNothing);
      expect(find.text('粘贴网络图片链接'), findsOneWidget);
      expect(find.text('移除封面'), findsOneWidget);
    });

    testWidgets('URL 封面：输入链接保存 → cover.remoteUrl 写入', (tester) async {
      final p = LibraryProvider();
      await pumpEdit(tester, p);
      await fillRequired(tester);
      await tester.pump();

      await tester.ensureVisible(find.text('更换封面'));
      await settle(tester);
      await tester.tap(find.text('更换封面'));
      await settle(tester);
      await tester.tap(find.text('粘贴网络图片链接'));
      await settle(tester);
      // 对话框输入框限定在 AlertDialog 内，避免与编辑页字段混淆
      final urlField = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      expect(urlField, findsOneWidget);
      await tester.enterText(urlField, 'https://example.com/cover.jpg');
      await tester.tap(find.text('确定'));
      await settle(tester);

      // 「添加图书」同时出现在 AppBar 标题与底部保存按钮；Scaffold 遍历顺序 body 在
      // appBar 前，.last 会命中 AppBar 标题（纯 Text 点了无效）→ 用 InkWell 祖先定位
      final saveBtn =
          find.ancestor(of: find.text('添加图书'), matching: find.byType(InkWell));
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await settle(tester);
      await tester.tap(saveBtn, warnIfMissed: false);
      await settle(tester);

      // 已返回宿主页且新书落库（addBook 插入头部 → books.first 即新书）
      expect(find.byType(BookEditScreen), findsNothing);
      expect(p.books.first.title, '测试新书');
      expect(p.books.first.cover?.remoteUrl, 'https://example.com/cover.jpg');
    });

    testWidgets('持久模式：更换封面菜单显示「从相册选择」', (tester) async {
      // makePersistent 含真实磁盘 IO：FakeAsync 区内文件 IO future 永不完成会卡死，
      // 必须在 runAsync（真实异步 zone）中完成初始化
      late final LibraryProvider p;
      await tester.runAsync(() async {
        final src = await makeSourceImage('pick.png');
        p = await makePersistent(picker: _FakePicker(src));
      });
      await pumpEdit(tester, p);
      await tester.ensureVisible(find.text('更换封面'));
      await settle(tester);
      await tester.tap(find.text('更换封面'));
      await settle(tester);
      expect(find.text('从相册选择'), findsOneWidget,
          reason: '持久模式应显示相册入口');
    });
  });
}

/// 测试用假选图服务：总是返回预先准备的临时文件
class _FakePicker implements ImagePickService {
  _FakePicker(this.file);

  final File file;

  @override
  Future<File?> pickImage() async => file;
}
