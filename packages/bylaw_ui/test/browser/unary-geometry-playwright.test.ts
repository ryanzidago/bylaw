import { afterAll, afterEach, beforeAll, expect, test } from "bun:test";
import { chromium, type Browser, type Page } from "playwright-core";

import { checkLayout, height, inViewport, width } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";

let browser: Browser;

beforeAll(async () => {
  browser = await chromium.launch({ headless: true });
});

afterAll(async () => {
  await browser.close();
});

afterEach(() => {
  expect(browser.contexts()).toHaveLength(0);
});

async function withPage<T>(
  run: (page: Page) => Promise<T>,
  viewport = { width: 800, height: 600 },
): Promise<T> {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  try {
    return await run(page);
  } finally {
    await context.close();
  }
}

async function setBody(page: Page, body: string) {
  await page.setContent(
    `<style>* { box-sizing: border-box } html, body { margin: 0; padding: 0 }</style>${body}`,
  );
}

test("Playwright evaluates width from the rendered border rectangle in CSS pixels", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="sidebar" style="box-sizing:content-box;width:250px;height:100px;padding:8px;border:2px solid"></div>',
    );
    const report = await checkLayout({
      adapter: playwright(page),
      rules: [width("sidebar", { minPx: 270, maxPx: 270 })],
    });
    expect(report.passed).toBe(true);
  }));

test("Playwright evaluates height from the rendered border rectangle in CSS pixels", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="toolbar" style="box-sizing:content-box;width:100px;height:36px;padding:4px;border:2px solid"></div>',
    );
    const report = await checkLayout({
      adapter: playwright(page),
      rules: [height("toolbar", { minPx: 48, maxPx: 48 })],
    });
    expect(report.passed).toBe(true);
  }));

test("Playwright evaluates transformed dimensions from the rendered bounding rectangle", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="card" style="width:120px;height:40px;transform:scale(1.5);transform-origin:top left"></div>',
    );
    const report = await checkLayout({
      adapter: playwright(page),
      rules: [
        width("card", { minPx: 180, maxPx: 180 }),
        height("card", { minPx: 60, maxPx: 60 }),
      ],
    });
    expect(report.rules.passed).toBe(2);
  }));

test("Playwright inViewport changes from passing to failing after the target scrolls out of view", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="target" style="position:absolute;top:100px;width:100px;height:100px"></div><div style="height:2000px"></div>',
    );
    const rule = inViewport("target");
    expect(
      (await checkLayout({ adapter: playwright(page), rules: [rule] })).passed,
    ).toBe(true);

    await page.evaluate(() => window.scrollTo(0, 500));

    expect(
      (await checkLayout({ adapter: playwright(page), rules: [rule] })).passed,
    ).toBe(false);
  }));
