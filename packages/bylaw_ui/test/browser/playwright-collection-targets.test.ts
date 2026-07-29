import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  equalWidths,
  everyInside,
  sameWidth,
  type CollectionFinding,
} from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import { browserHarness, expectPassed } from "./logical-target-support";

const withPage = browserHarness();

test("an explicit collection target resolves every exact data-testid match", () =>
  withPage(
    '<div data-testid="card" style="width:20px;height:10px"></div><div data-testid="card" style="width:20px;height:10px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page),
        rules: [equalWidths(collection("card"))],
      });
      expectPassed(report);
    },
  ));

test("an exact data-testid collection preserves DOM order", () =>
  withPage(
    '<div data-testid="card" style="width:30px;height:10px"></div><div data-testid="card" style="width:10px;height:10px"></div><div data-testid="card" style="width:20px;height:10px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page),
        rules: [equalWidths(collection("card"))],
      });
      const findings = report.findings as Extract<
        CollectionFinding,
        { collectionIndex: number }
      >[];
      expect(findings.map(({ collectionIndex }) => collectionIndex)).toEqual([
        1, 2,
      ]);
      expect(findings.map(({ actual }) => actual.referenceWidthPx)).toEqual([
        30, 30,
      ]);
    },
  ));

test("a registered collection locator resolves every match in locator order", () =>
  withPage(
    '<div class="card" style="width:30px;height:10px"></div><div class="card" style="width:10px;height:10px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: page.locator(".card") },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      expect(report.findings[0]).toMatchObject({
        collectionIndex: 1,
        actual: { referenceWidthPx: 30, memberWidthPx: 10 },
      });
    },
  ));

test("a scoped collection locator excludes matching elements outside its container", () =>
  withPage(
    '<div class="card" style="width:40px;height:10px"></div><section aria-label="Files"><div class="card" style="width:20px;height:10px"></div><div class="card" style="width:20px;height:10px"></div></section>',
    async (page) => {
      const files = page.getByRole("region", { name: "Files" });
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: files.locator(".card") },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      expectPassed(report);
    },
  ));

test("the same multi-match locator resolves only when declared as a collection", () =>
  withPage(
    '<div class="card" style="width:20px;height:10px"></div><div class="card" style="width:20px;height:10px"></div><div class="peer" style="width:20px;height:10px"></div>',
    async (page) => {
      const locator = page.locator(".card");
      const collectionReport = await checkLayout({
        adapter: playwright(page, { targets: { cards: locator } }),
        rules: [equalWidths(collection("cards"))],
      });
      const singularReport = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: locator, peer: page.locator(".peer") },
        }),
        rules: [sameWidth("cards", "peer")],
      });
      expect(collectionReport.passed).toBe(true);
      expect(singularReport.findings[0]?.code).toBe("duplicate-element");
    },
  ));

test("an empty registered collection does not fall back to a matching data-testid", () =>
  withPage(
    '<div data-testid="cards" style="width:20px;height:10px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: page.locator(".missing") },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      expect(report.findings[0]).toMatchObject({
        code: "empty-collection",
        actual: { matchCount: 0 },
      });
    },
  ));

test("a Playwright rule evaluates a collection locator against a singular locator", () =>
  withPage(
    '<section class="container" style="width:100px;height:100px"><div class="card" style="width:20px;height:20px"></div><div class="card" style="width:20px;height:20px"></div></section>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            cards: page.locator(".card"),
            container: page.locator(".container"),
          },
        }),
        rules: [everyInside(collection("cards"), "container")],
      });
      expectPassed(report);
    },
  ));

/**
 * @doc
 * Issue: Registered Playwright measurements are keyed only by target name, so
 * a collection request and singular request with the same name overwrite each
 * other instead of retaining their distinct resolution modes.
 *
 * Why it matters: A valid collection rule can fail during snapshot validation
 * when one registered locator intentionally serves both operands.
 */
test("a registered locator can be measured as both a collection and singular target with the same name", () =>
  withPage(
    '<section class="card" style="width:100px;height:100px"></section>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { card: page.locator(".card") },
        }),
        rules: [everyInside(collection("card"), "card")],
      });
      expectPassed(report);
    },
  ));

test("Playwright collection resolution does not mutate the DOM", () =>
  withPage(
    '<main id="root"><div class="card" style="width:20px;height:10px"></div><div class="card" style="width:20px;height:10px"></div></main>',
    async (page) => {
      const before = await page
        .locator("#root")
        .evaluate((node) => node.outerHTML);
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: page.locator(".card") },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      expectPassed(report);
      expect(
        await page.locator("#root").evaluate((node) => node.outerHTML),
      ).toBe(before);
    },
  ));

test("a browser collection finding identifies a hidden middle member", () =>
  withPage(
    '<div class="card" style="width:20px;height:10px"></div><div class="card" style="display:none;width:20px;height:10px"></div><div class="card" style="width:20px;height:10px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: page.locator(".card") },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      expect(report.findings[0]).toMatchObject({
        code: "hidden-element",
        target: "cards",
        collectionIndex: 1,
      });
    },
  ));

test("a browser collection finding identifies a zero-size middle member", () =>
  withPage(
    '<div class="card" style="width:20px;height:10px"></div><div class="card" style="width:0;height:10px"></div><div class="card" style="width:20px;height:10px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: page.locator(".card") },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      expect(report.findings[0]).toMatchObject({
        code: "zero-size-element",
        target: "cards",
        collectionIndex: 1,
      });
    },
  ));

test("collection locators resolve immediately from the current page state without waiting", () =>
  withPage("", async (page) => {
    await page.evaluate(() => {
      setTimeout(() => {
        const card = document.createElement("div");
        card.className = "card";
        card.style.cssText = "width:20px;height:10px";
        document.body.append(card);
      }, 250);
    });
    const startedAt = performance.now();
    const report = await checkLayout({
      adapter: playwright(page, {
        targets: { cards: page.locator(".card") },
      }),
      rules: [equalWidths(collection("cards"))],
    });
    expect(report.findings[0]).toMatchObject({ code: "empty-collection" });
    expect(performance.now() - startedAt).toBeLessThan(200);
  }));
