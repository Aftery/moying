import 'media_ref.dart';

/// 用户档案（单例集合，profile.json）
///
/// 与三集合（books/movies/actors）同目录同待遇：原子写、合并写、缺文件回退默认。
/// `themeMode` 一并落在本文件——主题偏好属于用户档案的一部分，P5 备份随之带走。
class UserProfile {
  const UserProfile({
    this.nickname = defaultNickname,
    this.signature,
    this.avatar,
    this.themeMode = 'dark',
  });

  /// 无档案时的默认昵称（与个人页历史文案一致）
  static const String defaultNickname = '书友';

  /// 昵称（必填语义；编辑 UI 保证非空后才提交）
  final String nickname;

  /// 个性签名（可空）
  final String? signature;

  /// 头像（可空：无头像时 UI 用昵称首字/占位图标）
  final MediaRef? avatar;

  /// 主题偏好：'dark' / 'light' / 'system'
  final String themeMode;

  /// 复制并替换部分字段
  ///
  /// `signature` / `avatar` 使用 sentinel：省略保留原值，显式传 null 清空。
  UserProfile copyWith({
    String? nickname,
    Object? signature = _unset,
    Object? avatar = _unset,
    String? themeMode,
  }) {
    return UserProfile(
      nickname: nickname ?? this.nickname,
      signature: _take(signature, this.signature),
      avatar: _take(avatar, this.avatar),
      themeMode: themeMode ?? this.themeMode,
    );
  }

  /// sentinel：区分「省略（保留原值）」与「显式置 null（清空）」
  static const Object _unset = Object();

  /// 取参：省略保留原值，显式传 null(或值) 则采用
  static T? _take<T>(Object? param, T? current) =>
      identical(param, _unset) ? current : param as T?;

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'themeMode': themeMode,
        if (signature != null) 'signature': signature,
        if (avatar != null) 'avatar': avatar!.toJson(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        nickname: (json['nickname'] as String?)?.trim().isEmpty ?? true
            ? defaultNickname
            : json['nickname'] as String,
        signature: json['signature'] as String?,
        avatar: json['avatar'] == null
            ? null
            : MediaRef.fromJson(json['avatar'] as Map<String, dynamic>),
        themeMode: json['themeMode'] as String? ?? 'dark',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.nickname == nickname &&
          other.signature == signature &&
          other.avatar == avatar &&
          other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(nickname, signature, avatar, themeMode);
}
