/// 奶白玻璃材质、档案式排版、立体书架 —— 三大设计语言组件。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

// ---------------- 奶白玻璃 ----------------

/// 全局玻璃效果开关（性能设置联动，main.dart 每帧写入）。
class GlassPrefs {
  static bool enabled = true;
}

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
    final content = Container(
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
    );
    // GlassPrefs.enabled = false 时跳过 BackdropFilter（低性能模式）
    if (!GlassPrefs.enabled) {
      return ClipRRect(borderRadius: radius, child: content);
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
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
  final Widget? trailing; // 右侧附加操作（如删除按钮）

  const ArchiveCard({
    super.key,
    required this.serial,
    required this.title,
    required this.subtitle,
    this.tags = const [],
    this.onTap,
    this.leading,
    this.trailing,
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
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
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

// ---------------- 陈列书架（发现页） ----------------

/// 一册立体陈列书：平放书板（带封面缩略）+ 直立书脊，两张为一组交叠。
/// 仿 wenku8 纪念站书架陈列：中间书直立立起（正面朝外），左右书直立排开（只见书脊）。
class DisplayShelf extends StatelessWidget {
  final List<DisplayBook> books;
  final int uprightIndex; // 本组中立起的书下标
  final void Function(DisplayBook book)? onBookTap;
  final double spineWidth;
  final double uprightWidth;

  const DisplayShelf({
    super.key,
    required this.books,
    this.uprightIndex = -1,
    this.onBookTap,
    this.spineWidth = 34,
    this.uprightWidth = 118,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(top: 10),
          // 底板阴影
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x14000000), Color(0x00000000)],
            ),
          ),
          // C2 修复：窄屏等比缩放整架，防 RenderFlex overflow
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < books.length; i++)
                  _DisplayBookWidget(
                    book: books[i],
                    upright: i == uprightIndex,
                    spineWidth: spineWidth,
                    uprightWidth: uprightWidth,
                    tilt: (i - (uprightIndex >= 0 ? uprightIndex : 0))
                        .clamp(-1, 1),
                    onTap: onBookTap == null
                        ? null
                        : () => onBookTap!(books[i]),
                  ),
              ],
            ),
          ),
        ),
        // 书板（三层厚度）
        Container(
          height: 10,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFEDE1CD),
                Color(0xFFC7B08B),
                Color(0xFFA08860),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x2E000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DisplayBook {
  final String aid;
  final String title;
  final String? author;
  final String? coverUrl;
  final Color spineColor;
  const DisplayBook({
    required this.aid,
    required this.title,
    this.author,
    this.coverUrl,
    required this.spineColor,
  });
}

class _DisplayBookWidget extends StatelessWidget {
  final DisplayBook book;
  final bool upright; // 立起：正面朝外（显示封面）
  final double spineWidth;
  final double uprightWidth;
  final int tilt; // -1 左倾 / 0 中 / 1 右倾（相邻书的交叠错落）
  final VoidCallback? onTap;

  const _DisplayBookWidget({
    required this.book,
    required this.upright,
    required this.spineWidth,
    required this.uprightWidth,
    required this.tilt,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spine = GestureDetector(
      onTap: onTap,
      child: Container(
        width: spineWidth,
        height: 168,
        margin: EdgeInsets.symmetric(
            horizontal: 1, vertical: tilt == 0 ? 0 : (tilt.abs() * 2.0)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.lerp(book.spineColor, Colors.black, 0.30)!,
              book.spineColor,
              Color.lerp(book.spineColor, Colors.white, 0.15)!,
            ],
            stops: const [0, 0.5, 1],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(3),
            topRight: Radius.circular(3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.30),
              blurRadius: 6,
              offset: Offset(tilt * 4.0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 编号签
            Text(
              'N ${book.aid}',
              style: const TextStyle(
                color: Color(0xAAFBF8F2),
                fontSize: 8,
                letterSpacing: 0.5,
              ),
            ),
            // 竖排标题
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xE6FBF8F2),
                      fontSize: upright ? 11 : 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!upright) return spine;

    // 立起书：正面封面 + 黑白档案风边框
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: uprightWidth,
        height: 172,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
          border: Border.all(color: const Color(0x22000000)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // 顶部档案编号条
            Container(
              height: 18,
              color: Colors.black,
              alignment: Alignment.center,
              child: Text(
                'NO.${book.aid.padLeft(3, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 封面
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: book.coverUrl != null
                    ? Image.network(
                        book.coverUrl!,
                        fit: BoxFit.cover,
                        // M4 修复：删除错误 loadingBuilder（会在加载中/无
                        // Content-Length 时永远显示黑底 fallback）
                        errorBuilder: (_, __, ___) => _coverFallback(),
                      )
                    : _coverFallback(),
              ),
            ),
            // 底部书名条
            Container(
              height: 22,
              color: Colors.white,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback() => Container(
        color: const Color(0xFF2B2B2B),
        alignment: Alignment.center,
        child: Text(
          book.title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: 'Songti',
          ),
        ),
      );
}
