import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// 图片选择服务抽象（P4 图片上传）
///
/// - 手机/桌面：由 [SystemImagePickService] 接系统相册（image_picker）；
/// - Web / 内存模式：provider 不注入 picker，`canPickImage` 为 false，
///   编辑页据此隐藏「从相册选择」入口；
/// - 测试：注入 fake 返回一个临时文件，即可驱动「选图 → 复制 → 落盘」全链路。
abstract class ImagePickService {
  /// 唤起系统选图；用户取消返回 null
  Future<File?> pickImage();
}

/// 系统相册选图（image_picker：iOS / Android / macOS / Windows 走系统图库）
class SystemImagePickService implements ImagePickService {
  SystemImagePickService();

  final ImagePicker _picker = ImagePicker();

  @override
  Future<File?> pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return null; // 用户取消
    return File(x.path);
  }
}
