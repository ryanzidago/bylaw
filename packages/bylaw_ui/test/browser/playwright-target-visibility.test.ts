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

/**
 * Issue: Visibility checks stop at an iframe document and ignore hidden frame
 * ancestors.
 * Why it matters: Bylaw can treat an element in a fully transparent embedded UI
 * as visible and evaluate layout rules against content users cannot see.
 */
test("reports a registered target hidden by its iframe", () =>
  withPage(
    '<iframe title="Hidden UI" style="opacity:0;border:0" srcdoc="<style>html,body{margin:0}</style><div class=&quot;target&quot; style=&quot;width:20px;height:20px&quot;></div>"></iframe><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            target: page
              .frameLocator('iframe[title="Hidden UI"]')
              .locator(".target"),
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
        actual: { hidden: true, width: 20, height: 20 },
      });
    },
  ));

/**
 * Issue: An iframe with visibility hidden does not make its registered targets
 * unavailable.
 * Why it matters: Layout rules can pass against embedded content that is not
 * rendered to the user.
 */
test("reports a registered target hidden by iframe visibility", () =>
  withPage(
    '<iframe title="Hidden UI" style="visibility:hidden;border:0" srcdoc="<style>html,body{margin:0}</style><div class=&quot;target&quot; style=&quot;width:20px;height:20px&quot;></div>"></iframe><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            target: page
              .frameLocator('iframe[title="Hidden UI"]')
              .locator(".target"),
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
        actual: { hidden: true, width: 20, height: 20 },
      });
    },
  ));
