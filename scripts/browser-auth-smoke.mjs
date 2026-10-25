import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import assert from 'node:assert/strict';
import { readFile, mkdir } from 'node:fs/promises';

const qa = JSON.parse(await readFile('.local/hosted-qa.json', 'utf8'));
const origin = 'http://127.0.0.1:3200';
await mkdir('.local/screens', { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
try {
  for (const width of [1440, 390]) {
    const context = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await context.newPage();
    await page.goto(`${origin}/login`);
    await page.locator('input[name="email"]').fill(qa.users[0].email);
    await page.locator('input[name="password"]').fill(qa.users[0].password);
    await page.getByRole('button', { name: 'Log in' }).click();
    await page.waitForURL(/\/workspaces(?:\?|$)/, { timeout: 15000 });
    const slug = qa.businesses[0].slug;
    for (const route of [`/app/${slug}/overview`, `/app/${slug}/calendar`, `/app/${slug}/bookings`, `/app/${slug}/customers`, `/app/${slug}/reports`]) {
      const response = await page.goto(origin + route, { waitUntil: 'domcontentloaded' });
      assert.equal(response.status(), 200, route);
      assert.equal(await page.locator('h1').count(), 1, `${route} has one h1`);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 2), false, `${route} overflow at ${width}`);
      if (route.endsWith('/overview')) {
        await page.screenshot({ path: `.local/screens/workspace-${width}.png`, fullPage: true });
        const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
        assert.equal(axe.violations.length, 0, JSON.stringify(axe.violations.map(v => ({ id: v.id, targets: v.nodes.map(n => n.target) }))));
      }
    }
    if (width === 1440) {
      const exportResponse = await page.request.get(`${origin}/api/workspaces/${slug}/reports.csv?range=7&date=2026-10-25`);
      assert.equal(exportResponse.status(), 200, 'owner CSV export');
      assert.match(exportResponse.headers()['content-type'], /text\/csv/);
      assert.match(await exportResponse.text(), /Booking value \(BDT\)/);
    }
    await context.close();
    console.log(`PASS: authenticated workspace routes, no horizontal overflow, overview accessibility at ${width}px`);
  }
} finally { await browser.close(); }
