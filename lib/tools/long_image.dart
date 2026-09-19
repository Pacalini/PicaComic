import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pica_comic/foundation/log.dart';

/// 导出长图时允许的最大宽度, 原图窄于这个宽度时不会被放大
const int longImageMaxWidth = 1080;

/// 输出图片的像素数上限, 超过时整体等比缩小, 避免使用过多内存
const int maxLongImagePixels = 64 * 1024 * 1024;

/// 图片扩展名, 用于过滤出漫画图片, 排除 cover 与 info.json
const _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'];

/// 把一话已下载的图片竖向拼成一张长图
///
/// [comicPath] 为漫画目录, [chapterIndex] 为 null 时表示该漫画没有章节
/// (图片直接存放于漫画目录下), 否则读取 [comicPath]/[chapterIndex + 1] 目录。
///
/// 返回生成的图片文件, 失败时抛出异常。
Future<File> createLongImageFromChapter({
  required String comicPath,
  int? chapterIndex,
  required String savePath,
  int maxWidth = longImageMaxWidth,
}) {
  return Isolate.run(() => _createLongImage(
        comicPath: comicPath,
        chapterIndex: chapterIndex,
        savePath: savePath,
        maxWidth: maxWidth,
      ));
}

/// 列出某一话的所有图片, 按文件名中的数字顺序排列
List<File> listChapterImages(String comicPath, int? chapterIndex) {
  var directory = Directory(_chapterPath(comicPath, chapterIndex));
  if (!directory.existsSync()) {
    return [];
  }
  var files = directory.listSync().whereType<File>().where((file) {
    var name = file.uri.pathSegments.last.toLowerCase();
    if (!_imageExtensions.any(name.endsWith)) {
      return false;
    }
    //排除封面
    return !name.startsWith('cover.');
  }).toList();
  files.sort((a, b) {
    var aIndex = int.tryParse(_stem(a)) ?? 1 << 30;
    var bIndex = int.tryParse(_stem(b)) ?? 1 << 30;
    var res = aIndex.compareTo(bIndex);
    return res != 0 ? res : _stem(a).compareTo(_stem(b));
  });
  return files;
}

/// [chapterIndex] 为 null 时表示图片直接存放于漫画目录下
String _chapterPath(String comicPath, int? chapterIndex) => chapterIndex == null
    ? comicPath
    : "$comicPath${Platform.pathSeparator}${chapterIndex + 1}";

/// 判断该漫画的图片是否直接存放于漫画目录下(即该漫画没有章节)
///
/// 有章节的漫画会把每一话存放在以章节序号命名的子目录中。
bool hasChapterDirectories(String comicPath) =>
    listChapterImages(comicPath, null).isEmpty;

/// 计算长图的输出宽度与高度
///
/// [sizes] 为每张图片的原始尺寸, 返回的尺寸已考虑最大宽度与
/// [maxLongImagePixels] 像素预算。
({int width, int height}) longImageSize(
    List<({int width, int height})> sizes, int maxWidth) {
  if (sizes.isEmpty) {
    throw ArgumentError("sizes must not be empty");
  }
  var width = sizes.map((e) => e.width).reduce(math.max);
  if (width > maxWidth) {
    width = maxWidth;
  }
  width = math.max(1, width);
  var height = 0;
  for (var size in sizes) {
    height += math.max(1, (width * size.height / size.width).round());
  }
  if (height * width > maxLongImagePixels) {
    var scale = math.sqrt(maxLongImagePixels / (height * width));
    var scaledWidth = math.max(1, (width * scale).floor());
    var scaledHeight = 0;
    for (var size in sizes) {
      scaledHeight +=
          math.max(1, (scaledWidth * size.height / size.width).round());
    }
    width = scaledWidth;
    height = scaledHeight;
  }
  return (width: width, height: height);
}

/// 把图片数据竖向拼成一张长图, 返回 png 数据
///
/// [decode] 用于把原始数据解码为图片, 解码失败时应返回 null
List<int> mergeImages(List<Uint8List> images,
    {int maxWidth = longImageMaxWidth, img.Image? Function(Uint8List)? decode}) {
  decode ??= (data) => img.decodeImage(data);
  var decoded = <img.Image>[];
  for (var data in images) {
    var image = decode(data);
    if (image == null) {
      throw Exception("Failed to decode image");
    }
    decoded.add(image);
  }
  var size = longImageSize(
      decoded.map((e) => (width: e.width, height: e.height)).toList(),
      maxWidth);
  var result = img.Image(width: size.width, height: size.height);
  var y = 0;
  for (var image in decoded) {
    var offset = y;
    y += math.max(1, (size.width * image.height / image.width).round());
    if (image.width != size.width) {
      //缩小时使用平均值插值, 避免长图出现锯齿
      image = img.copyResize(image,
          width: size.width,
          interpolation: image.width > size.width
              ? img.Interpolation.average
              : img.Interpolation.linear);
    }
    img.compositeImage(result, image, dstX: 0, dstY: offset);
  }
  //png 是无损格式, 不会像 jpeg 那样在文字与线条周围产生压缩痕迹
  return img.encodePng(result);
}

File _createLongImage({
  required String comicPath,
  required int? chapterIndex,
  required String savePath,
  required int maxWidth,
}) {
  var files = listChapterImages(comicPath, chapterIndex);
  if (files.isEmpty) {
    throw Exception("No downloaded image found in $comicPath");
  }

  //第一遍只读取图片头部, 得到尺寸并计算输出尺寸
  var images = <Uint8List>[];
  var sizes = <({int width, int height})>[];
  for (var file in files) {
    var bytes = file.readAsBytesSync();
    var decoder = img.findDecoderForData(bytes);
    var info = decoder?.startDecode(bytes);
    if (info == null || info.width < 1 || info.height < 1) {
      LogManager.addLog(LogLevel.warning, "Long Image",
          "Failed to read image size: ${file.path}");
      continue;
    }
    images.add(bytes);
    sizes.add((width: info.width, height: info.height));
  }
  if (images.isEmpty) {
    throw Exception("No readable image found in $comicPath");
  }

  var data = mergeImages(images, maxWidth: maxWidth);
  var file = File(savePath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data);
  return file;
}

String _stem(File file) {
  var name = file.uri.pathSegments.last;
  var dot = name.lastIndexOf('.');
  return dot == -1 ? name : name.substring(0, dot);
}

/// 删除导出长图时产生的临时文件
void deleteTemporaryLongImages(Iterable<File> files) {
  for (var file in files) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      //忽略
    }
  }
}
