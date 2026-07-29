import { afterAll, afterEach, beforeAll, expect, test } from "bun:test";
import { chromium, type Browser, type Page } from "playwright-core";

import { align, checkLayout, sameSize, type LayoutFinding } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import type { RawMeasurementSnapshot } from "../../src/internal/adapter";

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

async function snapshot(
  page: Page,
  testIds: readonly string[],
): Promise<RawMeasurementSnapshot> {
  return (await playwright(page).measure(testIds)) as RawMeasurementSnapshot;
}

async function setBody(page: Page, body: string) {
  await page.setContent(
    `<style>* { box-sizing: border-box } html, body { margin: 0; padding: 0 }</style>${body}`,
  );
}

function firstRect(measurement: RawMeasurementSnapshot) {
  const rectangle = measurement.elements[0]?.rect;
  expect(rectangle).not.toBeNull();
  return rectangle!;
}

test("exports the Playwright integration from the Playwright entrypoint", async () => {
  const entrypoint = await import("bylaw-ui/playwright");
  expect(entrypoint.playwright).toBe(playwright);
});

test("exports playwright from bylaw-ui/playwright", async () => {
  const entrypoint = await import("bylaw-ui/playwright");
  expect(entrypoint).toMatchObject({
    playwright,
    waitForLayoutTargets: expect.any(Function),
  });
});

test("does not export playwright from the package root", async () => {
  const root = await import("bylaw-ui");
  expect(root).not.toHaveProperty("playwright");
});

test("the Playwright integration accepts a playwright-core Page", () =>
  withPage(async (page) => {
    expect(playwright(page)).toBeDefined();
  }));

/**
 * Issue: Array values pass runtime validation as Playwright options.
 * Why it matters: JavaScript callers receive an adapter for a malformed public
 * input instead of an immediate actionable boundary error.
 */
test("rejects an array as Playwright options", () =>
  withPage(async (page) => {
    expect(() => playwright(page, [] as never)).toThrow(TypeError);
  }));

/**
 * Issue: Array target registries pass runtime validation as objects.
 * Why it matters: Numeric array properties can silently become logical target
 * registrations outside the declared public contract.
 */
test("rejects an array as the Playwright target registry", () =>
  withPage(async (page) => {
    expect(() => playwright(page, { targets: [] as never })).toThrow(TypeError);
  }));

test("the Playwright entrypoint has no import-time browser side effects", async () => {
  const before = browser.contexts().length;
  await import("bylaw-ui/playwright");
  expect(browser.contexts()).toHaveLength(before);
});

test("checkLayout accepts the adapter returned by the Playwright integration", () =>
  withPage(async (page) => {
    const report = await checkLayout({ adapter: playwright(page), rules: [] });
    expect(report.passed).toBe(true);
  }));

test("measures elements by exact data-testid value", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="avatar" style="width: 10px; height: 20px"></div>',
    );
    const result = await snapshot(page, ["avatar"]);
    expect(result.elements[0]).toMatchObject({
      testId: "avatar",
      count: 1,
      hidden: false,
    });
  }));

for (const [name, testId] of [
  ["handles test IDs containing spaces", "status badge"],
  ["handles test IDs containing quotes", `say "hello" and 'goodbye'`],
  ["handles test IDs containing CSS-special characters", "card:#1[data-x]"],
  ["handles Unicode test IDs", "κάρτα-🧭"],
] as const) {
  test(name, () =>
    withPage(async (page) => {
      await page.setContent("<div></div>");
      await page.locator("div").evaluate((element, id) => {
        element.setAttribute("data-testid", id);
        element.setAttribute("style", "width:10px;height:10px");
      }, testId);
      expect((await snapshot(page, [testId])).elements[0]?.count).toBe(1);
    }),
  );
}

test("matches data-testid values case-sensitively", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="Avatar" style="width:10px;height:10px"></div>',
    );
    const result = await snapshot(page, ["avatar"]);
    expect(result.elements[0]?.count).toBe(0);
  }));

test("distinguishes test IDs that differ only by case", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="Avatar" style="width:10px;height:10px"></div><div data-testid="avatar" style="width:20px;height:20px"></div>',
    );
    const result = await snapshot(page, ["Avatar", "avatar"]);
    expect(result.elements.map((element) => element.rect?.width)).toEqual([
      10, 20,
    ]);
  }));

