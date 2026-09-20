import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 单图压缩 / 上限服务（M9：压缩到 5MB 以内再落盘）
///
/// 设计契约：
/// - 只处理 jpg/jpeg/png（按 magic bytes 探活，不依赖扩展名）；
///   webp/gif 等其它格式 `decodeImage` 返回 null → 调用方回退原图。
/// - 流程：decode → 等比缩到长边 [maxSide] → encodeJpg([quality])。
/// - 压缩后字节反而更大（已高度压缩的照片）时回退原图，避免无谓体积膨胀。
/// - 用 `compute` 跑独立 isolate，解码大图不阻塞 UI。
///
/// [compressImage] 返回压缩后的 jpg 字节；无法处理 / 不划算时返回 null，
/// 由调用方自行决定用原图还是拒绝。
class ImageCompressService {
  const ImageCompressService();

  /// 把图片字节压缩为长边 ≤ [maxSide]、质量 [quality] 的 jpg。
  /// 无法解码 / 压缩后更大时返回 null。
  Future<Uint8List?> compressImage(
    Uint8List bytes, {
    int maxSide = 1600,
    int quality = 85,
  }) {
    return compute(
      _compressIsolate,
      _CompressArgs(bytes, maxSide, quality),
    );
  }
}

/// isolate 入参（按值复制到子 isolate）
class _CompressArgs {
  const _CompressArgs(this.bytes, this.maxSide, this.quality);

  final Uint8List bytes;
  final int maxSide;
  final int quality;
}

/// 顶层函数（compute 要求顶层或静态、不可闭包）
Uint8List? _compressIsolate(_CompressArgs args) {
  final original = args.bytes;
  // JPEG: FF D8 / PNG: 89 50 4E 47；其它格式跳过
  final isJpeg = original.length >= 2 && original[0] == 0xFF && original[1] == 0xD8;
  final isPng = original.length >= 4 &&
      original[0] == 0x89 &&
      original[1] == 0x50 &&
      original[2] == 0x4E &&
      original[3] == 0x47;
  if (!isJpeg && !isPng) return null;

  final decoded = isJpeg ? img.decodeJpg(original) : img.decodePng(original);
  if (decoded == null) return null; // 损坏 / 不支持 → 回退原图

  final w = decoded.width;
  final h = decoded.height;
  img.Image out = decoded;
  if (w > args.maxSide || h > args.maxSide) {
    final scale = args.maxSide / (w > h ? w : h);
    out = img.copyResize(
      decoded,
      width: (w * scale).round(),
      height: (h * scale).round(),
    );
  }

  final compressed = img.encodeJpg(out, quality: args.quality);
  // 压缩后反而更大 → 回退原图（decode/encode 有开销但体积不降）
  if (compressed.length >= original.length) return null;
  return Uint8List.fromList(compressed);
}
