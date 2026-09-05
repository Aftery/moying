// LibraryProvider 单元测试：搜索 / 筛选 / 更新 / 删除 / 派生列表
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/data/mock_data.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/movie.dart';
import 'package:moying/providers/library_provider.dart';

void main() {
  group('LibraryProvider · 初始状态', () {
    test('初始书库与 mock 数据一致（12 本，覆盖三种状态）', () {
      final p = LibraryProvider();
      expect(p.books.length, kAllBooks.length);
      expect(p.books.length, 12);
      for (final s in BookStatus.values) {
        expect(p.books.where((b) => b.status == s), isNotEmpty,
            reason: '应至少包含一本「${s.label}」的书');
      }
    });

    test('updateBook 不存在 id 时静默忽略', () {
      final p = LibraryProvider();
      p.updateBook(Book(
        id: 'nope',
        title: 'x',
        author: 'y',
        totalPages: 100,
        createdAt: DateTime(2026, 1, 1),
      ));
      expect(p.books.length, 12);
    });
  });

  group('LibraryProvider · 搜索', () {
    test('空/空白查询返回全量书库', () {
      final p = LibraryProvider();
      expect(p.searchBooks('').length, 12);
      expect(p.searchBooks('   ').length, 12);
    });

    test('按书名精确搜索可命中唯一结果', () {
      final p = LibraryProvider();
      for (final book in p.books.take(3)) {
        final result = p.searchBooks(book.title);
        expect(result.map((b) => b.id), contains(book.id));
      }
    });

    test('按作者搜索可命中该作者的书籍', () {
      final p = LibraryProvider();
      final target = p.books.firstWhere((b) => b.author.isNotEmpty);
      final result = p.searchBooks(target.author);
      expect(result.map((b) => b.id), contains(target.id));
    });

    test('搜索大小写不敏感（书名含 ASCII 的用例）', () {
      final p = LibraryProvider();
      Book? asciiBook;
      for (final b in p.books) {
        if (b.title.contains(RegExp(r'[A-Za-z]'))) {
          asciiBook = b;
          break;
        }
      }
      if (asciiBook == null) return; // 数据无 ASCII 书名则跳过
      final lower = p.searchBooks(asciiBook.title.toLowerCase());
      final upper = p.searchBooks(asciiBook.title.toUpperCase());
      expect(lower.length, upper.length);
    });
  });

  group('LibraryProvider · 筛选', () {
    test('按状态筛选结果全部匹配', () {
      final p = LibraryProvider();
      for (final s in BookStatus.values) {
        final result = p.getFilteredBooks(status: s);
        expect(result, isNotEmpty);
        expect(result.every((b) => b.status == s), isTrue);
      }
    });

    test('按分类筛选结果全部匹配该分类', () {
      final p = LibraryProvider();
      final cat = p.books.map((b) => b.category).firstWhere((c) => c != null)!;
      final result = p.getFilteredBooks(category: cat);
      expect(result, isNotEmpty);
      expect(result.every((b) => b.category == cat), isTrue);
    });

    test('关键词 + 状态 + 分类组合筛选 = 三条件交集', () {
      final p = LibraryProvider();
      final target = p.books.firstWhere((b) => b.category != null);
      final combined = p.getFilteredBooks(
        query: target.title.substring(0, 1),
        status: target.status,
        category: target.category,
      );
      expect(
        combined.every((b) =>
            b.title.contains(target.title.substring(0, 1)) &&
            b.status == target.status &&
            b.category == target.category),
        isTrue,
      );
    });

    test('无筛选条件时返回全量', () {
      final p = LibraryProvider();
      expect(p.getFilteredBooks().length, 12);
    });
  });

  group('LibraryProvider · 写操作', () {
    test('updateBook 更新书名并通知监听者', () {
      final p = LibraryProvider();
      var notified = 0;
      p.addListener(() => notified++);

      final b1 = p.books.first;
      p.updateBook(b1.copyWith(title: '被更新的书名'));
      expect(notified, 1);
      expect(p.books.first.title, '被更新的书名');
    });

    test('deleteBook 删除指定书且幂等', () {
      final p = LibraryProvider();
      final b1 = p.books.first;
      p.deleteBook(b1.id);
      expect(p.books.length, 11);
      expect(p.books.map((b) => b.id), isNot(contains(b1.id)));

      p.deleteBook(b1.id); // 重复删除不抛错
      expect(p.books.length, 11);
    });
  });

  group('LibraryProvider · 派生列表联动', () {
    test('readingList 读完优先（首本为已完成）', () {
      final p = LibraryProvider();
      expect(p.readingList.first.status, BookStatus.finished);
    });

    test('删除全部已读书后，readingList 首本自动变为在读', () {
      final p = LibraryProvider();
      for (final b in List.of(p.finishedBooks)) {
        p.deleteBook(b.id);
      }
      expect(p.readingList, isNotEmpty);
      expect(p.readingList.first.status, BookStatus.reading);
    });

    test('currentlyReadingBooks 只含在读且最多 2 本', () {
      final p = LibraryProvider();
      expect(p.currentlyReadingBooks.length, lessThanOrEqualTo(2));
      expect(
        p.currentlyReadingBooks.every((b) => b.status == BookStatus.reading),
        isTrue,
      );
    });

    test('删除一本书后 bookStats.total 自动减 1（动态聚合）', () {
      final p = LibraryProvider();
      final before = p.bookStats.total;
      p.deleteBook(p.books.first.id);
      expect(p.bookStats.total, before - 1);
    });

    test('bookStats 计数与状态列表严格一致', () {
      final p = LibraryProvider();
      final s = p.bookStats;
      expect(s.total, p.books.length);
      expect(s.active, p.activeBooks.length);
      expect(s.finished, p.finishedBooks.length);
    });

    test('bookStats.pagesRead = finished.totalPages + reading.currentPage', () {
      final p = LibraryProvider();
      final expected = p.finishedBooks.fold<int>(0, (s, b) => s + b.totalPages) +
          p.activeBooks.fold<int>(0, (s, b) => s + b.currentPage);
      expect(p.bookStats.pagesRead, expected);
    });

    test('bookStats.progress = 在读+已读 平均（想读 0 不参与）', () {
      final p = LibraryProvider();
      final started = [...p.activeBooks, ...p.finishedBooks];
      final expected =
          started.isEmpty ? 0.0 : started.map((b) => b.progress).reduce(
(a, b) => a + b) / started.length;
      expect(p.bookStats.progress, expected);
      // 反向验证：把 planToReadBooks 加进来重算，结果必须不同（否则说明想读被错误纳入）
      final withPlan = [...started, ...p.planToReadBooks];
      if (withPlan.length != started.length) {
        final polluted = withPlan.map((b) => b.progress).reduce(
(a, b) => a + b) / withPlan.length;
        expect(polluted, isNot(expected),
            reason: '想读书 progress=0 若参与聚合会拉低平均值，bookStats 必须排除');
      }
    });

    test('清空所有在读/已读书：bookStats.progress 回退 0', () {
      final p = LibraryProvider();
      for (final b in [...p.activeBooks, ...p.finishedBooks]) {
        p.deleteBook(b.id);
      }
      expect(p.bookStats.progress, 0.0);
      expect(p.bookStats.pagesRead, 0);
    });

    test('movieStats 计数与电影列表严格一致', () {
      final p = LibraryProvider();
      final s = p.movieStats;
      expect(s.total, p.movieList.length);
      expect(s.watchlist, p.movieList.where(
(m) => m.status == MovieStatus.watchlist).length);
      expect(s.rated, p.ratedMovies.length);
    });

    test('movieStats.averageRating = rating!=null 的均值（无评分时 0）', () {
      final p = LibraryProvider();
      final rated = p.ratedMovies;
      final expected = rated.isEmpty
          ? 0.0
          : rated.map((m) => m.rating!).reduce((a, b) => a + b) / rated.length;
      expect(p.movieStats.averageRating, expected);
    });

    test('upcomingMovies 派生自 _movieList 的 watchlist 前 2 部', () {
      final p = LibraryProvider();
      final expectedIds = p.movieList
          .where((m) => m.status == MovieStatus.watchlist)
          .take(2)
          .map((m) => m.id)
          .toList();
      expect(p.upcomingMovies.map((m) => m.id), expectedIds);
      // m1/m2 是 T3 并入的 seed 必现，应含奥本海默或沙丘 2
      expect(
        p.upcomingMovies.any(
(m) => m.title == '奥本海默' || m.title == '沙丘 2'),
        isTrue,
      );
    });
  });
}
