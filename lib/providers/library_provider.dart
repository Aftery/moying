import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/library_store.dart';
import '../data/mock_data.dart';
import '../models/actor.dart';
import '../models/book.dart';
import '../models/media_ref.dart';
import '../models/movie.dart';
import '../models/stats.dart';
import '../models/user_profile.dart';
import '../services/image_pick_service.dart';

/// 全局书影库状态（ChangeNotifier，配合 Provider 使用）
///
/// 双模式：
/// - **内存模式**（不传 [store]）：以 mock 数据初始化，不落盘——
///   UI 预览 / 既有测试 / Web 运行均走此模式，行为与持久化前完全一致；
/// - **持久模式**（传 [store]）：构造后必须先 `await init()` 从盘加载，
///   之后每次写操作（增/改/删书、电影、演员）尾部触发**合并写**持久化
///   （见 [LibraryStore]），内存先更新、磁盘异步追赶，UI 无感。
///
/// UI 层只通过 getter 消费，两种模式对外接口一致。
class LibraryProvider extends ChangeNotifier {
  LibraryProvider({LibraryStore? store, ImagePickService? picker})
      : _store = store,
        _picker = picker;

  /// 持久化存储（null = 内存模式）
  final LibraryStore? _store;

  /// 图片选择服务（null = 不支持选图：Web / 内存模式）
  final ImagePickService? _picker;

  /// 是否持久模式（接入了本地存储）
  bool get isPersistent => _store != null;

  /// 是否可唤起系统选图（持久模式 + 已注入 picker）
  bool get canPickImage => _picker != null;

  /// 全量书库（图书模块唯一可变数据源，支持增删改）
  List<Book> _books = List.of(kAllBooks);

  /// 想看电影演示集（独立于持久化的三集合，固定来自 mock）
  List<Movie> _movieList = List.of(kMovieList);

  /// 演员实体集合（actors.json，电影通过 actorIds 单向引用）
  List<Actor> _actors = List.of(kActors);

  /// 用户档案（profile.json 单例；内存模式用默认档案）
  UserProfile _userProfile = const UserProfile();

  /// 从存储加载全部数据（持久模式初始化入口，内存模式为 no-op）。
  ///
  /// main() 中 `await` 完成后再 runApp，避免启动闪现 seed 数据。
  Future<void> init() async {
    final store = _store;
    if (store == null) return; // 内存模式
    final snap = await store.load();
    _books = List.of(snap.books);
    _movieList = List.of(snap.movies);
    _actors = List.of(snap.actors);
    _userProfile = await store.loadProfile();
    notifyListeners();
  }

  /// 立即把未落盘的合并写冲盘（App 生命周期挂起/退出前调用）
  Future<void> flush() async => _store?.flush();

  // ==================== 用户档案与主题偏好 ====================

  /// 当前用户档案（单例，profile.json）
  UserProfile get userProfile => _userProfile;

  /// 更新用户档案（头像变更时回收旧图；持久模式落盘 profile.json）
  Future<void> updateProfile(UserProfile updated) async {
    _recycleImage(_userProfile.avatar, updated.avatar);
    _userProfile = updated;
    notifyListeners();
    await _store?.saveProfile(updated);
  }

  /// 主题偏好（'dark' / 'light' / 'system'，随档案持久化）
  String get themeMode => _userProfile.themeMode;

  /// 切换主题偏好（内部复用 updateProfile 落盘）
  Future<void> setThemeMode(String mode) async {
    if (mode == _userProfile.themeMode) return;
    await updateProfile(_userProfile.copyWith(themeMode: mode));
  }

  // ==================== 图片管线（P4） ====================

  /// 唤起系统选图（无 picker 返回 null）
  Future<File?> pickImageFile() async => _picker?.pickImage();

  /// 复制图片进 `images/<entryId><ext>`，返回 [MediaRef.localFile] 相对名。
  ///
  /// 内存模式（无 store）返回 null——调用方需保证仅在持久模式调用。
  Future<String?> attachImage(File source, String entryId) async {
    final s = _store;
    if (s == null) return null;
    return s.copyImage(source, entryId);
  }

