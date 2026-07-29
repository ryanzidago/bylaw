import { afterAll, afterEach, beforeAll, expect, test } from "bun:test";
import {
  chromium,
  type Browser,
  type BrowserContextOptions,
  type Page,
} from "playwright-core";

import {
  align,
  checkLayout,
  inside,
  leftOf,
  overlap,
  sameWidth,
} from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";

let browser: Browser;

beforeAll(async () => {
  browser = await chromium.launch({ headless: true });
});

afterEach(() => {
  expect(browser.contexts()).toHaveLength(0);
});

afterAll(async () => {
  await browser.close();
});

async function withMarkup(
  markup: string,
  run: (page: Page) => Promise<void>,
  options: BrowserContextOptions = { viewport: { width: 800, height: 600 } },
) {
  const context = await browser.newContext(options);
  const page = await context.newPage();

  try {
    await page.setContent(
      `<style>*{box-sizing:border-box}html,body{margin:0}body{font:16px sans-serif}</style>${markup}`,
    );
    await run(page);
  } finally {
    await context.close();
  }
}

test("browser validates a timeline avatar aligned beside its rail", () =>
  withMarkup(
    `
      <article style="position:relative;width:320px;height:96px;padding:16px">
        <div data-testid="avatar" style="position:absolute;left:16px;top:28px;width:40px;height:40px;border-radius:50%"></div>
        <div data-testid="timeline" style="position:absolute;left:64px;top:0;width:2px;height:96px"></div>
      </article>
    `,
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page),
        rules: [
          align("avatar", "timeline", "centerY"),
          leftOf("avatar", "timeline", { gap: { minPx: 8, maxPx: 8 } }),
        ],
      });
      expect(report.passed).toBe(true);
    },
  ));

test("browser validates a status badge overlapping its avatar", () =>
  withMarkup(
    `
      <div style="position:relative;width:64px;height:64px">
        <div data-testid="avatar" style="position:absolute;left:0;top:0;width:48px;height:48px;border-radius:50%"></div>
        <div data-testid="badge" style="position:absolute;left:36px;top:36px;width:16px;height:16px;border-radius:50%"></div>
      </div>
    `,
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page),
        rules: [
          overlap("badge", "avatar", {
            horizontal: { minPx: 12, maxPx: 12 },
            vertical: { minPx: 12, maxPx: 12 },
          }),
        ],
      });
      expect(report.passed).toBe(true);
    },
  ));

test("browser validates equal responsive cards at desktop and mobile widths", async () => {
  const markup = `
    <style>
      .grid { display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;padding:16px }
      .card { min-width:0;height:100px }
      @media(max-width:500px) { .grid { grid-template-columns:1fr } }
    </style>
    <div class="grid">
      <article class="card" data-testid="first"></article>
      <article class="card" data-testid="second"></article>
    </div>
  `;

  for (const viewport of [
    { width: 800, height: 600 },
    { width: 400, height: 600 },
  ]) {
    await withMarkup(
      markup,
      async (page) => {
        const report = await checkLayout({
          adapter: playwright(page),
          rules: [sameWidth("first", "second")],
        });
        expect(report.passed).toBe(true);
      },
      { viewport },
    );
  }
});

test("browser validates a panel control contained at exact boundaries", () =>
  withMarkup(
    `
      <section data-testid="panel" style="position:relative;width:320px;height:48px">
        <button data-testid="control" style="position:absolute;inset:0;width:320px;height:48px"></button>
      </section>
    `,
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page),
        rules: [inside("control", "panel")],
      });
      expect(report.passed).toBe(true);
    },
  ));

test("device scale factors 1 and 2 preserve CSS-pixel semantics", async () => {
  for (const deviceScaleFactor of [1, 2]) {
    await withMarkup(
      '<div data-testid="box" style="position:absolute;left:10px;top:20px;width:30px;height:40px"></div>',
      async (page) => {
        const adapter = playwright(page);
        const measured = (await adapter.measure(["box"])) as {
          elements: Array<{
            rect: { x: number; y: number; width: number; height: number } | null;
          }>;
        };
        expect(measured.elements[0]?.rect).toEqual({
          x: 10,
          y: 20,
          width: 30,
          height: 40,
        });
      },
      {
        viewport: { width: 800, height: 600 },
        deviceScaleFactor,
      },
    );
  }
});
