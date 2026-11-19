import 'dart:io';
import 'package:wenku8_ipad/api/wenku8_api.dart';

/// 端到端冒烟：下载 → 解析 → 切章 → 缓存。
Future<void> main() async {
  final api = Wenku8Api();
  final (book, volumes) = await api.bookDetail('2334'); // Re:0
  print('书名: ${book.title}');
  print('卷数: ${volumes.length}');
  for (final v in volumes.take(3)) {
    print('  ${v.title}  (${v.chapters.length} 章) 首章: ${v.chapters.first.title}');
  }
  final totalChapters = volumes.fold<int>(0, (s, v) => s + v.chapters.length);
  print('总章节数: $totalChapters');

  final first = volumes.first.chapters.first;
  final content = await api.chapterContent(book.aid, first.cid);
  print('首章「${first.title}」长度: ${content.length} 字');
  print('首章开头: ${content.substring(0, (content.length.clamp(0, 120)))}...');

  // 另一切章验证区间切割正确
  final last = volumes.last.chapters.last;
  final lastContent = await api.chapterContent(book.aid, last.cid);
  print('末章「${last.title}」长度: ${lastContent.length} 字');
  print('OK');
  api.dispose();
}
