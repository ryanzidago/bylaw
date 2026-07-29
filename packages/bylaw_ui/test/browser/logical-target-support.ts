import { afterAll, afterEach, beforeAll, expect } from "bun:test";
import { chromium, type Browser, type Page } from "playwright-core";

import type { LayoutReport } from "bylaw-ui";

export function browserHarness() {
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

  return async function withPage<T>(
    markup: string,
    run: (page: Page) => Promise<T>,
  ): Promise<T> {
    const context = await browser.newContext({
      viewport: { width: 800, height: 600 },
    });
    const page = await context.newPage();

    try {
      await page.setContent(
        `<style>*{box-sizing:border-box}html,body{margin:0;padding:0}</style>${markup}`,
      );
      return await run(page);
    } finally {
      await context.close();
    }
  };
}

export function expectPassed(report: LayoutReport, total = 1) {
  expect(report).toEqual({
    passed: true,
    rules: { total, passed: total, failed: 0, skipped: 0 },
    findings: [],
  });
}

export function expectElementFinding(
  report: LayoutReport,
  expected: {
    category: "element-resolution" | "element-visibility";
    code:
      | "missing-element"
      | "duplicate-element"
      | "hidden-element"
      | "zero-size-element";
    operand: "subject" | "reference";
    testId: string;
    actual: object;
  },
) {
  expect(report.passed).toBe(false);
  expect(report.rules).toEqual({
    total: 1,
    passed: 0,
    failed: 0,
    skipped: 1,
  });
  expect(report.findings).toHaveLength(1);
  expect(report.findings[0]).toMatchObject(expected);
}
