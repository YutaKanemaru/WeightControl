// App Store のプレビュー画像を書き出すスクリプト（アプリ本体には含まれません）。
// 使いかた: node docs/app-store/source/render.mjs
// 必要なもの: Node.js と Playwright（npm i -D playwright）。フォントは Google Fonts から読み込みます。
//
// 6.9 インチ（1320×2868）と 6.5 インチ（1284×2778）を、6 枚ずつ PNG で書き出します。
import { createRequire } from "node:module";
const { chromium } = createRequire(import.meta.url)("playwright");
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "../screenshots");
const sizes = [
  { name: "6.9", width: 1320, height: 2868 },
  { name: "6.5", width: 1284, height: 2778 },
];

const browser = await chromium.launch();
for (const size of sizes) {
  // 3 倍の解像度で描くので、ページの大きさは 1/3
  const page = await browser.newPage({
    viewport: { width: size.width / 3, height: size.height / 3 },
    deviceScaleFactor: 3,
  });
  for (let shot = 1; shot <= 6; shot++) {
    await page.goto(`file://${path.join(here, "screens.html")}?shot=${shot}`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    const file = path.join(outDir, size.name, `${shot}.png`);
    await page.screenshot({ path: file });
    console.log(file);
  }
  await page.close();
}
await browser.close();
