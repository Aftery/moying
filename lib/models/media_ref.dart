/// 图片引用（Book 封面 / Movie 海报 / Actor 头像共用）
///
/// 一个字段统一两种图片来源：
/// - 网络拉取：只存 [remoteUrl]，运行时按需加载，不占本地磁盘；
/// - 手动上传：复制进应用私有 images/ 目录后，[localFile] 存相对路径，
///   不依赖原始文件位置（备份恢复后依然有效）。
/// 两者皆空 = 无图，UI 回退到 coverHue + emoji 渐变占位。
class MediaRef {
  const MediaRef({this.remoteUrl, this.localFile});

  /// 网络图片地址（http/https）
  final String? remoteUrl;

  /// 本地图片相对路径（相对应用私有 images/ 目录，如 `m3.jpg`）
  final String? localFile;

  /// 是否为网络图（展示时网络优先，详情见 P4 展示组件）
  bool get isNetwork => remoteUrl != null && remoteUrl!.isNotEmpty;

  /// 是否为本地文件图
  bool get isLocal => localFile != null && localFile!.isNotEmpty;

  /// 是否无图（UI 应回退占位）
  bool get isEmpty => !isNetwork && !isLocal;

  /// 构造网络图引用
  factory MediaRef.network(String url) => MediaRef(remoteUrl: url);

  /// 构造本地文件引用
  factory MediaRef.local(String path) => MediaRef(localFile: path);

  Map<String, dynamic> toJson() => {
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        if (localFile != null) 'localFile': localFile,
      };

  factory MediaRef.fromJson(Map<String, dynamic> json) => MediaRef(
        remoteUrl: json['remoteUrl'] as String?,
        localFile: json['localFile'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaRef &&
          other.remoteUrl == remoteUrl &&
          other.localFile == localFile;

  @override
  int get hashCode => Object.hash(remoteUrl, localFile);

  @override
  String toString() => isEmpty
      ? 'MediaRef.empty'
      : isNetwork
          ? 'MediaRef.network($remoteUrl)'
          : 'MediaRef.local($localFile)';
}
