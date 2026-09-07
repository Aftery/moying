import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moying/config/app_palette.dart';
import 'package:moying/config/app_theme.dart';
import 'package:moying/data/library_store.dart';
import 'package:moying/data/mock_data.dart';
import 'package:moying/models/media_ref.dart';
import 'package:moying/models/user_profile.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/profile_screen.dart';
import 'package:provider/provider.dart';

/// 1×1 透明 PNG（极小合法图片，供 copyImage 复制验证）
final List<int> kPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  late Directory tmpDir;

  Future<LibraryProvider> makePersistent() async {
    final store = LibraryStore(
      tmpDir,
      seed: LibrarySnapshot(
        books: kAllBooks,
        movies: kMovieList,
        actors: kActors,
      ),
    );
    final provider = LibraryProvider(store: store);
    await provider.init();
    return provider;
  }

  /// 造一个「源图片」文件（copyImage 仅要求存在）
  Future<File> makeSourceImage(String name) async {
    final f = File('${tmpDir.path}/$name');
    await f.writeAsBytes(kPngBytes);
    return f;
  }

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('moying_profile_test');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  // ==================== 模型与存储（单元） ====================

  group('用户档案：模型', () {
    test('JSON roundtrip：全字段保留', () {
      const p = UserProfile(
        nickname: '阿墨',
        signature: '签名',
        themeMode: 'light',
      );
      const avatarRef = MediaRef(localFile: 'a.png');
      final withAvatar = p.copyWith(avatar: avatarRef);
      final back = UserProfile.fromJson(withAvatar.toJson());
      expect(back, withAvatar);
    });

    test('fromJson 缺字段回退默认（旧文件兼容）', () {
      final p = UserProfile.fromJson({'nickname': '  '});
      expect(p.nickname, UserProfile.defaultNickname);
      expect(p.signature, isNull);
      expect(p.avatar, isNull);
      expect(p.themeMode, 'dark');
    });

    test('copyWith sentinel：省略保留、显式 null 清空', () {
      const p = UserProfile(
        nickname: '阿墨',
        signature: '签名',
        avatar: MediaRef(localFile: 'a.png'),
      );
      // 省略 → 保留
      final kept = p.copyWith(nickname: '新名');
      expect(kept.signature, '签名');
      expect(kept.avatar, p.avatar);
      // 显式 null → 清空
      final cleared = p.copyWith(avatar: null, signature: null);
      expect(cleared.avatar, isNull);
      expect(cleared.signature, isNull);
      expect(cleared.nickname, '阿墨');
    });
  });

  group('用户档案：持久化', () {
    test('缺 profile.json：loadProfile 返回默认并写盘', () async {
      final p = await makePersistent();
      expect(p.userProfile.nickname, UserProfile.defaultNickname);
      expect(File('${tmpDir.path}/profile.json').existsSync(), isTrue);
    });

    test('updateProfile 落盘：重启后昵称/签名/头像/themeMode 全保留', () async {
      final p = await makePersistent();
      await p.updateProfile(const UserProfile(
        nickname: '阿墨',
        signature: '记录生活',
        themeMode: 'light',
      ).copyWith(avatar: const MediaRef(localFile: 'profile.png')));
      await p.flush();

      final p2 = await makePersistent(); // 重启
      expect(p2.userProfile.nickname, '阿墨');
      expect(p2.userProfile.signature, '记录生活');
      expect(p2.userProfile.avatar?.localFile, 'profile.png');
      expect(p2.userProfile.themeMode, 'light');
    });

    test('setThemeMode 持久化并读回', () async {
      final p = await makePersistent();
      await p.setThemeMode('system');
      expect(p.themeMode, 'system');
      await p.flush();

      final p2 = await makePersistent();
      expect(p2.themeMode, 'system');
    });

    test('本地头像换图：新扩展名文件落盘，旧文件被回收', () async {
      final p = await makePersistent();
      final png = await makeSourceImage('a.png');
      final rel1 = await p.attachImage(png, 'profile');
      await p.updateProfile(p.userProfile.copyWith(
        avatar: rel1 == null ? null : MediaRef.local(rel1),
      ));

      final jpgBytes = base64Decode(
          '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPDs0NDX/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==');
      final jpg = File('${tmpDir.path}/b.jpg');
      await jpg.writeAsBytes(jpgBytes);
      final rel2 = await p.attachImage(jpg, 'profile');
      await p.updateProfile(p.userProfile.copyWith(
        avatar: rel2 == null ? null : MediaRef.local(rel2),
      ));

      expect(rel1, 'profile.png');
      expect(rel2, 'profile.jpg');
      expect(File('${tmpDir.path}/images/$rel2').existsSync(), isTrue);
      // 旧图回收（_recycleImage：localFile 变化即删旧）
      expect(File('${tmpDir.path}/images/$rel1').existsSync(), isFalse);
    });
  });

  // ==================== 个人页（widget） ====================

  group('个人页', () {
    Future<LibraryProvider> pumpScreen(WidgetTester tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryProvider>.value(
          value: p,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return p;
    }

    testWidgets('默认渲染：档案卡显示「书友」与占位签名', (tester) async {
      await pumpScreen(tester);
      expect(find.text('书友'), findsOneWidget);
      expect(find.text('读万卷书 · 行万里路'), findsOneWidget);
      expect(find.text('编辑资料'), findsOneWidget);
      expect(find.text('数据统计'), findsOneWidget);
      expect(find.text('深色模式'), findsOneWidget);
    });

    testWidgets('编辑昵称/签名：保存后档案卡即时刷新', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('编辑资料'));
      await tester.pumpAndSettle();

      // 弹层 3 个输入框：URL(0) / 昵称(1) / 签名(2)
      await tester.enterText(find.byType(TextField).at(1), '测试昵称');
      await tester.enterText(find.byType(TextField).at(2), '测试签名');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('测试昵称'), findsOneWidget);
      expect(find.text('测试签名'), findsOneWidget);
    });

    testWidgets('主题三选：选浅色后 trailing 更新', (tester) async {
      final p = await pumpScreen(tester);
      await tester.tap(find.text('深色模式'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('浅色').last);
      await tester.pumpAndSettle();

      expect(p.themeMode, 'light');
      expect(find.text('浅色'), findsOneWidget); // 仅剩 trailing 标签
    });

    testWidgets('数据统计：跳转统计页并渲染', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('数据统计'));
      await tester.pumpAndSettle();

      expect(find.text('个人统计'), findsOneWidget); // AppBar
      expect(find.text('打卡记录'), findsOneWidget); // 三段式仪表盘
      expect(find.text('类型偏好'), findsOneWidget);
    });
  });

  // ==================== 主题（widget） ====================

  group('主题', () {
    testWidgets('浅色主题下 context.colors 返回浅色板', (tester) async {
      late AppPalette captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppPalette.light),
          home: Builder(
            builder: (context) {
              captured = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured.background, AppPalette.light.background);
      expect(captured.textPrimary, AppPalette.light.textPrimary);
    });

    testWidgets('未挂 palette 的 MaterialApp 兜底暗色板', (tester) async {
      late AppPalette captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured, AppPalette.dark);
    });
  });
}