  /// 解析本地图相对名 → 展示用 File；无 store / 非法路径返回 null（渲染层兜底占位）。
  File? resolveLocalImage(String? localFile) {
    final s = _store;
    if (s == null || localFile == null) return null;
    try {
      return s.resolveImageFile(localFile);
    } on StoreException {
      return null;
    }
  }

  /// 回收被替换/删除条目的孤儿图片（fire-and-forget，无 store 时 no-op）
  void _recycleImage(MediaRef? old, MediaRef? updated) {
    final s = _store;
    final oldFile = old?.localFile;
    if (s == null || oldFile == null) return;
    if (oldFile == updated?.localFile) return; // 封面未变
    unawaited(s.deleteImage(oldFile));
  }

  // ==================== 写后持久化（合并写，fire-and-forget） ====================

  void _persistBooks() {
    final s = _store;
    if (s != null) unawaited(s.saveBooks(_books));
  }

  void _persistMovies() {
    final s = _store;
    if (s != null) unawaited(s.saveMovies(_movieList));
  }

  void _persistActors() {
    final s = _store;
    if (s != null) unawaited(s.saveActors(_actors));
  }

  // ==================== 书库查询 ====================

  /// 全量书库（图书模块列表页/筛选/搜索的数据源）
  List<Book> get books => List.unmodifiable(_books);

  /// 仪表盘「阅读列表」展示的书目（读完优先，最多 6 本，保持旧观感）
  List<Book> get readingList {
    const order = {
      BookStatus.finished: 0,
      BookStatus.reading: 1,
      BookStatus.planToRead: 2,
    };
    final sorted = List.of(_books)
      ..sort((a, b) => order[a.status]!.compareTo(order[b.status]!));
    return sorted.take(6).toList();
  }

  /// 当前在读书籍（仪表盘横向任务卡，最多 2 本）
  List<Book> get currentlyReadingBooks =>
      _books.where((b) => b.status == BookStatus.reading).take(2).toList();

  /// 在读书籍
  List<Book> get activeBooks =>
      _books.where((b) => b.status == BookStatus.reading).toList();

  /// 已读完书籍
  List<Book> get finishedBooks =>
      _books.where((b) => b.status == BookStatus.finished).toList();

  /// 想读书籍
  List<Book> get planToReadBooks =>
      _books.where((b) => b.status == BookStatus.planToRead).toList();

  /// 阅读统计聚合（仪表盘 StatsCard 数据源；实时计算，保证与列表状态一致）
  ///
  /// - pagesRead：`finished` 的 `totalPages` 之和 + `reading` 的 `currentPage` 之和（想读不贡献）
  /// - progress：在读 + 已读 书的 `progress` 算术平均（想读不参与，避免 0 拉低）
  BookStats get bookStats {
    final finished = _books.where((b) => b.status == BookStatus.finished);
    final reading = _books.where((b) => b.status == BookStatus.reading);
    final pagesRead = finished.fold<int>(0, (s, b) => s + b.totalPages) +
        reading.fold<int>(0, (s, b) => s + b.currentPage);
    final started = [...finished, ...reading];
    final avgProgress = started.isEmpty
        ? 0.0
        : started.map((b) => b.progress).reduce((a, b) => a + b) /
            started.length;
    return BookStats(
      total: _books.length,
      active: reading.length,
      finished: finished.length,
      pagesRead: pagesRead,
      progress: avgProgress,
    );
  }

  // ==================== 搜索与筛选 ====================

