# 轻小说文库 iPad 阅读器

Flutter iPad 阅读器，对标 P5UEDGK/Wenku8_Flutter 界面和功能风格。

## 功能

### 在线阅读
- 网页爬虫：书页 → 目录 → 正文（匿名无需登录）
- 全本 TXT 下载：`dl.wenku8.com/down.php`
- 章节正文：`div#content` 栈法提取，GBK 解码

### 发现/搜索
- 本地目录快照（4328 本，CI 时从 sitemap 批量抓取）
- 推荐 / 排行 / 分类三个 Tab
- 书名/作者搜索

### 书架
- 网格/列表切换
- 阅读进度记录
- 最近阅读排序

### 阅读器
- 纵向滚动 + 左右滑动翻章
- 字号/行距/背景色/夜间模式
- 章节目录侧边栏
- 阅读进度自动保存

### 登录
- wenku8.net 登录 UI（当前站点登录已失效，保留供恢复后使用）

## 数据源

| 功能 | 状态 | 说明 |
|---|---|---|
| 书页 `/book/{aid}.htm` | ✅ | 匿名可用，GBK 编码 |
| 目录 `/novel/{n}/{aid}/index.htm` | ✅ | `.vcss` 卷 + `.ccss` 章 |
| 正文 `/novel/{n}/{aid}/{cid}.htm` | ✅ | `div#content` |
| TXT下载 `dl.wenku8.com` | ✅ | 全本 TXT |
| 封面图 `img.wenku8.com` | ✅ | |
| 排行/搜索/分类 | ❌ | 需登录，站点已失效 |
| 本地目录快照 | ✅ | 4328 本 |

## 构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```

GitHub Actions CI 在 `macos-15` 上构建 unsigned IPA。
