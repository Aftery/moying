/// 演员展示条目（展示层模型，统一「Movie.cast 快照」与「本地 Actor 实体」）
///
/// 为什么需要它：[Movie.cast] 是数据层快照（[CastMember]，含角色名与 TMDB 头像），
/// 本地 [Actor] 实体则没有角色概念（同一演员在不同片中角色不同，不宜存实体上）。
/// 详情页把两者归一为 [CastItem] 后交给 UI，UI 只需面对一种结构。
///
/// [actorId] 由姓名匹配本地演员库得出，为 null 表示该演员未收录——
/// 此时点击不跳转作品页（跳过去也是空列表）。
class CastItem {
  const CastItem({
    required this.name,
    this.character,
    this.photoUrl,
    this.actorId,
  });

  /// 演员姓名
  final String name;

  /// 饰演角色（仅 cast 快照携带，本地实体回退时为 null）
  final String? character;

  /// 头像完整 URL（TMDB profile_path 已拼好 base；本地实体的网络头像）
  final String? photoUrl;

  /// 本地 Actor id（null = 未收录）
  final String? actorId;

  /// 导演行约定角色名
  ///
  /// 详情页为 [Movie.director] 单独构造条目时用此值填充 [character]，
  /// 弹层据此把该条目分到「导演」组（其余为「主要演员」）。
  static const String kDirectorRole = '导演';

  /// 是否可跳转到作品页
  bool get canOpen => actorId != null;

  /// 是否为导演行
  bool get isDirector => character == kDirectorRole;

  /// 角色展示文本（无角色时回退空串，UI 决定是否显示该行）
  String get characterText => character ?? '';
}
