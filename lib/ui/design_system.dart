/// 奶白玻璃材质、档案式排版、立体书架 —— 三大设计语言组件。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

// ---------------- 奶白玻璃 ----------------

/// 奶白色主题令牌。
class CreamTokens {
  static const bgBase = Color(0xFFF7F2EA); // 页面底色（奶白）
  static const bgDeep = Color(0xFFEFE7DA); // 次级底色
  static const glassTint = Color(0xCCFBF8F2); // 玻璃奶白
  static const glassBorder = Color(0x1A000000);
  static const ink = Color(0xFF3B342B); // 墨色文字
  static const inkSoft = Color(0xFF8A8071);
  static const accent = Color(0xFFB4884A); // 档案铜金
  static const shelfBoard = Color(0xFFD9C9B0); // 书架板色
  static const spineColors = <Color>[
    Color(0xFFA9553D),
    Color(0xFF4E6E58),
    Color(0xFF35547A),
    Color(0xFF8A6A3B),
    Color(0xFF6B4A6E),
    Color(0xFF7A4E3A),
    Color(0xFF3E5F66),
    Color(0xFF946A4F),
  ];
}

/// 奶白玻璃容器：BackdropFilter 模糊 + 奶白半透明 + 细边 + 高光。
class CreamGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final BorderRadius radius;
  const CreamGlass({
    super.key,
    required this.child,
    this.blur = 18,
    this.padding,
    this.radius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: CreamTokens.glassTint,
            borderRadius: radius,
            border: Border.all(color: CreamTokens.glassBorder),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x14FFFFFF), Color(0x00000000)],
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

// ---------------- 档案式排版 ----------------

/// 档案卡片：编号 + 分类签 + 衬线标题 + 元信息 + 分割线。
class ArchiveCard extends StatelessWidget {
  final String serial; // 档案编号，如 A-1024
  final String title;
  final String subtitle;
  final List<String> tags;
  final VoidCallback? onTap;
  final Widget? leading;

  const ArchiveCard({
    super.key,
    required this.serial,
    required this.title,
    required this.subtitle,
    this.tags = const [],
    this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return CreamGlass(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(serial,
                          style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            color: CreamTokens.accent,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(height: 1, color: CreamTokens.glassBorder),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.3,
                        color: CreamTokens.ink,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Songti',
                      )),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: CreamTokens.inkSoft, height: 1.5)),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x14B4884A),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0x33B4884A)),
                            ),
                            child: Text(t,
                                style: const TextStyle(
                                    fontSize: 11, color: CreamTokens.accent)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 档案页眉：大号衬线标题 + 底部双线。
class ArchiveHeader extends StatelessWidget {
  final String title;
  final String? note;
  const ArchiveHeader({super.key, required this.title, this.note});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: CreamTokens.ink,
              fontFamily: 'Songti',
              letterSpacing: 4,
            )),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!,
              style: const TextStyle(
                  fontSize: 12, letterSpacing: 2, color: CreamTokens.inkSoft)),
        ],
        const SizedBox(height: 10),
        Container(height: 3, color: CreamTokens.accent),
        const SizedBox(height: 2),
        Container(height: 1, color: CreamTokens.glassBorder),
      ],
    );
  }
}

// ---------------- 立体书架 ----------------

/// 一层立体书架：奶白底 + 多层阴影书板 + 直立书脊。
class BookshelfLayer extends StatelessWidget {
  final List<ShelfBook> books;
  final int columns;
  final void Function(ShelfBook book)? onBookTap;

  const BookshelfLayer({
    super.key,
    required this.books,
    this.columns = 6,
    this.onBookTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 18,
          children: [
            for (var i = 0; i < books.length; i++)
              _Spine(
                book: books[i],
                color:
                    CreamTokens.spineColors[i % CreamTokens.spineColors.length],
                onTap: onBookTap == null ? null : () => onBookTap!(books[i]),
              ),
          ],
        ),
        // 立体书板：三层渐变营造厚度
        Container(
          height: 12,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFE7D9C2),
                CreamTokens.shelfBoard,
                Color(0xFFB39B77),
              ],
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 22,
                offset: Offset(0, 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ShelfBook {
  final String aid;
  final String title;
  final String? coverUrl;
  final String? progressNote;
  const ShelfBook({
    required this.aid,
    required this.title,
    this.coverUrl,
    this.progressNote,
  });
}

class _Spine extends StatelessWidget {
  final ShelfBook book;
  final Color color;
  final VoidCallback? onTap;
  const _Spine({required this.book, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 书脊
          Container(
            width: 62,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.lerp(color, Colors.black, 0.25)!,
                  color,
                  Color.lerp(color, Colors.white, 0.18)!,
                ],
                stops: const [0, 0.55, 1],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(3),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(3, 4),
                ),
                const BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 3,
                  offset: Offset(-1, 0),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
            child: Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xF2FBF8F2),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // 书底反光
          Container(
            width: 62,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
