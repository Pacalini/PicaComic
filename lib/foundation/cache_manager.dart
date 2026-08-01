import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:sqlite3/sqlite3.dart';

class CacheManager {
  static String get cachePath => '${App.cachePath}/cache';

  static CacheManager? instance;

  late Database _db;

  int? _currentSize;

  /// size in bytes
  int get currentSize => _currentSize ?? 0;

  int dir = 0;

  /// 数据库文件路径, 用于初始化扫描
  late String _dbPath;

  /// 初始化扫描任务, 完成后 _currentSize 为真实大小
  Future<void>? _initialScanTask;

  int _limitSize = 2 * 1024 * 1024 * 1024;

  int get limitSize => _limitSize;

  /// compute 回调: 在后台 isolate 中扫描缓存目录
  ///
  /// 必须是无捕获的静态方法, 以便在 web 平台由 compute 降级为同线程执行。
  static Future<Map<String, Object?>> _scanDirCallback(
      List<String> args) async {
    final dbPath = args[0];
    final cacheDir = args[1];
    int totalSize = 0;
    final unmanagedFiles = <String>[];
    var db = sqlite3.open(dbPath);
    try {
      var d = Directory(cacheDir);
      if (await d.exists()) {
        await for (var entity in d.list(recursive: true)) {
          if (entity is File) {
            var segs = entity.uri.pathSegments;
            var name = segs.last;
            var dirName = segs.length >= 2 ? segs[segs.length - 2] : "*";
            var rows = db.select(
              'SELECT * FROM cache WHERE dir = ? AND name = ?',
              [dirName, name],
            );
            if (rows.isEmpty) {
              unmanagedFiles.add(entity.path);
            } else {
              totalSize += await entity.length();
            }
          }
        }
      }
    } finally {
      db.dispose();
    }
    return {'totalSize': totalSize, 'unmanagedFiles': unmanagedFiles};
  }

  /// 扫描缓存目录, 统计有效缓存大小并找出孤立文件
  static Future<int> _scanDir(String dbPath, String cacheDir) async {
    final res = await compute(_scanDirCallback, [dbPath, cacheDir]);
    // 主 isolate 中删除孤立文件并清理数据库记录
    for (var filePath in res['unmanagedFiles'] as List<String>) {
      var file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      var segs = file.uri.pathSegments;
      var name = segs.last;
      var dirName = segs.length >= 2 ? segs[segs.length - 2] : "*";
      CacheManager()._db.execute(
        'DELETE FROM cache WHERE dir = ? AND name = ?',
        [dirName, name],
      );
    }
    return res['totalSize'] as int;
  }

  /// 初始化时扫描缓存目录, 校准大小并清理孤立文件
  Future<void> _runInitialScan() async {
    try {
      _currentSize = await _scanDir(_dbPath, cachePath);
      await checkCache();
    } catch (_) {
      _currentSize = 0;
    }
  }

  CacheManager._create(){
    Directory(cachePath).createSync(recursive: true);
    _dbPath = '${App.dataPath}/cache.db';
    _db = sqlite3.open(_dbPath);
    _db.execute('''
      CREATE TABLE IF NOT EXISTS cache (
        key TEXT PRIMARY KEY NOT NULL,
        dir TEXT NOT NULL,
        name TEXT NOT NULL,
        expires INTEGER NOT NULL,
        type TEXT
      )
    ''');
    // 旧版本的表中没有type字段，需要添加
    try {
      _db.execute('''
        ALTER TABLE cache ADD COLUMN type TEXT
      ''');
    } catch (e) {
      // ignore
    }
    // 初始化时在后台 isolate 中扫描缓存目录, 校准大小并清理孤立文件
    _initialScanTask = _runInitialScan();
  }

  factory CacheManager() => instance ??= CacheManager._create();

  /// set cache size limit in MB
  void setLimitSize(int size){
    if(size <= 0){
      // 非法值忽略, 防止 _limitSize <= 0 导致缓存被全部清空
      return;
    }
    _limitSize = size * 1024 * 1024;
  }

  void setType(String key, String? type){
    _db.execute('''
      UPDATE cache
      SET type = ?
      WHERE key = ?
    ''', [type, key]);
  }

  String? getType(String key){
    var res = _db.select('''
      SELECT type FROM cache
      WHERE key = ?
    ''', [key]);
    if(res.isEmpty){
      return null;
    }
    return res.first[0];
  }

