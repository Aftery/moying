import 'package:flutter/foundation.dart' show listEquals;

import 'data_source.dart' show CastMember;
import 'media_ref.dart';

/// 观影状态
enum MovieStatus {
  /// 想看（清单内）
  watchlist('想看'),

  /// 已看过
  watched('已看'),

  /// 已评分
  rated('已评分');

  const MovieStatus(this.label);

  /// 中文展示名
  final String label;
}

/// 列表页排序方式（切换排序下拉时实时生效）
enum MovieSort {
  /// 评分最高 → 按评分从高到低（未评分排在末尾）
  ratingHigh('评分最高'),

  /// 观影时间最新 → 按看过日期倒序（无看过日期排在末尾）
  dateWatchedNewest('观影时间最新'),

  /// 上映时间最新 → 按上映日期倒序（无上映日期排在末尾）
  releaseNewest('上映时间最新');

  const MovieSort(this.label);

  /// 下拉框展示名
  final String label;
}

/// 可选电影分类（列表筛选与编辑页 Tag 共用同一数据源）
const List<String> kMovieCategories = [
  '科幻',
  '冒险',
  '悬疑',
  '剧情',
  '动画',
  '奇幻',
  '动作',
  '爱情',
  '喜剧',
  '犯罪',
  '战争',
  '传记',
];

