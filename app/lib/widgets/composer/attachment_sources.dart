/// 附件入口：相册、相机、系统文件选择器。
///
/// 对齐 dsh Web 的 `+` 菜单三项来源；Web 端的剪贴板粘贴图片本轮不做
/// （当前 Flutter SDK 的 Clipboard 只支持文本，image_picker 也没有剪贴板取图接口）。
/// 鸿蒙侧分别由 `image_picker_harmonyos` 与 `file_selector_ohos` 提供
/// 联邦实现，调用失败时统一降级为可读提示而不是崩溃。
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';

/// 一次选择的产出：本地路径列表 + 可选的整体错误。
class AttachmentPick {
  final List<String> paths;
  final String? error;

  const AttachmentPick({this.paths = const [], this.error});

  bool get isEmpty => paths.isEmpty && error == null;
}

class AttachmentSources {
  final ImagePicker picker;

  AttachmentSources({ImagePicker? picker}) : picker = picker ?? ImagePicker();

  /// 相册多选；limit 由剩余可添加图片数决定。
  Future<AttachmentPick> pickImages({required int limit}) async {
    if (limit <= 0) {
      return const AttachmentPick(error: '图片数量已达上限');
    }
    try {
      final files = await picker.pickMultiImage(limit: limit);
      return AttachmentPick(paths: await _pathsOf(files));
    } catch (_) {
      return const AttachmentPick(error: '当前设备不支持选择图片');
    }
  }

  /// 相机拍照（单张）。
  Future<AttachmentPick> capturePhoto() async {
    try {
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file == null) return const AttachmentPick();
      return AttachmentPick(paths: await _pathsOf([file]));
    } catch (_) {
      return const AttachmentPick(error: '当前设备不支持拍照');
    }
  }

  /// 系统文件选择器：任意类型，选中即交给 AttachmentStore 排队上传。
  Future<AttachmentPick> pickFiles() async {
    try {
      final files = await openFiles();
      return AttachmentPick(paths: await _pathsOf(files));
    } catch (_) {
      return const AttachmentPick(error: '当前设备不支持选择文件');
    }
  }

  /// 选择器给出的通常是本地路径；拿不到路径时落到临时文件保证可读。
  static Future<List<String>> _pathsOf(List<XFile> files) async {
    final paths = <String>[];
    for (final file in files) {
      final path = file.path;
      if (path.isNotEmpty) {
        paths.add(path);
        continue;
      }
      try {
        final target = File(
          '${Directory.systemTemp.path}/dsh-${DateTime.now().microsecondsSinceEpoch}-${file.name}',
        );
        await file.saveTo(target.path);
        paths.add(target.path);
      } catch (_) {
        continue;
      }
    }
    return paths;
  }
}