test("preserves leading and trailing whitespace in test IDs", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid=" avatar " style="width:10px;height:10px"></div>',
    );
    const result = await snapshot(page, [" avatar ", "avatar"]);
    expect(result.elements.map(({ count }) => count)).toEqual([1, 0]);
  }));

test("measures the rendered border rectangle", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="position:absolute;left:12px;top:34px;width:56px;height:78px"></div>',
    );
    expect(firstRect(await snapshot(page, ["box"]))).toEqual({
      x: 12,
      y: 34,
      width: 56,
      height: 78,
    });
  }));

test("includes border and padding in the measured rectangle", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="box-sizing:content-box;width:20px;height:30px;padding:4px;border:2px solid"></div>',
    );
    expect(firstRect(await snapshot(page, ["box"]))).toMatchObject({
      width: 32,
      height: 42,
    });
  }));

test("measures transformed rendered geometry", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="width:20px;height:10px;transform:scale(2);transform-origin:top left"></div>',
    );
    expect(firstRect(await snapshot(page, ["box"]))).toMatchObject({
      width: 40,
      height: 20,
    });
  }));

test("uses the axis-aligned rectangle returned by getBoundingClientRect", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="position:absolute;left:100px;top:100px;width:40px;height:20px;transform:rotate(30deg)"></div>',
    );
    const measured = firstRect(await snapshot(page, ["box"]));
    const direct = await page
      .locator('[data-testid="box"]')
      .evaluate((element) => {
        const bounds = element.getBoundingClientRect();
        return {
          x: bounds.x,
          y: bounds.y,
          width: bounds.width,
          height: bounds.height,
        };
      });
    expect(measured).toEqual(direct);
  }));

test("reports coordinates in CSS pixels rather than device pixels", async () => {
  const context = await browser.newContext({
    viewport: { width: 800, height: 600 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();

  try {
    await setBody(
      page,
      '<div data-testid="box" style="position:absolute;left:10px;top:20px;width:30px;height:40px"></div>',
    );
    expect(firstRect(await snapshot(page, ["box"]))).toEqual({
      x: 10,
      y: 20,
      width: 30,
      height: 40,
    });
  } finally {
    await context.close();
  }
});

test("preserves fractional browser coordinates", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="position:absolute;left:10.25px;top:20.5px;width:30.75px;height:40.125px"></div>',
    );
    const measured = firstRect(await snapshot(page, ["box"]));
    expect(measured.x).not.toBe(Math.round(measured.x));
    expect(measured.y).not.toBe(Math.round(measured.y));
    expect(measured.width).not.toBe(Math.round(measured.width));
  }));

test("preserves negative viewport-relative coordinates", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="position:absolute;left:-20px;top:-30px;width:10px;height:10px"></div>',
    );
    expect(firstRect(await snapshot(page, ["box"]))).toMatchObject({
      x: -20,
      y: -30,
    });
  }));

test("uses the current viewport dimensions", () =>
  withPage(async (page) => {
    const result = await snapshot(page, []);
    expect(result.viewport).toEqual({ width: 800, height: 600 });
  }));

test("observes viewport changes between separate checks", () =>
  withPage(async (page) => {
    expect((await snapshot(page, [])).viewport).toEqual({
      width: 800,
      height: 600,
    });
    await page.setViewportSize({ width: 500, height: 400 });
    expect((await snapshot(page, [])).viewport).toEqual({
      width: 500,
      height: 400,
    });
  }));

test("reports coordinates relative to the current viewport", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div style="height:1000px"></div><div data-testid="box" style="width:10px;height:10px"></div>',
    );
    await page.evaluate(() => window.scrollTo(0, 500));
    const directY = await page
      .locator('[data-testid="box"]')
      .evaluate((element) => element.getBoundingClientRect().y);
    expect(firstRect(await snapshot(page, ["box"])).y).toBe(directY);
    expect(directY).toBeLessThan(1_000);
  }));

test("scrolling changes coordinates by the corresponding CSS-pixel offset", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="position:absolute;top:900px;width:10px;height:10px"></div><div style="height:2000px"></div>',
    );
    const before = firstRect(await snapshot(page, ["box"]));
    await page.evaluate(() => window.scrollTo(0, 333));
    const after = firstRect(await snapshot(page, ["box"]));
    expect(before.y - after.y).toBe(333);
  }));

