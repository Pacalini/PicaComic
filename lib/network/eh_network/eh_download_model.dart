import 'dart:async';
import 'dart:isolate';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/file_downloader.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:zip_flutter/zip_flutter.dart';
import 'dart:io';
import '../../tools/io_tools.dart';
import '../download.dart';
import 'eh_main_network.dart';
import 'get_gallery_id.dart';

class DownloadedGallery extends DownloadedItem{
  Gallery gallery;
  double? size;
  DownloadedGallery(this.gallery,this.size);

  @override
  Map<String, dynamic> toJson()=>{
    "gallery": gallery.toJson(),
    "size": size
  };
  DownloadedGallery.fromJson(Map<String, dynamic> map):
        gallery = Gallery.fromJson(map["gallery"]),
        size = map["size"];

  @override
  DownloadType get type => DownloadType.ehentai;

  @override
  List<int> get downloadedEps => [0];

  @override
  List<String> get eps => ["EP 1"];

  @override
  String get name {
    if(appdata.settings[78] == "1"){
      return gallery.subTitle ?? gallery.title;
    } else {
      return gallery.title;
    }
  }

  @override
  String get id => getGalleryId(gallery.link);

  @override
  String get subTitle => gallery.uploader;

  @override
  double? get comicSize => size;

  @override
  set comicSize(double? value) {
    size = value;
  }

  List<String> _getTags(){
    var res = <String>[];
    gallery.tags.forEach((key, value) => value.forEach((element) => res.add(element)));
    return res;
  }

  @override
  List<String> get tags => _getTags();
}

///e-hentai的下载进程模型
class EhDownloadingItem extends DownloadingItem{
  EhDownloadingItem(
      this.gallery,
      super.whenFinish,
      super.onError,
      super.updateInfo,
      super.id,
      this.downloadType,
      {super.type = DownloadType.ehentai}
  );

  ///画廊模型
  final Gallery gallery;

  final int downloadType;

  @override
  Map<String, String> get headers => {
    "Cookie": EhNetwork().cookiesStr,
    "User-Agent": webUA,
    "Referer": EhNetwork().ehBaseUrl,
  };

  @override
  String get cover => gallery.coverPath.replaceFirst('s.exhentai.org', 'ehgt.org');

  @override
  String get title => gallery.title;

  @override
  Future<Map<int, List<String>>> getLinks() async{
    return {
      0: List.generate((int.parse(gallery.maxPage)), (index) => (index+1).toString())
    };
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return ImageManager().getEhImageNew(gallery, int.parse(link));
  }

  @override
  Map<String, dynamic> toMap() => {
    "gallery": gallery.toJson(),
    "downloadType": downloadType,
    "_downloadLink": _downloadLink,
    "_currentBytes": _currentBytes,
    "_totalBytes": _totalBytes,
    ...super.toBaseMap()
  };

  @override
  Future<void> onStart() async{
    await super.onStart();
    // clear showKey and imageKey
    // imageKey is saved through the network cache mechanism
    gallery.auth?.remove("showKey");
    await CacheManager().deleteKeyword("exhentai.org");
    await CacheManager().deleteKeyword("e-hentai.org");
  }

  int? _currentBytes;

  int? _totalBytes;

  @override
  int get totalPages {
    if(downloadType == 0){
      return super.totalPages;
    } else {
      return _totalBytes ?? 1;
    }
  }

  @override
  int get downloadedPages {
    if(downloadType == 0){
      return super.downloadedPages;
    } else {
      return _currentBytes ?? 0;
    }
  }

  _IsolateDownloader? _downloader;

  bool _stop = false;

  String? _downloadLink;

  int _currentSpeed = 0;

  @override
  int get currentSpeed => downloadType == 0
      ? super.currentSpeed
      : _currentSpeed;

  @override
  start() async{
    if(downloadType == 0){
      return super.start();
    } else {
      await onStart();
      _stop = false;
      try{
        await downloadCover();
        if(gallery.auth?["archiveDownload"] == null){
          throw "No archive download link";
        }
        if(_downloadLink == null) {
          var res = await EhNetwork().getArchiveDownloadLink(
              gallery.auth!["archiveDownload"]!, downloadType);
          if (_stop) {
            return;
          }
          if (res.error) {
            throw res.errorMessage!;
          }
          _downloadLink = res.data;
        }
        _downloader = _IsolateDownloader(
    _downloadLink!,
    path,
    (current, total, speed){
      _currentBytes = current;
      _totalBytes = total;
      _currentSpeed = speed;
      if(current == total){
        if (DownloadManager().downloading.firstOrNull != this) return;
        finish();                                  // _onFinish 中已含 _saveInfo → 通知
      } else {
        updateInfo?.call();                        // 只在未完成时通知进度
      }
    },
    onError!
);

        _downloader!.start();
      }
      catch(e, s){
        log("$e\n$s", "Download", LogLevel.error);
        onError?.call();
        return;
      }
    }
  }

void finish() async{
    try {
      onFinish?.call();
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Download", "Finish error: $e\n$s");
      onError?.call();
    }
}


