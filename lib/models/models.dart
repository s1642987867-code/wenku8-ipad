/// 数据模型层
library;

/// 书籍
class Book {
  final String aid;
  final String title;
  final String author;
  final String? coverUrl;
  final String? status; // 连载中 / 已完结
  final String? intro;
  final int? wordCount;
  final String? lastUpdate;
  final String? category;

  const Book({
    required this.aid,
    required this.title,
    this.author = '',
    this.coverUrl,
    this.status,
    this.intro,
    this.wordCount,
    this.lastUpdate,
    this.category,
  });

  Book copyWith({
    String? title,
    String? author,
    String? coverUrl,
    String? status,
    String? intro,
    int? wordCount,
    String? lastUpdate,
    String? category,
  }) =>
      Book(
        aid: aid,
        title: title ?? this.title,
        author: author ?? this.author,
        coverUrl: coverUrl ?? this.coverUrl,
        status: status ?? this.status,
        intro: intro ?? this.intro,
        wordCount: wordCount ?? this.wordCount,
        lastUpdate: lastUpdate ?? this.lastUpdate,
        category: category ?? this.category,
      );

  Map<String, dynamic> toJson() => {
        'aid': aid,
        'title': title,
        'author': author,
        'coverUrl': coverUrl,
        'status': status,
        'intro': intro,
        'wordCount': wordCount,
        'lastUpdate': lastUpdate,
        'category': category,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        aid: j['aid']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        author: j['author']?.toString() ?? '',
        coverUrl: j['coverUrl']?.toString(),
        status: j['status']?.toString(),
        intro: j['intro']?.toString(),
        wordCount: (j['wordCount'] as num?)?.toInt(),
        lastUpdate: j['lastUpdate']?.toString(),
        category: j['category']?.toString(),
      );
}

/// 卷
class Volume {
  final String vid;
  final String title;
  final List<Chapter> chapters;
  const Volume({required this.vid, required this.title, this.chapters = const []});
}

/// 章节
class Chapter {
  final String aid;
  final String cid;
  final String title;
  final String? volumeTitle;
  const Chapter({
    required this.aid,
    required this.cid,
    required this.title,
    this.volumeTitle,
  });
}

/// 书架条目（含阅读进度）
class ShelfEntry {
  final Book book;
  final String? lastCid;
  final String? lastChapterTitle;
  final int? lastChapterIdx;
  final int lastPosition;
  final int lastReadAt;
  final bool isDownloaded;

  const ShelfEntry({
    required this.book,
    this.lastCid,
    this.lastChapterTitle,
    this.lastChapterIdx,
    this.lastPosition = 0,
    required this.lastReadAt,
    this.isDownloaded = false,
  });

  ShelfEntry copyWith({
    String? lastCid,
    String? lastChapterTitle,
    int? lastChapterIdx,
    int? lastPosition,
    int? lastReadAt,
    bool? isDownloaded,
  }) =>
      ShelfEntry(
        book: book,
        lastCid: lastCid ?? this.lastCid,
        lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
        lastChapterIdx: lastChapterIdx ?? this.lastChapterIdx,
        lastPosition: lastPosition ?? this.lastPosition,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        isDownloaded: isDownloaded ?? this.isDownloaded,
      );

  Map<String, dynamic> toJson() => {
        'book': book.toJson(),
        'lastCid': lastCid,
        'lastChapterTitle': lastChapterTitle,
        'lastChapterIdx': lastChapterIdx,
        'lastPosition': lastPosition,
        'lastReadAt': lastReadAt,
        'isDownloaded': isDownloaded,
      };

  factory ShelfEntry.fromJson(Map<String, dynamic> j) => ShelfEntry(
        book: Book.fromJson(j['book'] as Map<String, dynamic>),
        lastCid: j['lastCid']?.toString(),
        lastChapterTitle: j['lastChapterTitle']?.toString(),
        lastChapterIdx: (j['lastChapterIdx'] as num?)?.toInt(),
        lastPosition: (j['lastPosition'] as num?)?.toInt() ?? 0,
        lastReadAt: (j['lastReadAt'] as num?)?.toInt() ?? 0,
        isDownloaded: j['isDownloaded'] as bool? ?? false,
      );
}

