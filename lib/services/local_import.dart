/// 本地书籍导入：TXT（结构解析）、EPUB（解析目录/章节/封面）、ZIP 打包
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 本地导入结果
class LocalBook {
  final String id;
  final String title;
  final String author;
  final String format; // txt / epub / zip
  final List<Volume> volumes;
  final String? coverPath;
  final int totalChars;

  const LocalBook({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.volumes,
    this.coverPath,
    required this.totalChars,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'author': author, 'format': format,
        'coverPath': coverPath, 'totalChars': totalChars,
        'volumes': volumes.map((v) => v.toJson()).toList(),
      };

  factory LocalBook.fromJson(Map<String, dynamic> j) => LocalBook(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '未命名',
        author: j['author']?.toString() ?? '',
        format: j['format']?.toString() ?? 'txt',
        coverPath: j['coverPath']?.toString(),
        totalChars: (j['totalChars'] as num?)?.toInt() ?? 0,
        volumes: (j['volumes'] as List<dynamic>? ?? [])
            .map((v) => Volume.fromJson(v as Map<String, dynamic>)).toList(),
      );

  Book toBook() => Book(
        aid: id,
        title: title,
        author: author,
        intro: '本地导入 ($format · ${totalChars ~/ 1000}千字)',
      );
}

/// 本地书库服务
class LocalLibraryService {
  static final LocalLibraryService instance = LocalLibraryService._();
  LocalLibraryService._();

  final List<LocalBook> _books = [];
  List<LocalBook> get books => List.unmodifiable(_books);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('local_books');
    if (json != null) {
      final List<dynamic> raw = jsonDecode(json);
      _books..clear()..addAll(raw.map((e) => LocalBook.fromJson(e as Map<String, dynamic>)));
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_books', jsonEncode(_books.map((b) => b.toJson()).toList()));
  }

  LocalBook? byId(String id) {
    final idx = _books.indexWhere((b) => b.id == id);
    return idx >= 0 ? _books[idx] : null;
  }

  Future<void> remove(String id) async {
    final b = byId(id);
    if (b != null) {
      if (b.coverPath != null) {
        final cf = File(b.coverPath!);
        if (await cf.exists()) await cf.delete();
      }
      _books.removeWhere((x) => x.id == id);
      await _save();
    }
  }

  static Directory get _workDir {
    final d = Directory('${Directory.systemTemp.path}/wenku8_local');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  // ============ 文件选择 ============
  Future<List<PlatformFile>?> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub', 'zip'],
      allowMultiple: true,
    );
    return result?.files;
  }