  Future<void> writeCache(String key, Uint8List data, [int duration = 7 * 24 * 60 * 60 * 1000]) async{
    // 删除该 key 的旧缓存文件, 防止 INSERT OR REPLACE 后旧文件永久残留
    var oldPath = await findCache(key);
    if(oldPath != null){
      var oldFile = File(oldPath);
      if(await oldFile.exists()){
        var oldSize = await oldFile.length();
        await oldFile.delete();
        if(_currentSize != null){
          _currentSize = _currentSize! - oldSize;
        }
      }
    }
    this.dir++;
    this.dir %= 100;
    var dir = this.dir;
    var name = md5.convert(Uint8List.fromList(key.codeUnits)).toString();
    var file = File('$cachePath/$dir/$name');
    while(await file.exists()){
      name = md5.convert(Uint8List.fromList(name.codeUnits)).toString();
      file = File('$cachePath/$dir/$name');
    }
    await file.create(recursive: true);
    await file.writeAsBytes(data);
    // duration <= 0 表示永久缓存 (expires = 0), 与 findCache/checkCache 的 expires > 0 判断配合
    var expires =
        duration <= 0 ? 0 : DateTime.now().millisecondsSinceEpoch + duration;
    _db.execute('''
      INSERT OR REPLACE INTO cache (key, dir, name, expires) VALUES (?, ?, ?, ?)
    ''', [key, dir.toString(), name, expires]);
    if(_currentSize != null) {
      _currentSize = _currentSize! + data.length;
    }
    if(_currentSize != null && _currentSize! > _limitSize){
      await checkCache();
    }
  }

  Future<CachingFile> openWrite(String key) async{
    // 删除该 key 的旧缓存文件, 防止同一 key 多次流式写入时旧文件永久残留
    await delete(key);
    this.dir++;
    this.dir %= 100;
    var dir = this.dir;
    var name = md5.convert(Uint8List.fromList(key.codeUnits)).toString();
    var file = File('$cachePath/$dir/$name');
    while(await file.exists()){
      name = md5.convert(Uint8List.fromList(name.codeUnits)).toString();
      file = File('$cachePath/$dir/$name');
    }
    await file.create(recursive: true);
    return CachingFile._(key, dir.toString(), name, file);
  }

  Future<String?> findCache(String key) async{
    var res = _db.select('''
      SELECT * FROM cache
      WHERE key = ?
    ''', [key]);
    if(res.isEmpty){
      return null;
    }
    var row = res.first;
    var dir = row[1] as String;
    var name = row[2] as String;
    var expires = row[3] as int;
    var file = File('$cachePath/$dir/$name');
    var now = DateTime.now().millisecondsSinceEpoch;

    // 过期缓存直接删除并返回 null (expires <= 0 视为永久缓存, 不过期)
    if(expires > 0 && expires < now){
      _db.execute('''
        DELETE FROM cache
        WHERE key = ?
      ''', [key]);
      if(await file.exists()){
        var size = await file.length();
        if(_currentSize != null) {
          _currentSize = _currentSize! - size;
        }
        await file.delete();
      }
      return null;
    }

    // 命中缓存, LRU 续期 7 天 (永久缓存 expires <= 0 不续期)
    if(await file.exists()){
      if(expires > 0){
        _db.execute('''
          UPDATE cache
          SET expires = ?
          WHERE key = ?
        ''', [now + 7 * 24 * 60 * 60 * 1000, key]);
      }
      return file.path;
    }

    // 文件丢失, 清理数据库脏记录
    _db.execute('''
      DELETE FROM cache
      WHERE key = ?
    ''', [key]);
    return null;
  }

  bool _isChecking = false;