/// 书签
class Bookmark {
  final String id;
  final String aid;
  final String cid;
  final String chapterTitle;
  final int paragraphIdx;
  final String snippet;
  final String? note;
  final int createdAt;

  const Bookmark({
    required this.id,
    required this.aid,
    required this.cid,
    required this.chapterTitle,
    required this.paragraphIdx,
    required this.snippet,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'aid': aid,
        'cid': cid,
        'chapterTitle': chapterTitle,
        'paragraphIdx': paragraphIdx,
        'snippet': snippet,
        'note': note,
        'createdAt': createdAt,
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        id: j['id']?.toString() ?? '',
        aid: j['aid']?.toString() ?? '',
        cid: j['cid']?.toString() ?? '',
        chapterTitle: j['chapterTitle']?.toString() ?? '',
        paragraphIdx: (j['paragraphIdx'] as num?)?.toInt() ?? 0,
        snippet: j['snippet']?.toString() ?? '',
        note: j['note']?.toString(),
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// 目录快照条目（内置 3892 本）
class CatalogEntry {
  final int aid;
  final String title;
  final String author;
  final String? tag;
  final int? status; // 0=连载 1=完结
  final int? bookSize;

  const CatalogEntry({
    required this.aid,
    required this.title,
    this.author = '',
    this.tag,
    this.status,
    this.bookSize,
  });

  factory CatalogEntry.fromJson(List<dynamic> j) => CatalogEntry(
        aid: (j[0] as num).toInt(),
        title: j[1]?.toString() ?? '',
        author: j[2]?.toString() ?? '',
        tag: j.length > 3 ? j[3]?.toString() : null,
        status: j.length > 4 ? (j[4] as num?)?.toInt() : null,
        bookSize: j.length > 5 ? (j[5] as num?)?.toInt() : null,
      );

  Book toBook() => Book(
        aid: aid.toString(),
        title: title,
        author: author,
        coverUrl: 'https://img.wenku8.com/image/${aid ~/ 1000}/$aid/${aid}s.jpg',
        status: status == 1 ? '已完结' : '连载中',
        category: tag,
      );
}

/// 阅读设置
class ReaderSettings {
  final double fontSize;
  final double lineHeight;
  final int backgroundColorIndex;
  final bool nightMode;
  final String fontFamily;
  final bool justifyText;
  final double paragraphSpacing;

  const ReaderSettings({
    this.fontSize = 18.0,
    this.lineHeight = 1.8,
    this.backgroundColorIndex = 0,
    this.nightMode = false,
    this.fontFamily = 'system',
    this.justifyText = true,
    this.paragraphSpacing = 8.0,
  });

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    int? backgroundColorIndex,
    bool? nightMode,
    String? fontFamily,
    bool? justifyText,
    double? paragraphSpacing,
  }) =>
      ReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        backgroundColorIndex: backgroundColorIndex ?? this.backgroundColorIndex,
        nightMode: nightMode ?? this.nightMode,
        fontFamily: fontFamily ?? this.fontFamily,
        justifyText: justifyText ?? this.justifyText,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'backgroundColorIndex': backgroundColorIndex,
        'nightMode': nightMode,
        'fontFamily': fontFamily,
        'justifyText': justifyText,
        'paragraphSpacing': paragraphSpacing,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic> j) => ReaderSettings(
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 18.0,
        lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.8,
        backgroundColorIndex: (j['backgroundColorIndex'] as num?)?.toInt() ?? 0,
        nightMode: j['nightMode'] as bool? ?? false,
        fontFamily: j['fontFamily']?.toString() ?? 'system',
        justifyText: j['justifyText'] as bool? ?? true,
        paragraphSpacing: (j['paragraphSpacing'] as num?)?.toDouble() ?? 8.0,
      );
}

/// 异常
class Wenku8Exception implements Exception {
  final String message;
  Wenku8Exception(this.message);
  @override
  String toString() => message;
}