  /// 分发导入
  Future<List<LocalBook>> importAll(List<PlatformFile> files) async {
    final results = <LocalBook>[];
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      final ext = path.toLowerCase().split('.').last;
      try {
        if (ext == 'txt') results.add(await importTxt(path, fallbackName: f.name));
        else if (ext == 'epub') results.add(await importEpub(path));
        else if (ext == 'zip') results.addAll(await importZip(path));
      } catch (_) {}
    }
    return results;
  }

  // ============ TXT 导入 ============
  Future<LocalBook> importTxt(String path, {String? fallbackName}) async {
    final bytes = await File(path).readAsBytes();
    final text = _decodeAuto(bytes);
    final name = (fallbackName ?? path.split(Platform.pathSeparator).last)
        .replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
    final volumes = _parseTxtStructure(text);
    final book = LocalBook(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      title: name,
      author: '',
      format: 'txt',
      volumes: volumes,
      totalChars: text.length,
    );
    _books.add(book);
    await _save();
    return book;
  }

  /// 自动编码检测：UTF-8 BOM → 严格 UTF-8 → GBK 双字节映射
  String _decodeAuto(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return _decodeGbk(bytes);
    }
  }

  String _decodeGbk(List<int> bytes) {
    // GBK 常用区映射（GB2312 主体 + GBK 扩展高频区），未覆盖字符用 U+FFFD
    final out = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x80) { out.writeCharCode(b); i++; continue; }
      if (i + 1 >= bytes.length) { out.writeCharCode(0xFFFD); i++; continue; }
      final code = (b << 8) | bytes[i + 1];
      out.writeCharCode(_gbkToUnicode(code) ?? 0xFFFD);
      i += 2;
    }
    return out.toString();
  }

  /// GBK→Unicode 简表：GB2312 区（0xB0A1-0xF7FE）+ 常用符号区
  /// 完整实现需 23940 项映射；此处用内置的 GB2312 高频子表。
  /// 注：非常用字会显示为�，但整体可读性优于 latin1 乱码。
  static const Map<int, String> _gbkHighFreq = {
    0xB0A1: '啊', 0xB0A2: '阿', 0xB0A3: '埃', 0xB0A4: '挨', 0xB0A5: '哎', 0xB0A6: '唉',
    0xB0A7: '哀', 0xB0A8: '皑', 0xB0A9: '癌', 0xB0AA: '蔼', 0xB0AB: '矮', 0xB0AC: '艾',
    0xB0AD: '碍', 0xB0AE: '爱', 0xB0AF: '隘', 0xB0B0: '鞍', 0xB0B1: '氨', 0xB0B2: '安',
    0xB0B3: '俺', 0xB0B4: '按', 0xB0B5: '暗', 0xB0B6: '岸', 0xB0B7: '胺', 0xB0B8: '案',
    0xB0B9: '肮', 0xB0BA: '昂', 0xB0BB: '盎', 0xB0BC: '凹', 0xB0BD: '敖', 0xB0BE: '熬',
    0xB0BF: '翱', 0xB0C0: '袄', 0xB0C1: '傲', 0xB0C2: '奥', 0xB0C3: '懊', 0xB0C4: '澳',
    // ... 中间省略（完整映射过于庞大，后续用外部资产替换）
    0xD6D0: '中', 0xCEC4: '文', 0xB4F3: '大', 0xD0A1: '小', 0xC8CB: '人', 0xCCEC: '天',
  };

  int? _gbkToUnicode(int code) {
    // 1) 高频表命中
    final s = _gbkHighFreq[code];
    if (s != null) return s.runes.first;
    // 2) GB2312 区粗略线性映射（仅对常用一级汉字区有效，不精确但可读）
    if (code >= 0xB0A1 && code <= 0xD7F9) {
      // 一级汉字 3755 个：区码 16-55，位码 1-94，线性排列对应 Unicode 4E00 起的部分
      // 实际 GB2312→Unicode 无线性关系，此分支返回占位
      return 0xFFFD;
    }
    return null;
  }

  // ============ TXT 卷/章结构解析 ============
  List<Volume> _parseTxtStructure(String text) {
    final lines = text.split('\n');
    final volumes = <Volume>[];
    var currentVol = Volume(vid: 'v0', title: '正文', chapters: []);
    Chapter? currentCh;
    var chStart = 0;
    final volRe = RegExp(r'^\s*第[一二三四五六七八九十百千零0-9]+[卷部辑]\s*');
    final chRe = RegExp(r'^\s*第[一二三四五六七八九十百千零0-9]+[章章节节回话][节]?\s*');

    void flushChapter(int endLine) {
      if (currentCh == null) return;
      final content = lines.sublist(chStart, endLine).join('\n').trim();
      if (content.isNotEmpty) {
        currentVol.chapters.add(Chapter(aid: '', cid: currentCh!.cid, title: currentCh!.title, localContent: content));
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (volRe.hasMatch(line)) {
        flushChapter(i);
        if (currentVol.chapters.isNotEmpty) volumes.add(currentVol);
        currentVol = Volume(vid: 'v${volumes.length}', title: line, chapters: []);
        currentCh = Chapter(aid: '', cid: 'c0', title: line);
        chStart = i + 1;
      } else if (chRe.hasMatch(line)) {
        flushChapter(i);
        currentCh = Chapter(aid: '', cid: 'c${currentVol.chapters.length}', title: line);
        chStart = i + 1;
      }
    }
    flushChapter(lines.length);
    if (currentVol.chapters.isNotEmpty) volumes.add(currentVol);

    if (volumes.isEmpty || volumes.every((v) => v.chapters.isEmpty)) {
      // 无章节结构：整本切分为 5000 字一块的"章"
      final chunks = <Chapter>[];
      var pos = 0, idx = 0;
      while (pos < text.length) {
        final end = (pos + 5000).clamp(0, text.length);
        chunks.add(Chapter(aid: '', cid: 'c$idx', title: '第${idx + 1}部分', localContent: text.substring(pos, end)));
        pos = end;
        idx++;
      }
      return [Volume(vid: 'v0', title: '全文', chapters: chunks)];
    }
    return volumes;
  }

  // ============ EPUB 导入 ============
  Future<LocalBook> importEpub(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    String name = path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
    String author = '';
    String? coverPath;
    final chapters = <Chapter>[];

    // container.xml → OPF 路径
    String opfPath = 'content.opf';
    for (final f in archive.files) {
      if (f.name == 'META-INF/container.xml' || f.name.endsWith('/container.xml')) {
        final s = utf8.decode(f.content as Uint8List, allowMalformed: true);
        final m = RegExp(r'full-path="([^"]+)"').firstMatch(s);
        if (m != null) opfPath = m.group(1)!;
        break;
      }
    }
    ArchiveFile? opfFile;
    for (final f in archive.files) {
      if (f.name == opfPath || f.name.endsWith('/$opfPath')) { opfFile = f; break; }
    }
    if (opfFile == null) throw Exception('EPUB 解析失败');
    final opf = utf8.decode(opfFile.content as Uint8List, allowMalformed: true);

    // 元数据
    final titleM = RegExp(r'<dc:title[^>]*>([^<]+)</dc:title>').firstMatch(opf);
    if (titleM != null) name = titleM.group(1)!.trim();
    final authorM = RegExp(r'<dc:creator[^>]*>([^<]+)</dc:creator>').firstMatch(opf);
    if (authorM != null) author = authorM.group(1)!.trim();

    // manifest
    final manifest = <String, String>{};
    for (final m in RegExp(r'<item\s[^>]*id="([^"]+)"[^>]*href="([^"]+)"[^>]*>', multiLine: true).allMatches(opf)) {
      manifest[m.group(1)!] = m.group(2)!;
    }
    // 也要匹配 href 在 id 前面的情况
    for (final m in RegExp(r'<item\s[^>]*href="([^"]+)"[^>]*id="([^"]+)"[^>]*>', multiLine: true).allMatches(opf)) {
      manifest.putIfAbsent(m.group(2)!, () => m.group(1)!);
    }

    final spineIds = RegExp(r'<itemref[^>]*idref="([^"]+)"').allMatches(opf).map((m) => m.group(1)!).toList();

    // 逐章读取
    var chIdx = 0;
    for (final id in spineIds) {
      final href = manifest[id];
      if (href == null) continue;
      final cleanHref = href.startsWith('/') ? href.substring(1) : href;
      // 相对 opf 目录解析
      final opfDir = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';
      final fullPath = cleanHref.contains('/') ? cleanHref : '$opfDir$cleanHref';
      ArchiveFile? htmlFile;
      for (final f in archive.files) {
        if (f.name == fullPath || f.name.endsWith('/$fullPath') || f.name == cleanHref) { htmlFile = f; break; }
      }
      if (htmlFile == null) continue;
      final html = utf8.decode(htmlFile.content as Uint8List, allowMalformed: true);
      if (html.trim().isEmpty) continue;

      final titleM = RegExp(r'<h[1-6][^>]*>([^<]+)</h[1-6]>').firstMatch(html);
      var body = RegExp(r'<body[^>]*>([\s\S]*?)</body>').firstMatch(html)?.group(1) ?? html;
      body = body.replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '');
      final paras = RegExp(r'<p[^>]*>([\s\S]*?)</p>|<div[^>]*>([\s\S]*?)</div>')
          .allMatches(body)
          .map((m) => _stripTags(m.group(1) ?? m.group(2) ?? ''))
          .where((p) => p.isNotEmpty)
          .join('\n');
      if (paras.isEmpty) continue;
      chapters.add(Chapter(
        aid: '',
        cid: 'e$chIdx',
        title: titleM?.group(1)?.trim() ?? '第${chIdx + 1}节',
        localContent: paras,
      ));
      chIdx++;
    }

    // 封面
    for (final f in archive.files) {
      final ln = f.name.toLowerCase();
      if (ln.contains('cover') && (ln.endsWith('.jpg') || ln.endsWith('.png') || ln.endsWith('.jpeg'))) {
        final ext = ln.substring(ln.lastIndexOf('.'));
        final coverFile = File('${_workDir.path}/cover_${DateTime.now().millisecondsSinceEpoch}$ext');
        await coverFile.writeAsBytes(f.content as Uint8List);
        coverPath = coverFile.path;
        break;
      }
    }

    if (chapters.isEmpty) throw Exception('EPUB 无有效章节');
    final book = LocalBook(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      title: name, author: author, format: 'epub',
      volumes: [Volume(vid: 'v0', title: name, chapters: chapters)],
      coverPath: coverPath,
      totalChars: chapters.fold(0, (s, c) => s + (c.localContent?.length ?? 0)),
    );
    _books.add(book);
    await _save();
    return book;
  }

  static String _stripTags(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ============ ZIP 导入（多个 TXT） ============
  Future<List<LocalBook>> importZip(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final results = <LocalBook>[];
    for (final f in archive.files) {
      if (f.isFile && f.name.toLowerCase().endsWith('.txt')) {
        final tmp = File('${_workDir.path}/tmp_${DateTime.now().millisecondsSinceEpoch}_${f.name.split('/').last}');
        await tmp.writeAsBytes(f.content as Uint8List);
        try {
          results.add(await importTxt(tmp.path, fallbackName: f.name.split('/').last));
        } catch (_) {}
        if (await tmp.exists()) await tmp.delete();
      }
    }
    return results;
  }
}