  Future<void> checkCache() async{
    if(_isChecking){
      return;
    }
    _isChecking = true;
    try {
      var res = _db.select('''
        SELECT * FROM cache
        WHERE expires > 0 AND expires < ?
      ''', [DateTime.now().millisecondsSinceEpoch]);
      for(var row in res){
        var dir = row[1] as String;
        var name = row[2] as String;
        var file = File('$cachePath/$dir/$name');
        if(await file.exists()){
          var size = await file.length();
          await file.delete();
          if(_currentSize != null){
            _currentSize = _currentSize! - size;
          }
        }
      }
      _db.execute('''
        DELETE FROM cache
        WHERE expires > 0 AND expires < ?
      ''', [DateTime.now().millisecondsSinceEpoch]);

      int count = 0;
      var res2 = _db.select('''
        SELECT COUNT(*) FROM cache
      ''');
      if(res2.isNotEmpty){
        count = res2.first[0] as int;
      }

      compute((path) => Directory(path).size, cachePath)
          .then((value) => _currentSize = value);

      // 防御: 初始化扫描未完成时 _currentSize 可能为 null,
      // 若 count > 2000 会进入 while 循环, 循环内 _currentSize! 将崩溃
      if(_currentSize == null && count > 2000){
        _currentSize = await Directory(cachePath).size;
      }

      while((_currentSize != null && _currentSize! > _limitSize) ||  count > 2000){
        // 淘汰排除永久缓存 (expires <= 0)
        var res = _db.select('''
          SELECT * FROM cache
          WHERE expires > 0
          ORDER BY expires ASC
          limit 10
        ''');
        if(res.isEmpty){
          // 无可淘汰的临时缓存 (expires > 0)。
          // 仅当数据库已完全为空 (磁盘上都是孤立文件) 时才全清,
          // 避免永久缓存 (expires <= 0) 占满空间时被无差别删除。
          var countRes = _db.select('''
            SELECT COUNT(*) FROM cache
          ''');
          var dbCount = countRes.isEmpty ? 0 : countRes.first[0] as int;
          if(dbCount == 0){
            await Directory(cachePath).delete(recursive: true);
            Directory(cachePath).createSync(recursive: true);
            _currentSize = 0;
          }
          break;
        }
        for(var row in res){
          var key = row[0] as String;
          var dir = row[1] as String;
          var name = row[2] as String;
          var file = File('$cachePath/$dir/$name');
          if(await file.exists()){
            var size = await file.length();
            await file.delete();
            _db.execute('''
              DELETE FROM cache
              WHERE key = ?
            ''', [key]);
            _currentSize = _currentSize! - size;
            if(_currentSize! <= _limitSize){
              break;
            }
          } else {
            _db.execute('''
              DELETE FROM cache
              WHERE key = ?
            ''', [key]);
          }
          count--;
        }
      }
    } finally {
      _isChecking = false;
    }
  }

  Future<void> delete(String key) async{
    var res = _db.select('''
      SELECT * FROM cache
      WHERE key = ?
    ''', [key]);
    if(res.isEmpty){
      return;
    }
    var row = res.first;
    var dir = row[1] as String;
    var name = row[2] as String;
    var file = File('$cachePath/$dir/$name');
    var fileSize = 0;
    if(await file.exists()){
      fileSize = await file.length();
      await file.delete();
    }
    _db.execute('''
      DELETE FROM cache
      WHERE key = ?
    ''', [key]);
    if(_currentSize != null) {
      _currentSize = _currentSize! - fileSize;
    }
  }

  Future<void> clear() async {
    await Directory(cachePath).delete(recursive: true);
    Directory(cachePath).createSync(recursive: true);
    _db.execute('''
      DELETE FROM cache
    ''');
    _currentSize = 0;
  }

  Future<void> deleteKeyword(String keyword) async{
    var res = _db.select('''
      SELECT * FROM cache
      WHERE key LIKE ?
    ''', ['%$keyword%']);
    for(var row in res){
      var key = row[0] as String;
      var dir = row[1] as String;
      var name = row[2] as String;
      var file = File('$cachePath/$dir/$name');
      var fileSize = 0;
      if(await file.exists()){
        fileSize = await file.length();
        try {
          await file.delete();
        }
        finally {}
      }
      _db.execute('''
        DELETE FROM cache
        WHERE key = ?
      ''', [key]);
      if(_currentSize != null) {
        _currentSize = _currentSize! - fileSize;
      }
    }
  }
}

class CachingFile{
  CachingFile._(this.key, this.dir, this.name, this.file);

  final String key;

  final String dir;

  final String name;

  final File file;

  final List<int> _buffer = [];

  Future<void> writeBytes(List<int> data) async{
    _buffer.addAll(data);
    if(_buffer.length > 1024 * 1024){
      await file.writeAsBytes(_buffer, mode: FileMode.append);
      _buffer.clear();
    }
  }

  Future<void> close() async{
    if(_buffer.isNotEmpty){
      await file.writeAsBytes(_buffer, mode: FileMode.append);
    }
    CacheManager()._db.execute('''
      INSERT OR REPLACE INTO cache (key, dir, name, expires) VALUES (?, ?, ?, ?)
    ''', [key, dir, name, DateTime.now().millisecondsSinceEpoch + 7 * 24 * 60 * 60 * 1000]);
    // 将流式写入的文件大小计入全局缓存容量
    if(CacheManager()._currentSize != null){
      CacheManager()._currentSize = CacheManager()._currentSize! + await file.length();
    }
    await CacheManager().checkCache();
  }

  Future<void> cancel() async{
    await file.deleteIgnoreError();
  }

  void reset() {
    _buffer.clear();
    if(file.existsSync()) {
      file.deleteSync();
    }
  }
}
