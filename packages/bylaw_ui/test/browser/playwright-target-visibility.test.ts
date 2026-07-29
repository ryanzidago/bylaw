import { test } from "bun:test";

import { checkLayout, sameSize } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import {
  browserHarness,
  expectElementFinding,
} from "./logical-target-support";

const withPage = browserHarness();

test("reports a registered target that is hidden", () =>
  withPage(
    '<div class="target" hidden style="width:20px;height:20px"></div><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            target: page.locator(".target"),
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("target", "reference")],
      });
      expectElementFinding(report, {
        category: "element-visibility",
        code: "hidden-element",
        operand: "subject",
        testId: "target",
        actual: { hidden: true, width: 0, height: 0 },
      });
    },
  ));

test("reports a registered target that has zero size", () =>
  withPage(
    '<div class="target" style="width:0;height:20px"></div><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            target: page.locator(".target"),
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("target", "reference")],
      });
      expectElementFinding(report, {
        category: "element-visibility",
        code: "zero-size-element",
        operand: "subject",
        testId: "target",
        actual: { hidden: false, width: 0, height: 20 },
      });
    },
  ));