test("uses the bounding rectangle of a fragmented inline element", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<p style="width:80px;font:16px sans-serif"><span data-testid="inline">a fragmented inline phrase spanning lines</span></p>',
    );
    const measured = firstRect(await snapshot(page, ["inline"]));
    const direct = await page
      .locator('[data-testid="inline"]')
      .evaluate((element) => {
        const bounds = element.getBoundingClientRect();
        return {
          x: bounds.x,
          y: bounds.y,
          width: bounds.width,
          height: bounds.height,
        };
      });
    expect(measured).toEqual(direct);
    expect(measured.height).toBeGreaterThan(16);
  }));

test("uses the axis-aligned bounding rectangle of a rotated element", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="width:40px;height:20px;transform:rotate(45deg)"></div>',
    );
    const measured = firstRect(await snapshot(page, ["box"]));
    expect(measured.width).toBeGreaterThan(40);
    expect(measured.height).toBeGreaterThan(20);
  }));

test("measures SVG elements using their rendered bounding rectangle", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<svg width="100" height="100"><rect data-testid="shape" x="10" y="20" width="30" height="40"/></svg>',
    );
    expect(firstRect(await snapshot(page, ["shape"]))).toEqual({
      x: 10,
      y: 20,
      width: 30,
      height: 40,
    });
  }));

test("reports zero matches without throwing", () =>
  withPage(async (page) => {
    const result = await snapshot(page, ["missing"]);
    expect(result.elements[0]).toEqual({
      testId: "missing",
      count: 0,
      hidden: null,
      rect: null,
    });
  }));

test("reports multiple matches without choosing one", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="duplicate"></div><div data-testid="duplicate"></div>',
    );
    expect((await snapshot(page, ["duplicate"])).elements[0]).toEqual({
      testId: "duplicate",
      count: 2,
      hidden: null,
      rect: null,
    });
  }));

test("reports browser-determined hidden states without throwing", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="hidden" style="width:10px;height:10px;visibility:hidden"></div>',
    );
    expect((await snapshot(page, ["hidden"])).elements[0]?.hidden).toBe(true);
  }));

test("does not wait implicitly for page readiness", () =>
  withPage(async (page) => {
    await setBody(page, '<div id="later"></div>');
    await page.evaluate(() => {
      setTimeout(() => {
        document.querySelector("#later")?.setAttribute("data-testid", "late");
      }, 100);
    });
    expect((await snapshot(page, ["late"])).elements[0]?.count).toBe(0);
  }));

test("measures all requested elements from one document snapshot", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="a" style="width:10px;height:10px"></div><div data-testid="b" style="width:10px;height:10px"></div>',
    );
    let calls = 0;
    const wrapped = {
      evaluate: async (...args: Parameters<Page["evaluate"]>) => {
        calls += 1;
        return (page.evaluate as (...values: typeof args) => Promise<unknown>)(
          ...args,
        );
      },
    } as unknown as Page;
    await checkLayout({
      adapter: playwright(wrapped),
      rules: [sameSize("a", "b"), align("a", "b", "top")],
    });
    expect(calls).toBe(1);
  }));

test("uses one snapshot when several rules reference the same element", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="a" style="width:10px;height:10px"></div><div data-testid="b" style="width:10px;height:10px"></div>',
    );
    const result = await snapshot(page, ["a", "b"]);
    expect(result.elements.map(({ testId }) => testId)).toEqual(["a", "b"]);
  }));

test("does not mix measurements from opposite sides of a synchronous layout mutation", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="a" style="width:10px;height:10px"></div><div data-testid="b" style="width:10px;height:10px"></div>',
    );
    await page.evaluate(() => {
      queueMicrotask(() => {
        for (const element of document.querySelectorAll<HTMLElement>(
          "[data-testid]",
        )) {
          element.style.width = "20px";
        }
      });
    });
    const result = await snapshot(page, ["a", "b"]);
    expect(result.elements.map((element) => element.rect?.width)).toEqual([
      20, 20,
    ]);
  }));

test("separate checkLayout calls observe subsequent DOM changes", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="a" style="width:10px;height:10px"></div><div data-testid="b" style="width:10px;height:10px"></div>',
    );
    expect(
      (
        await checkLayout({
          adapter: playwright(page),
          rules: [sameSize("a", "b")],
        })
      ).passed,
    ).toBe(true);
    await page.locator('[data-testid="b"]').evaluate((element: HTMLElement) => {
      element.style.width = "20px";
    });
    expect(
      (
        await checkLayout({
          adapter: playwright(page),
          rules: [sameSize("a", "b")],
        })
      ).passed,
    ).toBe(false);
  }));

