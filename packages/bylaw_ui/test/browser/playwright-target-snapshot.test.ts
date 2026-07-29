import { expect, test } from "bun:test";
import type { Locator } from "playwright-core";

import { checkLayout, sameSize } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import {
  browserHarness,
  expectElementFinding,
  expectPassed,
} from "./logical-target-support";

const withPage = browserHarness();

test("resolves registered targets from the current page state without waiting", () =>
  withPage(
    '<div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        setTimeout(() => {
          const target = document.createElement("div");
          target.className = "late";
          target.style.cssText = "width:20px;height:20px";
          document.body.append(target);
        }, 250);
      });
      const startedAt = performance.now();
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            late: page.locator(".late"),
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("late", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "missing-element",
        operand: "subject",
        testId: "late",
        actual: { matchCount: 0 },
      });
      expect(performance.now() - startedAt).toBeLessThan(200);
    },
  ));

/**
 * Issue: Registered handles and fallback targets can be measured from different
 * DOM states.
 * Why it matters: A check can report false layout or visibility findings when
 * the page changes while registered locators are being resolved.
 */
test("measures registered and fallback targets from one coherent page snapshot", () =>
  withPage(
    '<div class="registered" style="width:10px;height:10px"></div><div data-testid="fallback" style="width:10px;height:10px"></div>',
    async (page) => {
      const locator = page.locator(".registered");
      let resolutions = 0;
      const changingLocator = {
        elementHandles: async () => {
          const handles = await locator.elementHandles();
          resolutions += 1;

          if (resolutions === 1) {
            await page.evaluate(() => {
              document.body.innerHTML =
                '<div class="registered" style="width:20px;height:20px"></div><div data-testid="fallback" style="width:20px;height:20px"></div>';
            });
          }

          return handles;
        },
      } as Locator;
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { registered: changingLocator },
        }),
        rules: [sameSize("registered", "fallback")],
      });
      expectPassed(report);
      expect(resolutions).toBe(3);
    },
  ));

/**
 * Issue: Snapshot coherence checks only the originally captured handles and do
 * not detect a new match that makes a singular registered locator ambiguous.
 * Why it matters: Bylaw can evaluate an arbitrary first element even though the
 * locator no longer resolves exactly once.
 */
test("detects registered target ambiguity introduced during snapshot capture", () =>
  withPage(
    '<div class="registered" style="width:20px;height:20px"></div><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const locator = page.locator(".registered");
      let resolutions = 0;
      const changingLocator = {
        elementHandles: async () => {
          const handles = await locator.elementHandles();
          resolutions += 1;

          if (resolutions === 1) {
            await page.evaluate(() => {
              const duplicate = document.createElement("div");
              duplicate.className = "registered";
              duplicate.style.cssText = "width:20px;height:20px";
              document.body.append(duplicate);
            });
          }

          return handles;
        },
      } as Locator;
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            registered: changingLocator,
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("registered", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "duplicate-element",
        operand: "subject",
        testId: "registered",
        actual: { matchCount: 2 },
      });
    },
  ));
