import 'media_ref.dart';

/// 演员实体（独立集合，actors.json）
///
/// 电影通过 `Movie.actorIds` 单向引用演员；演员的"作品列表"不落盘，
/// 由 Provider 遍历电影库按 actorIds 反查得出（用计算换一致性）。
class Actor {
  const Actor({
    required this.id,
    required this.name,
    this.avatar,
    this.bio,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  /// 唯一标识（如 `a_1725512345678`）
  final String id;

  /// 姓名
  final String name;

  /// 头像（可空：无头像时 UI 用姓名首字占位）
  final MediaRef? avatar;

  /// 个人简介（可空）
  final String? bio;

  /// 创建时间
  final DateTime createdAt;

  /// 最后修改时间（WebDAV 记录级 LWW 合并的时间戳基准；新增即创建时间）
  final DateTime updatedAt;

  /// 复制并替换部分字段
  ///
  /// `avatar` / `bio` 使用 sentinel：省略保留原值，显式传 null 清空。
  Actor copyWith({
    String? name,
    Object? avatar = _unset,
    Object? bio = _unset,
    Object? updatedAt = _unset,
  }) {
    return Actor(
      id: id,
      name: name ?? this.name,
      avatar: _take(avatar, this.avatar),
      bio: _take(bio, this.bio),
      createdAt: createdAt,
      updatedAt: _take(updatedAt, this.updatedAt),
    );
  }

  /// sentinel：区分「省略（保留原值）」与「显式置 null（清空）」
  static const Object _unset = Object();

  /// 取参：省略保留原值，显式传 null(或值) 则采用
  static T? _take<T>(Object? param, T? current) =>
      identical(param, _unset) ? current : param as T?;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (avatar != null) 'avatar': avatar!.toJson(),
        if (bio != null) 'bio': bio,
      };

  factory Actor.fromJson(Map<String, dynamic> json) => Actor(
        id: json['id'] as String,
        name: json['name'] as String,
        avatar: json['avatar'] == null
            ? null
            : MediaRef.fromJson(json['avatar'] as Map<String, dynamic>),
        bio: json['bio'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] == null
            ? DateTime.parse(json['createdAt'] as String) // 旧数据兜底
            : DateTime.parse(json['updatedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Actor &&
          other.id == id &&
          other.name == name &&
          other.avatar == avatar &&
          other.bio == bio &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, avatar, bio, createdAt, updatedAt);
}