  @override
  pause() async{
    if(downloadType == 0){
      return super.pause();
    } else {
      _stop = true;
      _downloader?.pause();
    }
  }

  @override
  stop() async{
    if(downloadType == 0){
      return super.stop();
    } else {
      _stop = true;
      _downloader?.stop();
      var directory = Directory(path);
      if(await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  EhDownloadingItem.fromMap(
      Map<String, dynamic> map,
      DownloadProgressCallback whenFinish,
      DownloadProgressCallback whenError,
      DownloadProgressCallbackAsync updateInfo,
      String id
      ):gallery=Gallery.fromJson(map["gallery"]),
        downloadType = map["downloadType"],
        _currentBytes = map["_currentBytes"],
        _totalBytes = map["_totalBytes"],
        _downloadLink = map["_downloadLink"],
        super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    return DownloadedGallery(gallery, await getFolderSize(Directory(path)));
  }
}

class _IsolateDownloader{
  final String url;

  final String savePath;

  late ReceivePort port;

  late SendPort sendPort;

  final void Function(int current, int total, int speed) updateInfo;

  final void Function() onError;

  _IsolateDownloader(this.url, this.savePath, this.updateInfo,
      this.onError);

  Isolate? isolate;

  void stop(){
    sendPort.send("stop");
    isolate = null;
    port.close();
  }

  void pause(){
    stop();
  }

  void start() async{
    port = ReceivePort();
    isolate = await Isolate.spawn<_DownloadData>(run, _DownloadData(
        port.sendPort, url, savePath, await getProxy()));
    var total = 0;
    port.listen((message) {
      if(message is SendPort){
        sendPort = message;
      } else if(message is DownloadingStatus){
        updateInfo(message.downloadedBytes, message.totalBytes+1, message.bytesPerSecond);
        total = message.totalBytes;
      } else if(message == "finish"){
        isolate?.kill(priority: Isolate.immediate);
        isolate = null;
        updateInfo(total+1, total+1, 0);
      } else if(message is _DownloadException){
        isolate?.kill(priority: Isolate.immediate);
        isolate = null;
        LogManager.addLog(LogLevel.error, "Download", message.message);
        onError();
      }
    });
  }

  static void run(_DownloadData data) async{
    var receivePort = ReceivePort();

    final sendPort = data.port;

    sendPort.send(receivePort.sendPort);

    final url = data.url;

    final savePath = data.savePath;

    FileDownloader? task;

    receivePort.listen((message) {
      if(message == "stop"){
        task?.stop().then((value) => Isolate.current.kill());
      }
    });

    Future.sync(() async{
      task = FileDownloader(url, "$savePath/temp.zip", data.proxy);

      try {
        await for (var status in task!.start()) {
          sendPort.send(status);
        }
        ZipFile.openAndExtract("$savePath/temp.zip", savePath);
        var files = Directory(savePath)
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.endsWith(".zip") && !f.path.contains("cover"))
            .toList();
    
        // 自然排序：按文件名中交替出现的文本段和数字段依次比较
        int naturalCompare(String a, String b) {
          final regex = RegExp(r'(\D+)|(\d+)');
          final aParts = regex.allMatches(a).map((m) => m.group(0)!).toList();
          final bParts = regex.allMatches(b).map((m) => m.group(0)!).toList();
        
          for (int i = 0; i < aParts.length && i < bParts.length; i++) {
            final numA = int.tryParse(aParts[i]);
            final numB = int.tryParse(bParts[i]);
        
            if (numA != null && numB != null) {
              final cmp = numA.compareTo(numB);
              if (cmp != 0) return cmp;
            } else {
              final cmp = aParts[i].compareTo(bParts[i]);
              if (cmp != 0) return cmp;
            }
          }
          return aParts.length.compareTo(bParts.length);
        }
        
        files.sort((a, b) {
          final nameA = a.path.split(pathSep).last;
          final nameB = b.path.split(pathSep).last;
          return naturalCompare(nameA, nameB);
        });
        
        for (int index = 0; index < files.length; index++) {
          final entry = files[index];
          final ext = entry.path.split(".").last;
          entry.renameSync("$savePath/$index.$ext");
        }
        
        // 删除 zip 文件
        File("$savePath/temp.zip").deleteSync();
        sendPort.send("finish");
      }
      catch(e, s){
        sendPort.send(_DownloadException("$e\n$s"));
      }
    });
  }
}

class _DownloadData{
  final SendPort port;
  final String url;
  final String savePath;
  final String? proxy;

  const _DownloadData(this.port, this.url, this.savePath,
      this.proxy);
}

class _DownloadException{
  final String message;

  const _DownloadException(this.message);
}
