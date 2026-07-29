import { test } from "bun:test";

import { checkLayout, sameSize } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import {
  browserHarness,
  expectElementFinding,
  expectPassed,
} from "./logical-target-support";

const withPage = browserHarness();

test("distinguishes identical descendants scoped within different containers", () =>
  withPage(
    '<section id="first"><button style="width:30px;height:20px">Open</button></section><section id="second"><button style="width:30px;height:20px">Open</button></section>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            firstAction: page
              .locator("#first")
              .getByRole("button", { name: "Open" }),
            secondAction: page
              .locator("#second")
              .getByRole("button", { name: "Open" }),
          },
        }),
        rules: [sameSize("firstAction", "secondAction")],
      });
      expectPassed(report);
    },
  ));

test("does not count matching descendants outside a locator's scope", () =>
  withPage(
    '<section id="scope"><span class="item" style="display:block;width:20px;height:20px"></span></section><span class="item" style="display:block;width:20px;height:20px"></span><div class="peer" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            scoped: page.locator("#scope").locator(".item"),
            peer: page.locator(".peer"),
          },
        }),
        rules: [sameSize("scoped", "peer")],
      });
      expectPassed(report);

      const unscoped = await checkLayout({
        adapter: playwright(page, {
          targets: {
            scoped: page.locator(".item"),
            peer: page.locator(".peer"),
          },
        }),
        rules: [sameSize("scoped", "peer")],
      });
      expectElementFinding(unscoped, {
        category: "element-resolution",
        code: "duplicate-element",
        operand: "subject",
        testId: "scoped",
        actual: { matchCount: 2 },
      });
    },
  ));
