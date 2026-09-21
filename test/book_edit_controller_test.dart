// BookEditController 单元测试（M-5）
//
// 这些断言此前只能写成慢且脆的 widget test（要 pump 整个编辑页、找 TextField、
// 输入、点保存）。逻辑迁进控制器后可以直接构造、直接断言——本文件不依赖
// Widget 树，也不启动网络。
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/business/library/model/book.dart';
import 'package:moying/business/library/view_model/book_edit_controller.dart';
import 'package:moying/business/library/view_model/library_provider.dart';
import 'package:moying/component/media/model/media_ref.dart';

/// 造一本编辑模式的原书（默认覆盖全部可编辑字段）
Book sampleBook({
  String id = 'b_1',
  String title = '三体',
  String author = '刘慈欣',
  int totalPages = 400,
  int currentPage = 100,
  BookStatus status = BookStatus.reading,
  String? category = '科幻',
  String? publisher = '重庆出版社',
  int? year = 2008,
  String? description = '地球往事三部曲之一',
  String? notes = '黑暗森林法则',
  String? isbn = '9787536692930',
  String? source = 'googleBooks:abc',
  double? rating = 4.0,
  double coverHue = 123,
  String? emoji = '📘',
  MediaRef? cover,
  DateTime? startedAt,
  DateTime? finishedAt,
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 1, 1);
  return Book(
    id: id,
    title: title,
    author: author,
    totalPages: totalPages,
    currentPage: currentPage,
    status: status,
    createdAt: created,
    category: category,
    publisher: publisher,
    year: year,
    description: description,
    notes: notes,
    isbn: isbn,
    source: source,
    rating: rating,
    coverHue: coverHue,
    emoji: emoji,
    cover: cover,
    startedAt: startedAt,
    finishedAt: finishedAt,
  );
}

/// 统计通知次数（控制器只对「内部推导」引起的变化通知）
int Function() countNotifications(BookEditController c) {
  var n = 0;
  c.addListener(() => n++);
  return () => n;
}