  /// 按书名/作者模糊搜索（不区分大小写）
  List<Book> searchBooks(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_books);
    return _books
        .where((b) =>
            b.title.toLowerCase().contains(q) ||
            b.author.toLowerCase().contains(q))
        .toList();
  }

  /// 组合筛选：关键词 + 阅读状态 + 分类（均为可选项，null 表示不过滤）
  List<Book> getFilteredBooks({
    String? query,
    BookStatus? status,
    String? category,
  }) {
    Iterable<Book> result = _books;
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      result = result.where((b) =>
          b.title.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q));
    }
    if (status != null) {
      result = result.where((b) => b.status == status);
    }
    if (category != null && category.isNotEmpty) {
      result = result.where((b) => b.category == category);
    }
    return result.toList();
  }

  /// 所有已被书目使用的分类（供筛选下拉动态生成，去重）
  List<String> get usedCategories =>
      _books.map((b) => b.category).whereType<String>().toSet().toList();

  // ==================== 书库写操作 ====================

  /// 新增一本书（插入列表头部，网格立即刷新）
  void addBook(Book book) {
    _books.insert(0, book);
    notifyListeners();
    _persistBooks();
  }

  /// 更新一本已有的书（按 id 匹配），不存在则忽略
  void updateBook(Book updated) {
    final i = _books.indexWhere((b) => b.id == updated.id);
    if (i < 0) return;
    final old = _books[i];
    if (old.cover != null) _recycleImage(old.cover, updated.cover);
    _books[i] = updated;
    notifyListeners();
    _persistBooks();
  }

  /// 按 id 删除一本书（回收其封面图片文件）
  void deleteBook(String id) {
    final i = _books.indexWhere((b) => b.id == id);
    if (i < 0) return;
    final old = _books[i];
    _books.removeAt(i);
    if (old.cover != null) _recycleImage(old.cover, null);
    notifyListeners();
    _persistBooks();
  }

  // ==================== 电影 ====================

  /// 待看/未评分电影
  List<Movie> get watchlistMovies =>
      _movieList.where((m) => m.status == MovieStatus.watchlist).toList();

  /// 已评分电影
  List<Movie> get ratedMovies =>
      _movieList.where((m) => m.rating != null).toList();

  /// 全部电影（仪表盘网格/电影库）
  List<Movie> get movieList => List.unmodifiable(_movieList);

  /// 想看电影（仪表盘横向任务卡）—— 来自电影库真实 watchlist，前 2 部
  List<Movie> get upcomingMovies => List.unmodifiable(_movieList
      .where((m) => m.status == MovieStatus.watchlist)
      .take(2)
      .toList());

  /// 电影统计聚合（仪表盘 StatsCard 数据源；实时计算，保证与列表状态一致）
  ///
  /// - rated：`rating != null` 计数
  /// - averageRating：已评分电影的平均评分（0-5；无已评分时为 0）
  MovieStats get movieStats {
    final rated = _movieList.where((m) => m.rating != null).toList();
    final avg = rated.isEmpty
        ? 0.0
        : rated.map((m) => m.rating!).reduce((a, b) => a + b) / rated.length;
    return MovieStats(
      total: _movieList.length,
      watchlist: _movieList
          .where((m) => m.status == MovieStatus.watchlist)
          .length,
      rated: rated.length,
      averageRating: avg,
    );
  }

  // ==================== 电影搜索/筛选/排序 ====================

  /// 按片名/导演模糊搜索（不区分大小写）
  List<Movie> searchMovies(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_movieList);
    return _movieList
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            (m.director ?? '').toLowerCase().contains(q))
        .toList();
  }

  /// 组合筛选 + 排序（电影列表页数据源）
  ///
  /// - [query]：按片名/导演模糊过滤，null/空串 不过滤
  /// - [genre]：按类型精确过滤，null/空串 不过滤
  /// - [sort]：排序方式，见 [MovieSort]
  List<Movie> getFilteredMovies({
    String? query,
    String? genre,
    MovieSort sort = MovieSort.ratingHigh,
  }) {
    Iterable<Movie> result = _movieList;
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      result = result.where((m) =>
          m.title.toLowerCase().contains(q) ||
          (m.director ?? '').toLowerCase().contains(q));
    }
    if (genre != null && genre.isNotEmpty) {
      result = result.where(
          (m) => m.genres != null && m.genres!.contains(genre));
    }
    final list = result.toList();
    // 排序（切换下拉框时界面借助 setState/notifyListeners 实时更新）
    switch (sort) {
      case MovieSort.ratingHigh:
        // 有评分在前，按分数降序；未评分固定在末尾
        list.sort((a, b) {
          if (a.rating == null && b.rating == null) return 0;
          if (a.rating == null) return 1;
          if (b.rating == null) return -1;
          return b.rating!.compareTo(a.rating!);
        });
      case MovieSort.dateWatchedNewest:
        // 看过日期倒序；无看过日期排在末尾
        list.sort((a, b) {
          if (a.watchDate == null && b.watchDate == null) return 0;
          if (a.watchDate == null) return 1;
          if (b.watchDate == null) return -1;
          return b.watchDate!.compareTo(a.watchDate!);
        });
      case MovieSort.releaseNewest:
        // 上映日期倒序；无上映日期排在末尾
        list.sort((a, b) {
          if (a.releaseDate == null && b.releaseDate == null) return 0;
          if (a.releaseDate == null) return 1;
          if (b.releaseDate == null) return -1;
          return b.releaseDate!.compareTo(a.releaseDate!);
        });
    }
    return list;
  }

  /// 所有已被电影使用的类型（供筛选下拉生成，去重）
  List<String> get usedMovieGenres =>
      _movieList
          .map((m) => m.genres ?? const <String>[])
          .expand((g) => g)
          .toSet()
          .toList();

  // ==================== 电影写操作 ====================

  /// 新增一部电影（追加到列表尾部）
  void addMovie(Movie movie) {
    _movieList.add(movie);
    notifyListeners();
    _persistMovies();
  }

  /// 更新一部已有的电影（按 id 匹配），不存在则忽略
  void updateMovie(Movie updated) {
    final i = _movieList.indexWhere((m) => m.id == updated.id);
    if (i < 0) return;
    final old = _movieList[i];
    if (old.poster != null) _recycleImage(old.poster, updated.poster);
    _movieList[i] = updated;
    notifyListeners();
    _persistMovies();
  }

  /// 按 id 删除一部电影（回收其海报图片文件）
  void deleteMovie(String id) {
    final i = _movieList.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final old = _movieList[i];
    _movieList.removeAt(i);
    if (old.poster != null) _recycleImage(old.poster, null);
    notifyListeners();
    _persistMovies();
  }

  // ==================== 演员 ====================

  /// 全部演员实体（演员库 / 编辑页联想候选数据源）
  List<Actor> get actors => List.unmodifiable(_actors);

  /// 新增演员
  void addActor(Actor actor) {
    _actors.add(actor);
    notifyListeners();
    _persistActors();
  }

  /// 更新演员（按 id 匹配），不存在则忽略
  void updateActor(Actor updated) {
    final i = _actors.indexWhere((a) => a.id == updated.id);
    if (i < 0) return;
    final old = _actors[i];
    if (old.avatar != null) _recycleImage(old.avatar, updated.avatar);
    _actors[i] = updated;
    notifyListeners();
    _persistActors();
  }

  /// 按 id 取多个演员（保持 [ids] 顺序，缺失静默跳过——渲染层对悬空引用兜底）
  List<Actor> actorsByIds(Iterable<String> ids) {
    final byId = {for (final a in _actors) a.id: a};
    return ids.map((id) => byId[id]).whereType<Actor>().toList();
  }

  /// 演员参与的电影（遍历反查，用计算换一致性，不落盘作品列表）
  List<Movie> moviesByActor(String actorId) => _movieList
      .where((m) => m.actorIds != null && m.actorIds!.contains(actorId))
      .toList();

  /// 删除演员；仍被电影引用时拒绝删除并返回 false（调用方提示引用关系）。
  ///
  /// 被引用数量少时直接查 [moviesByActor] 组装提示文案。
  bool deleteActor(String id) {
    if (moviesByActor(id).isNotEmpty) return false;
    final i = _actors.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    final old = _actors[i];
    _actors.removeAt(i);
    if (old.avatar != null) _recycleImage(old.avatar, null);
    notifyListeners();
    _persistActors();
    return true;
  }
}