test("measures the element state captured by the browser-side snapshot", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="box" style="width:10px;height:10px"></div>',
    );
    const before = await snapshot(page, ["box"]);
    await page
      .locator('[data-testid="box"]')
      .evaluate((element: HTMLElement) => {
        element.style.width = "30px";
      });
    expect(firstRect(before).width).toBe(10);
  }));

for (const [name, markup] of [
  [
    "treats a hidden attribute as unavailable even when author CSS overrides display",
    '<style>[hidden]{display:block}</style><div data-testid="target" hidden style="width:10px;height:10px"></div>',
  ],
  [
    "uses computed display values for the element and its ancestors",
    '<div style="display:none"><div data-testid="target" style="width:10px;height:10px"></div></div>',
  ],
  [
    "treats inherited visibility hidden as unavailable",
    '<div style="visibility:hidden"><div data-testid="target" style="width:10px;height:10px"></div></div>',
  ],
  [
    "treats any zero-opacity ancestor as making the element unavailable",
    '<div style="opacity:0"><div data-testid="target" style="width:10px;height:10px"></div></div>',
  ],
] as const) {
  test(name, () =>
    withPage(async (page) => {
      await setBody(page, markup);
      expect((await snapshot(page, ["target"])).elements[0]?.hidden).toBe(true);
    }),
  );
}

test("treats a descendant that restores visibility visible as available", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div style="visibility:hidden"><div data-testid="target" style="visibility:visible;width:10px;height:10px"></div></div>',
    );
    expect((await snapshot(page, ["target"])).elements[0]?.hidden).toBe(false);
  }));

test("treats positive fractional opacity on every ancestor as visible", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div style="opacity:.01"><div data-testid="target" style="opacity:.01;width:10px;height:10px"></div></div>',
    );
    expect((await snapshot(page, ["target"])).elements[0]?.hidden).toBe(false);
  }));

test("applies zero-size visibility after transformed geometry is measured", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="target" style="width:10px;height:10px;transform:scale(0)"></div><div data-testid="reference" style="width:10px;height:10px"></div>',
    );
    const report = await checkLayout({
      adapter: playwright(page),
      rules: [sameSize("target", "reference")],
    });
    expect(report.findings[0]?.code).toBe("zero-size-element");
  }));

test("reports a display-contents target without a rendered rectangle as unavailable", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="target" style="display:contents"><span>content</span></div><div data-testid="reference" style="width:10px;height:10px"></div>',
    );
    const report = await checkLayout({
      adapter: playwright(page),
      rules: [sameSize("target", "reference")],
    });
    expect(report.findings[0]?.code).toBe("zero-size-element");
  }));

test("does not wrap a Playwright timeout as a layout assertion error", async () => {
  const original = new Error("Timeout 1ms exceeded");
  const fakePage = {
    evaluate: async () => {
      throw original;
    },
  } as unknown as Page;
  const caught = await checkLayout({
    adapter: playwright(fakePage),
    rules: [sameSize("a", "b")],
  }).catch((error: unknown) => error);
  expect(caught).toBe(original);
});

test("unexpected execution errors are not presented as layout assertion failures", async () => {
  const original = new Error("page closed");
  const fakePage = {
    evaluate: async () => {
      throw original;
    },
  } as unknown as Page;
  const caught = await checkLayout({
    adapter: playwright(fakePage),
    rules: [sameSize("a", "b")],
  }).catch((error: unknown) => error);
  expect(caught).toBe(original);
  expect(caught).not.toHaveProperty("report");
});

test("browser reports remain JSON serializable", () =>
  withPage(async (page) => {
    await setBody(
      page,
      '<div data-testid="a" style="width:10px;height:10px"></div><div data-testid="b" style="width:20px;height:20px"></div>',
    );
    const report = await checkLayout({
      adapter: playwright(page),
      rules: [sameSize("a", "b")],
    });
    const roundTrip = JSON.parse(JSON.stringify(report)) as {
      findings: LayoutFinding[];
    };
    expect(roundTrip).toEqual(report);
  }));