/// 电影记录模型
class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.year,
    this.englishTitle,
    this.director,
    this.status = MovieStatus.watchlist,
    this.rating,
    this.coverHue = 165,
    this.emoji,
    this.releaseDate,
    this.watchDate,
    this.duration,
    this.genres,
    this.description,
    this.review,
    this.actorIds,
    this.poster,
    this.cast,
    this.stills,
    this.source,
    this.updatedAt,
  });

  /// 唯一标识
  final String id;

  /// 片名
  final String title;

  /// 英文名
  final String? englishTitle;

  /// 上映年份（兼容旧字段，列表卡片等轻量展示用）
  final int year;

  /// 导演
  final String? director;

  /// 观影状态
  final MovieStatus status;

  /// 评分（0-5，可为空）
  final double? rating;

  /// 占位封面主色相
  final double coverHue;

  /// 占位封面 emoji
  final String? emoji;

  /// 完整上映日期（如 2014-11-07）
  final DateTime? releaseDate;

  /// 看过日期（如 2023-11-05）
  final DateTime? watchDate;

  /// 片长（分钟）
  final int? duration;

  /// 剧情类型（来自 [kMovieCategories]）
  final List<String>? genres;

  /// 电影简介
  final String? description;

  /// 我的影评
  final String? review;

  /// 主要演员引用（存 [Actor](actor.dart).id；过渡期 mock 数据暂存姓名，
  /// P2a seed 实体化后统一回填为 Actor.id）
  final List<String>? actorIds;

  /// 海报图引用（可空：无图时 UI 用 coverHue + emoji 渐变占位）
  final MediaRef? poster;

  /// 演职员表快照（可空）
  ///
  /// 与 [actorIds] 的分工：后者引用本地 [Actor] 实体（用于「参演作品」反查），
  /// 这里是**这部电影**的演职员快照，带角色名与头像——角色名不能存 Actor 上
  /// （同一演员在不同片中角色不同），故按片存快照。
  /// 空数组语义 = 该片确实无演职员信息（不落盘时为 null = 未知）。
  final List<CastMember>? cast;

  /// 剧照缓存（可空）：TMDB images.backdrops 的完整 URL，落盘后离线可看
  ///
  /// 存 [MediaRef.network] 而非字符串——复用现有图片展示与序列化链路。
  final List<MediaRef>? stills;

  /// 数据溯源标记（可空：P6 网络补全落地后记录来源与外部 id，如 tmdbId）
  final String? source;

  /// 最后修改时间（WebDAV 记录级 LWW 合并的时间戳基准）
  ///
  /// 可空 = 从未修改过（旧数据 / 未编辑的想看电影），合并时视为最旧、
  /// 让位于任何带时间戳的一端；可空设计同时保证 const 构造器可用
  /// （DateTime 无 const 构造，无法在初始化列表里做非空兜底）。
  final DateTime? updatedAt;

  /// 是否有评分
  bool get hasRating => rating != null;

  /// 格式化年份（例如 "2023"）
  String get yearText => '$year';

  /// 上映日期展示文本（如 "2014-11-07"）
  String get releaseDateText {
    final d = releaseDate;
    if (d == null) return '';
    return _fmtDate(d);
  }

  /// 看过日期展示文本（如 "2023-11-05"）
  String get watchDateText {
    final d = watchDate;
    if (d == null) return '';
    return _fmtDate(d);
  }

  /// 片长展示文本（如 "169 分钟"）
  String get durationText => duration == null ? '' : '$duration 分钟';

  /// 类型展示文本（如 "科幻 / 冒险 / 悬疑"）
  String get genresText {
    final g = genres;
    if (g == null || g.isEmpty) return '';
    return g.join(' / ');
  }

  static String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// 复制并替换部分字段（编辑页保存时构造新实例）
  ///
  /// 与 [Book.copyWith] 的差异：电影表单的 Tag 多选/演员列表/影评文本框
  /// 均可被「清空」，因此可空字段使用 sentinel 机制——传 null 表示清空，
  /// 省略参数表示保留原值。例：`copyWith(review: null)` 清空影评。
  Movie copyWith({
    String? title,
    Object? englishTitle = _unset,
    Object? director = _unset,
    MovieStatus? status,
    double? rating,
    double? coverHue,
    String? emoji,
    int? year,
    Object? releaseDate = _unset,
    Object? watchDate = _unset,
    Object? duration = _unset,
    Object? genres = _unset,
    Object? description = _unset,
    Object? review = _unset,
    Object? actorIds = _unset,
    Object? poster = _unset,
    Object? cast = _unset,
    Object? stills = _unset,
    Object? source = _unset,
    Object? updatedAt = _unset,
  }) {
    return Movie(
      id: id,
      title: title ?? this.title,
      englishTitle: _take(englishTitle, this.englishTitle),
      director: _take(director, this.director),
      status: status ?? this.status,
      rating: rating ?? this.rating,
      coverHue: coverHue ?? this.coverHue,
      emoji: _take(emoji, this.emoji),
      year: year ?? this.year,
      releaseDate: _take(releaseDate, this.releaseDate),
      watchDate: _take(watchDate, this.watchDate),
      duration: _take(duration, this.duration),
      genres: _take(genres, this.genres),
      description: _take(description, this.description),
      review: _take(review, this.review),
      actorIds: _take(actorIds, this.actorIds),
      poster: _take(poster, this.poster),
      cast: _take(cast, this.cast),
      stills: _take(stills, this.stills),
      source: _take(source, this.source),
      updatedAt: _take(updatedAt, this.updatedAt),
    );
  }

  /// sentinel：区分「省略（保留原值）」与「显式置 null（清空）」
  static const Object _unset = Object();

  /// 取参：省略保留原值，显式传 null(或值) 则采用
  static T? _take<T>(Object? param, T? current) =>
      identical(param, _unset) ? current : param as T?;

  // ==================== 序列化 ====================
  //
  // 约定与 [Book] 一致：必填总写、可空 null 省略、枚举存 name、
  // DateTime 存本地 ISO8601、列表非 null 即写（空数组与 null 语义不同）。

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'year': year,
        'status': status.name,
        'coverHue': coverHue,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (englishTitle != null) 'englishTitle': englishTitle,
        if (director != null) 'director': director,
        if (rating != null) 'rating': rating,
        if (emoji != null) 'emoji': emoji,
        if (releaseDate != null) 'releaseDate': releaseDate!.toIso8601String(),
        if (watchDate != null) 'watchDate': watchDate!.toIso8601String(),
        if (duration != null) 'duration': duration,
        if (genres != null) 'genres': genres,
        if (description != null) 'description': description,
        if (review != null) 'review': review,
        if (actorIds != null) 'actorIds': actorIds,
        if (poster != null) 'poster': poster!.toJson(),
        if (cast != null) 'cast': cast!.map((c) => c.toJson()).toList(),
        if (stills != null) 'stills': stills!.map((s) => s.toJson()).toList(),
        if (source != null) 'source': source,
      };

  factory Movie.fromJson(Map<String, dynamic> json) {
    final watchDate = json['watchDate'] == null
        ? null
        : DateTime.parse(json['watchDate'] as String);
    return Movie(
        id: json['id'] as String,
        title: json['title'] as String,
        year: (json['year'] as num).toInt(),
        status: json['status'] == null
            ? MovieStatus.watchlist
            : MovieStatus.values.byName(json['status'] as String),
        coverHue: (json['coverHue'] as num?)?.toDouble() ?? 165,
        englishTitle: json['englishTitle'] as String?,
        director: json['director'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        emoji: json['emoji'] as String?,
        releaseDate: json['releaseDate'] == null
            ? null
            : DateTime.parse(json['releaseDate'] as String),
        watchDate: watchDate,
        duration: (json['duration'] as num?)?.toInt(),
        genres: (json['genres'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        description: json['description'] as String?,
        review: json['review'] as String?,
        actorIds: (json['actorIds'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        poster: json['poster'] == null
            ? null
            : MediaRef.fromJson(json['poster'] as Map<String, dynamic>),
        cast: (json['cast'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(CastMember.fromJson)
            .toList(),
        stills: (json['stills'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(MediaRef.fromJson)
            .toList(),
        source: json['source'] as String?,
        updatedAt: json['updatedAt'] == null
            ? null // 旧数据兜底：无 updatedAt = 从未修改，合并时视为最旧
            : DateTime.parse(json['updatedAt'] as String),
      );
  }

  // ==================== 值相等（round-trip 测试与数据保持断言用）====================

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Movie &&
          other.id == id &&
          other.title == title &&
          other.englishTitle == englishTitle &&
          other.year == year &&
          other.director == director &&
          other.status == status &&
          other.rating == rating &&
          other.coverHue == coverHue &&
          other.emoji == emoji &&
          other.releaseDate == releaseDate &&
          other.watchDate == watchDate &&
          other.updatedAt == updatedAt &&
          other.duration == duration &&
          listEquals(other.genres, genres) &&
          other.description == description &&
          other.review == review &&
          listEquals(other.actorIds, actorIds) &&
          other.poster == poster &&
          listEquals(other.cast, cast) &&
          listEquals(other.stills, stills) &&
          other.source == source;

  // Object.hash 仅支持 20 个位置参数，字段超量后改用 hashAll（Book 同款教训）
  @override
  int get hashCode => Object.hashAll([
        id,
        title,
        englishTitle,
        year,
        director,
        status,
        rating,
        coverHue,
        emoji,
        releaseDate,
        watchDate,
        updatedAt,
        duration,
        genres == null ? null : Object.hashAll(genres!),
        description,
        review,
        actorIds == null ? null : Object.hashAll(actorIds!),
        poster,
        cast == null ? null : Object.hashAll(cast!),
        stills == null ? null : Object.hashAll(stills!),
        source,
      ]);
}