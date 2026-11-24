/// 书架页：网格/列表切换，阅读进度显示，本地书导入
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/models.dart';
import '../services/local_import.dart';
import '../services/services.dart';
import 'book_detail_page.dart';
import 'reader_page.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});
  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  bool _gridView = true;

  Future<void> _importLocal() async {
    final files = await LocalLibraryService.instance.pickFiles();
    if (files == null || files.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final imported = await LocalLibraryService.instance.importAll(files);
    if (mounted) Navigator.pop(context);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(imported.isEmpty ? '导入失败（格式不支持或文件损坏）' : '成功导入 ${imported.length} 本书籍'),
      ));
    }
  }

  void _openLocalBook(LocalBook lb) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ReaderPage(
        aid: lb.id,
        book: lb.toBook(),
        volumes: lb.volumes,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(icon: const Icon(Icons.file_upload_outlined), tooltip: '导入本地书', onPressed: _importLocal),
          IconButton(
            icon: Icon(_gridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
        ],
      ),
      body: StreamBuilder<List<ShelfEntry>>(
        stream: ShelfService.instance.entries,
        builder: (ctx, snap) {
          final entries = snap.data ?? ShelfService.instance.list;
          final locals = LocalLibraryService.instance.books;
          if (entries.isEmpty && locals.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmarks_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('书架空空如也', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('去发现页添加书籍，或点右上角导入本地书', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          if (_gridView) {
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                childAspectRatio: 0.65,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: entries.length + locals.length,
              itemBuilder: (ctx, i) {
                if (i < entries.length) return _ShelfGridCard(entries[i]);
                return _LocalGridCard(locals[i - entries.length], onOpen: _openLocalBook);
              },
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: entries.length + locals.length,
            itemBuilder: (ctx, i) {
              if (i < entries.length) return _ShelfListTile(entries[i]);
              return _LocalListTile(locals[i - entries.length], onOpen: _openLocalBook);
            },
          );
        },
      ),
    );
  }
}

/// 本地书网格卡片
class _LocalGridCard extends StatelessWidget {
  final LocalBook book;
  final void Function(LocalBook) onOpen;
  const _LocalGridCard(this.book, {required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpen(book),
      onLongPress: () async {
        final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          title: Text(book.title),
          content: const Text('从本地书库移除？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('移除')),
          ],
        ));
        if (ok == true) await LocalLibraryService.instance.remove(book.id);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      color: const Color(0xFFE8DCC8),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(8),
                      child: Text(book.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF5B4636))),
                    ),
                  ),
                ),
                Positioned(
                  top: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.teal.withOpacity(0.85), borderRadius: BorderRadius.circular(3)),
                    child: Text(book.format.toUpperCase(), style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// 本地书列表项
class _LocalListTile extends StatelessWidget {
  final LocalBook book;
  final void Function(LocalBook) onOpen;
  const _LocalListTile(this.book, {required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 50, height: 70,
        color: const Color(0xFFE8DCC8),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        child: Text(book.format.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5B4636))),
      ),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${book.totalChars ~/ 1000} 千字 · 本地导入', style: const TextStyle(fontSize: 12)),
      onTap: () => onOpen(book),
      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => LocalLibraryService.instance.remove(book.id)),
    );
  }
}

class _ShelfGridCard extends StatelessWidget {
  final ShelfEntry entry;
  const _ShelfGridCard(this.entry);

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => BookDetailPage(aid: book.aid, book: book))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: book.coverUrl ?? '',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => const ColoredBox(
                        color: Color(0xFFE0E0E0),
                        child: Center(child: Icon(Icons.book, color: Colors.grey))),
                    errorWidget: (_, __, ___) => const ColoredBox(
                        color: Color(0xFFE0E0E0),
                        child: Center(child: Icon(Icons.book, color: Colors.grey))),
                  ),
                ),
                if (entry.lastChapterTitle != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                      ),
                      child: Text(
                        entry.lastChapterTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ShelfListTile extends StatelessWidget {
  final ShelfEntry entry;
  const _ShelfListTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: book.coverUrl ?? '',
          width: 50,
          height: 70,
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox(width: 50, height: 70, child: ColoredBox(color: Color(0xFFE0E0E0))),
          errorWidget: (_, __, ___) => const SizedBox(width: 50, height: 70, child: ColoredBox(color: Color(0xFFE0E0E0))),
        ),
      ),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.lastChapterTitle != null
            ? '读到: ${entry.lastChapterTitle}'
            : '未开始阅读',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => BookDetailPage(aid: book.aid, book: book))),
    );
  }
}
