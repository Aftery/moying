/// 多源聚合的搜索结果去重 / 合并（书籍检索用）
///
/// 背景：单个数据源对中文书的覆盖差异很大——Open Library 命中少、字段常缺，
/// Google Books 字段全但国内访问不稳。聚合检索时同一本书会同时出现在多个源
/// 里；若只是把列表首尾相接，用户会看到重复条目（甚至同名书一条有 ISBN、
/// 一条没简介）。这里按稳定键去重，并把互补字段拼起来。
///
/// 去重键（见 [BookResultMerger.dedupeKeys]，一条结果可能同时登记多个键）：
/// 1. `isbn:<10/13 位>` —— 同一本书最可靠的标识；
/// 2. `title:<归一化书名>|<归一化首作者>` —— 无 ISBN 时的兜底
///    （搜索接口常常不返回 ISBN）。
/// 一条结果登记**所有**可用键，这样「源 A 带 ISBN」与「源 B 不带 ISBN」的
/// 同名书也能对上。
library;

import '../models/data_source.dart';

/// 搜索结果去重 / 合并（纯函数、无状态，便于单测）
class BookResultMerger {
  const BookResultMerger._();

  /// 按来源优先级合并多批结果（[batches] 越靠前优先级越高）。
  ///
  /// 同一本书只保留首次出现的记录（来自高优先级源），后续重复项仅用于
  /// 补空缺字段（见 [merge]）——低优先级源不该覆盖高优先级源已给出的值。
  static List<BookSearchResult> mergeAll(
    Iterable<List<BookSearchResult>> batches,
  ) {
    final merged = <BookSearchResult>[];
    final indexByKey = <String, int>{};
    for (final batch in batches) {
      for (final result in batch) {
        final keys = dedupeKeys(result);
        int? hit;
        for (final key in keys) {
          final found = indexByKey[key];
          if (found != null) {
            hit = found;
            break;
          }
        }
        if (hit == null) {
          final at = merged.length;
          merged.add(result);
          for (final key in keys) {
            indexByKey[key] = at;
          }
        } else {
          final at = hit;
          merged[at] = merge(merged[at], result);
          // 合并后可能补上了 ISBN，新键也要登记，避免后续重复项漏判
          for (final key in dedupeKeys(merged[at])) {
            indexByKey.putIfAbsent(key, () => at);
          }
        }
      }
    }
    return merged;
  }

  /// 该条结果的全部去重键；空列表 = 书名与 ISBN 都不可用，
  /// 调用方应视为独立条目（不做去重，避免把空标题全并成一条）。
  static List<String> dedupeKeys(BookSearchResult r) {
    final keys = <String>[];
    final isbn = normalizeIsbn(r.isbn);
    if (isbn != null) keys.add('isbn:$isbn');
    final title = normalizeTitle(r.title);
    if (title.isNotEmpty) {
      final author = r.authors.isEmpty ? '' : normalizeAuthor(r.authors.first);
      keys.add('title:$title|$author');
    }
    return keys;
  }

  /// 合并同一本书的两条记录：以 [base] 为准，[extra] 只补 base 缺的字段。
  ///
  /// 与 [BookSearchResult.mergeWith] 的区别：那个是「详情覆盖搜索」的**覆盖**
  /// 语义，这个是「同级多条记录取并集」的**补缺**语义。
  static BookSearchResult merge(BookSearchResult base, BookSearchResult extra) {
    return BookSearchResult(
      externalId: base.externalId,
      title: base.title,
      authors: base.authors.isNotEmpty ? base.authors : extra.authors,
      publisher: _firstText(base.publisher, extra.publisher),
      year: base.year ?? extra.year,
      isbn: _firstText(base.isbn, extra.isbn),
      pageCount: base.pageCount ?? extra.pageCount,
      coverUrl: _firstText(base.coverUrl, extra.coverUrl),
      rating: base.rating ?? extra.rating,
      description: _firstText(base.description, extra.description),
      categories: _union(base.categories, extra.categories),
    );
  }

  /// ISBN 归一化：去掉连字符与空格；长度非 10/13 或含非法字符返回 null
  /// （部分源的 isbn 字段塞了别的东西，不能直接拿来当键）。
  static String? normalizeIsbn(String? raw) {
    if (raw == null) return null;
    final s = raw.replaceAll(_isbnSeparatorRe, '').toUpperCase();
    if (s.length != 10 && s.length != 13) return null;
    for (var i = 0; i < s.length; i++) {
      final code = s.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39;
      // ISBN-10 最后一位可以是校验符 X
      final isCheckX = s.length == 10 && i == 9 && s[i] == 'X';
      if (!isDigit && !isCheckX) return null;
    }
    return s;
  }

  /// 书名归一化：去括号内容（副标题 / 装帧）→ 去标点与空白 → 转小写。
  ///
  /// `三体 (The Three-Body Problem)`、`三体（精）` 与 `三体` 归一到同一个键，
  /// 否则跨源去重基本失效。注意不去数字与字母——`三体Ⅱ` 与 `三体` 必须保持
  /// 区分，不能被过度归一化并成一本。
  static String normalizeTitle(String raw) => raw
      .toLowerCase()
      .replaceAll(_bracketRe, '')
      .replaceAll(_punctRe, '');

  /// 作者归一化（仅用于比对，不用于展示）
  static String normalizeAuthor(String raw) =>
      raw.toLowerCase().replaceAll(_punctRe, '');

  static String? _firstText(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a;
    if (b != null && b.trim().isNotEmpty) return b;
    return null;
  }

  /// 分类取并集（按小写去重，保留首次出现的大小写形态与顺序）
  static List<String> _union(List<String> a, List<String> b) {
    final out = <String>[...a];
    final seen = a.map((e) => e.toLowerCase()).toSet();
    for (final item in b) {
      if (seen.add(item.toLowerCase())) out.add(item);
    }
    return out;
  }

  static final RegExp _isbnSeparatorRe = RegExp(r'[\s-]');

  /// 括号及其内容：`(精)` / `（平装）` / `[Scribner Classics]`
  static final RegExp _bracketRe = RegExp(r'[（(\[【][^）)\]】]*[）)\]】]');

  /// 标点与空白（中英文）
  static final RegExp _punctRe = RegExp(
    r'''[\s·・:：,，.。;；\-—_/\\|'"“”‘’!！?？*#~`^&+=<>《》]''',
  );
}