void main() {
  group('BookEditController · 新增模式', () {
    test('默认值：总页数 300、已读 0、想读、无原书', () {
      final c = BookEditController();
      addTearDown(c.dispose);

      expect(c.isAddMode, isTrue);
      expect(c.notFound, isFalse);
      expect(c.book, isNull);
      expect(c.pagesCtrl.text, '300');
      expect(c.currentPagesCtrl.text, '0');
      expect(c.rating, 0);
      expect(c.statusFromProgress, BookStatus.planToRead);
      expect(c.startedAt, isNull);
      expect(c.finishedAt, isNull);
      expect(c.coverEdited, isFalse);
      // 色相只生成一次（rebuild 不得变色）
      expect(c.addCoverHue, inInclusiveRange(0, 360));
    });

    test('validate：书名或作者为空时给出统一文案', () {
      final c = BookEditController();
      addTearDown(c.dispose);

      expect(c.validate(), '书名与作者不能为空');
      c.titleCtrl.text = '三体';
      expect(c.validate(), '书名与作者不能为空');
      c.authorCtrl.text = '刘慈欣';
      expect(c.validate(), isNull);
    });

    test('composeBook：生成新实体，id 前缀 b_、字段全部落值', () async {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '  球状闪电  ';
      c.authorCtrl.text = ' 刘慈欣 ';
      c.pagesCtrl.text = '320';
      c.currentPagesCtrl.text = '80';
      c.rating = 4.5;
      c.categoryCtrl.text = ' 科幻 ';
      c.publisherCtrl.text = '四川科技';
      c.yearCtrl.text = '2004';
      c.descCtrl.text = ' 简介 ';
      c.notesCtrl.text = ' 感悟 ';
      c.isbnCtrl.text = ' 9787536692930 ';
      c.sourceTag = 'googleBooks:xyz';

      final book = await c.composeBook(LibraryProvider());

      expect(book, isNotNull);
      expect(book!.id, startsWith('b_'));
      expect(book.title, '球状闪电');
      expect(book.author, '刘慈欣');
      expect(book.totalPages, 320);
      expect(book.currentPage, 80);
      expect(book.status, BookStatus.reading);
      expect(book.rating, 4.5);
      expect(book.category, '科幻');
      expect(book.publisher, '四川科技');
      expect(book.year, 2004);
      expect(book.description, '简介');
      expect(book.notes, '感悟');
      expect(book.isbn, '9787536692930');
      expect(book.source, 'googleBooks:xyz');
      expect(book.coverHue, c.addCoverHue);
      expect(book.createdAt, c.createdAt);
      // 已读 80/320 > 0 → 自动补开始时间（controller 的联动）
      expect(book.startedAt, isNotNull);
      expect(book.finishedAt, isNull);
    });

    test('composeBook：空白文本字段归一为 null', () async {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '书';
      c.authorCtrl.text = '人';
      c.categoryCtrl.text = '   ';
      c.publisherCtrl.text = '';
      c.isbnCtrl.text = '  ';
      c.yearCtrl.text = '不是数字';

      final book = await c.composeBook(LibraryProvider());

      expect(book!.category, isNull);
      expect(book.publisher, isNull);
      expect(book.isbn, isNull);
      expect(book.year, isNull);
      expect(book.rating, isNull);
    });
  });

  group('BookEditController · 编辑模式', () {
    test('从原书回填全部表单字段', () {
      final original = sampleBook(
        startedAt: DateTime(2026, 2, 1),
        finishedAt: DateTime(2026, 3, 1),
        cover: MediaRef.network('https://img/cover.jpg'),
      );
      final c = BookEditController(bookId: 'b_1', initialBook: original);
      addTearDown(c.dispose);

      expect(c.isAddMode, isFalse);
      expect(c.notFound, isFalse);
      expect(c.book!.id, 'b_1');
      expect(c.titleCtrl.text, '三体');
      expect(c.authorCtrl.text, '刘慈欣');
      expect(c.isbnCtrl.text, '9787536692930');
      expect(c.pagesCtrl.text, '400');
      expect(c.currentPagesCtrl.text, '100');
      expect(c.publisherCtrl.text, '重庆出版社');
      expect(c.yearCtrl.text, '2008');
      expect(c.descCtrl.text, '地球往事三部曲之一');
      expect(c.notesCtrl.text, '黑暗森林法则');
      expect(c.rating, 4.0);
      expect(c.categoryCtrl.text, '科幻');
      expect(c.createdAt, DateTime(2026, 1, 1));
      expect(c.startedAt, DateTime(2026, 2, 1));
      expect(c.finishedAt, DateTime(2026, 3, 1));
    });

    test('按 id 找不到书 → notFound，composeBook 返回 null', () async {
      final c = BookEditController(bookId: 'nope');
      addTearDown(c.dispose);

      expect(c.notFound, isTrue);
      expect(c.book, isNull);
      expect(await c.composeBook(LibraryProvider()), isNull);
    });

    test('composeBook：保留未在表单里出现的字段（emoji / 色相 / 添加时间）', () async {
      final original = sampleBook(createdAt: DateTime(2025, 12, 31));
      final c = BookEditController(bookId: 'b_1', initialBook: original);
      addTearDown(c.dispose);
      c.titleCtrl.text = '三体（修订版）';

      final book = await c.composeBook(LibraryProvider());

      expect(book!.id, 'b_1');
      expect(book.title, '三体（修订版）');
      expect(book.emoji, '📘');
      expect(book.coverHue, 123);
      expect(book.createdAt, DateTime(2025, 12, 31));
      expect(book.author, '刘慈欣');
    });

    test('composeBook：未重新检索时保留原溯源标记', () async {
      final c = BookEditController(bookId: 'b_1', initialBook: sampleBook());
      addTearDown(c.dispose);

      expect((await c.composeBook(LibraryProvider()))!.source,
          'googleBooks:abc');
    });

    test('composeBook：publisher / year 显式清空会真的写入 null（sentinel 语义）',
        () async {
      final c = BookEditController(bookId: 'b_1', initialBook: sampleBook());
      addTearDown(c.dispose);
      c.publisherCtrl.text = '';
      c.yearCtrl.text = '';

      final book = await c.composeBook(LibraryProvider());

      expect(book!.publisher, isNull);
      expect(book.year, isNull);
    });
  });

  group('BookEditController · 页数与状态推导', () {
    test('effectiveTotalPages：非法输入回退（编辑=原书值，新增=300），下限 1', () {
      final add = BookEditController();
      addTearDown(add.dispose);
      expect(add.effectiveTotalPages, 300);
      add.pagesCtrl.text = 'abc';
      expect(add.effectiveTotalPages, 300);
      add.pagesCtrl.text = '0';
      expect(add.effectiveTotalPages, 1);
      add.pagesCtrl.text = '-5';
      expect(add.effectiveTotalPages, 1);
      add.pagesCtrl.text = '256';
      expect(add.effectiveTotalPages, 256);

      final edit = BookEditController(bookId: 'b_1', initialBook: sampleBook());
      addTearDown(edit.dispose);
      edit.pagesCtrl.text = '';
      expect(edit.effectiveTotalPages, 400);
    });

    test('effectiveCurrentPages：非法按 0，超出总页数截断', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.pagesCtrl.text = '100';
      c.currentPagesCtrl.text = 'xyz';
      expect(c.effectiveCurrentPages, 0);
      c.currentPagesCtrl.text = '999';
      expect(c.effectiveCurrentPages, 100);
      c.currentPagesCtrl.text = '-3';
      expect(c.effectiveCurrentPages, 0);
    });

    test('statusFromProgress：0=想读、中间=在读、填满=完成', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.pagesCtrl.text = '100';

      c.currentPagesCtrl.text = '0';
      expect(c.statusFromProgress, BookStatus.planToRead);
      c.currentPagesCtrl.text = '1';
      expect(c.statusFromProgress, BookStatus.reading);
      c.currentPagesCtrl.text = '100';
      expect(c.statusFromProgress, BookStatus.finished);
    });

    test('progressAtLeastFull：只有填满总页数才为 true', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.pagesCtrl.text = '50';
      expect(c.progressAtLeastFull, isFalse);
      c.currentPagesCtrl.text = '49';
      expect(c.progressAtLeastFull, isFalse);
      c.currentPagesCtrl.text = '50';
      expect(c.progressAtLeastFull, isTrue);
    });
  });

  group('BookEditController · 进度联动（自动补时间）', () {
    test('已读页数 > 0 → 自动补开始时间 = 添加时间（归一到日）并通知', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      final notify = countNotifications(c);
      c.pagesCtrl.text = '100';

      c.currentPagesCtrl.text = '10';

      expect(c.startedAt, DateTime(c.createdAt.year, c.createdAt.month,
          c.createdAt.day));
      expect(c.finishedAt, isNull);
      expect(notify(), 1);
    });

    test('填满总页数 → 自动补完成时间 = 今天（归一到日）', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.pagesCtrl.text = '100';

      c.currentPagesCtrl.text = '100';

      final now = DateTime.now();
      expect(c.finishedAt, DateTime(now.year, now.month, now.day));
      expect(c.startedAt, isNotNull);
    });

    test('无变化时不通知（避免多余重建）', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      final notify = countNotifications(c);

      c.currentPagesCtrl.text = '0';

      expect(notify(), 0);
    });

    test('已有开始/完成记录时不覆盖用户选定的时间', () {
      final c = BookEditController(
        bookId: 'b_1',
        initialBook: sampleBook(
          startedAt: DateTime(2026, 5, 1),
          finishedAt: DateTime(2026, 6, 1),
          currentPage: 400,
          status: BookStatus.finished,
        ),
      );
      addTearDown(c.dispose);

      c.currentPagesCtrl.text = '410';

      expect(c.startedAt, DateTime(2026, 5, 1));
      expect(c.finishedAt, DateTime(2026, 6, 1));
    });
  });

  group('BookEditController · 日期与二次确认', () {
    test('applyFinishedDate：写入完成时间并把已读页数拉满', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.pagesCtrl.text = '200';
      c.currentPagesCtrl.text = '30';

      c.applyFinishedDate(DateTime(2026, 7, 8, 15, 30));

      expect(c.finishedAt, DateTime(2026, 7, 8)); // 丢掉时分秒
      expect(c.currentPagesCtrl.text, '200');
      expect(c.statusFromProgress, BookStatus.finished);
    });

    test('applyStartedDate：归一到日', () {
      final c = BookEditController();
      addTearDown(c.dispose);

      c.applyStartedDate(DateTime(2026, 7, 8, 23, 59));

      expect(c.startedAt, DateTime(2026, 7, 8));
    });

    test('validate：完成时间早于开始时间会被拦下', () {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '书';
      c.authorCtrl.text = '人';
      c.applyStartedDate(DateTime(2026, 8, 2));
      c.applyFinishedDate(DateTime(2026, 8, 1));

      expect(c.validate(), '完成时间不能早于开始时间');
    });

    test('needsFinishedClearConfirm：有完成记录但进度被改小', () {
      final c = BookEditController(
        bookId: 'b_1',
        initialBook: sampleBook(
          currentPage: 400,
          status: BookStatus.finished,
          finishedAt: DateTime(2026, 3, 1),
        ),
      );
      addTearDown(c.dispose);
      expect(c.needsFinishedClearConfirm, isFalse);

      c.currentPagesCtrl.text = '40';

      expect(c.needsFinishedClearConfirm, isTrue);
    });
  });

  group('BookEditController · 封面预览与保存', () {
    test('编辑态未改动封面 → 预览沿用原图', () {
      final cover = MediaRef.network('https://img/cover.jpg');
      final c = BookEditController(
        bookId: 'b_1',
        initialBook: sampleBook(cover: cover),
      );
      addTearDown(c.dispose);

      expect(c.previewCoverMedia, same(cover));
    });

    test('改动后填 URL → 预览为网络图；清空 → 预览为空（占位）', () {
      final c = BookEditController(
        bookId: 'b_1',
        initialBook: sampleBook(cover: MediaRef.network('https://img/a.jpg')),
      );
      addTearDown(c.dispose);

      c.coverEdited = true;
      c.coverUrlCtrl.text = 'https://img/b.jpg';
      expect(c.previewCoverMedia!.remoteUrl, 'https://img/b.jpg');

      c.coverUrlCtrl.text = '   ';
      expect(c.previewCoverMedia, isNull);
    });

    test('composeBook：URL 封面在内存模式下退化为纯网络引用', () async {
      final c = BookEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '书';
      c.authorCtrl.text = '人';
      c.coverEdited = true;
      c.coverUrlCtrl.text = 'https://img/new.jpg';

      final book = await c.composeBook(LibraryProvider());

      expect(book!.cover!.remoteUrl, 'https://img/new.jpg');
      expect(book.cover!.localFile, isNull);
    });

    test('composeBook：封面被移除 → 保存为 null', () async {
      final c = BookEditController(
        bookId: 'b_1',
        initialBook: sampleBook(cover: MediaRef.network('https://img/a.jpg')),
      );
      addTearDown(c.dispose);
      c.coverEdited = true;
      c.coverUrlCtrl.clear();

      expect((await c.composeBook(LibraryProvider()))!.cover, isNull);
    });

    test('composeBook：未动过封面 → 沿用原图', () async {
      final cover = MediaRef.network('https://img/keep.jpg');
      final c = BookEditController(
        bookId: 'b_1',
        initialBook: sampleBook(cover: cover),
      );
      addTearDown(c.dispose);

      expect((await c.composeBook(LibraryProvider()))!.cover, same(cover));
    });
  });

  group('BookEditController · 分类候选', () {
    test('预设分类在前、书库用过的分类并入且去重', () {
      final c = BookEditController();
      addTearDown(c.dispose);

      final options = c.categoryOptions(['科幻', '自造分类', '科幻']);

      expect(options.first, kBookCategories.first);
      expect(options, contains('自造分类'));
      expect(options.where((e) => e == '科幻').length, 1);
      expect(options.length,
          kBookCategories.toSet().union({'自造分类'}).length);
    });
  });

  group('BookEditController · 生命周期', () {
    test('dispose 释放表单控制器与 FocusNode，再用会抛错', () {
      final c = BookEditController();
      c.dispose();

      expect(() => c.currentPagesCtrl.text = '1', throwsFlutterError);
      expect(() => c.categoryFocus.dispose(), throwsFlutterError);
    });
  });
}
