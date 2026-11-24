// 从 sitemap 提取的 aid 列表生成最小目录（仅 aid，标题在运行时懒加载）
// 这个脚本在 GitHub Actions runner 上运行（避免本地 IP 被 Cloudflare 封禁）
const fs = require('fs');
const https = require('https');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const td = new TextDecoder('gbk');

function fetchText(url) {
  return new Promise((resolve, reject) => {
    fetch(url, { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(20000) })
      .then(async r => {
        const buf = Buffer.from(await r.arrayBuffer());
        resolve(td.decode(buf));
      })
      .catch(reject);
  });
}

async function fetchBook(aid) {
  try {
    const r = await fetch(`https://www.wenku8.net/book/${aid}.htm`, {
      headers: { 'User-Agent': UA, 'Referer': 'https://www.wenku8.net/' },
      signal: AbortSignal.timeout(15000),
    });
    if (r.status !== 200) return null;
    const buf = Buffer.from(await r.arrayBuffer());
    const html = td.decode(buf);
    const titleMatch = html.match(/<title>([^<]+)<\/title>/);
    let title = '', author = '', category = '';
    if (titleMatch) {
      const parts = titleMatch[1].split(' - ');
      title = parts[0]?.trim() || '';
      author = parts[1]?.trim() || '';
      category = parts[2]?.trim() || '';
    }
    if (!title || title === '轻小说文库' || title.includes('404') || title.includes('Access denied')) return null;

    let status = null;
    const statusMatch = html.match(/文章状态[^<]*<[^>]+>([^<]+)/);
    if (statusMatch) {
      const s = statusMatch[1].trim();
      if (s.includes('完结')) status = 1;
      else if (s.includes('连载')) status = 0;
    }

    let bookSize = null;
    const sizeMatch = html.match(/(?:字数|文章字数|文库分类)[^<]*<[^>]+>([\d,]+)/);
    if (sizeMatch) bookSize = parseInt(sizeMatch[1].replace(/,/g, ''));

    return [parseInt(aid), title, author, category, status, bookSize];
  } catch (e) {
    return null;
  }
}

async function main() {
  // 1. 获取 sitemap 提取所有 aid
  console.log('Fetching sitemap...');
  const xml = await fetchText('https://www.wenku8.net/sitemap.xml');
  const aids = [...new Set([...xml.matchAll(/\/book\/(\d+)\.htm/g)].map(m => parseInt(m[1])))].sort((a, b) => a - b);
  console.log(`Found ${aids.length} aids in sitemap`);

  // 2. 批量抓取书页（单并发，800ms 间隔）
  console.log('Fetching book pages...');
  const results = [];
  let done = 0, failed = 0, consecutiveFails = 0;

  for (let i = 0; i < aids.length; i++) {
    const aid = aids[i];
    const r = await fetchBook(aid);
    if (r) {
      results.push(r);
      consecutiveFails = 0;
    } else {
      failed++;
      consecutiveFails++;
      if (consecutiveFails >= 10) {
        console.log(`  Pausing 30s after ${consecutiveFails} consecutive failures...`);
        await new Promise(r => setTimeout(r, 30000));
        consecutiveFails = 0;
      }
    }
    done++;

    if (done % 100 === 0 || done === aids.length) {
      console.log(`  Progress: ${done}/${aids.length} (ok=${results.length}, fail=${failed})`);
      results.sort((a, b) => a[0] - b[0]);
      fs.writeFileSync('assets/catalog/catalog.json', JSON.stringify(results));
    }

    if (i + 1 < aids.length) {
      await new Promise(r => setTimeout(r, 800));
    }
  }

  results.sort((a, b) => a[0] - b[0]);
  fs.writeFileSync('assets/catalog/catalog.json', JSON.stringify(results));
  console.log(`\nDone! ${results.length} books saved.`);
}

main().catch(e => { console.error(e); process.exit(1); });
