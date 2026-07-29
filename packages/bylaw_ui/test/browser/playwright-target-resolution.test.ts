import { expect, test } from "bun:test";

import { checkLayout, sameSize } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import {
  browserHarness,
  expectElementFinding,
  expectPassed,
} from "./logical-target-support";

const withPage = browserHarness();

test("reports a registered target that matches no elements", () =>
  withPage(
    '<div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            absent: page.locator(".absent"),
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("absent", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "missing-element",
        operand: "subject",
        testId: "absent",
        actual: { matchCount: 0 },
      });
    },
  ));

test("reports a registered target that matches multiple elements", () =>
  withPage(
    '<div class="candidate"></div><div class="candidate"></div><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            ambiguous: page.locator(".candidate"),
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("ambiguous", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "duplicate-element",
        operand: "subject",
        testId: "ambiguous",
        actual: { matchCount: 2 },
      });
    },
  ));

test("does not choose the first match for an ambiguous registered target", () =>
  withPage(
    '<div class="candidate" style="width:20px;height:20px"></div><div class="candidate" style="width:40px;height:40px"></div><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            ambiguous: page.locator(".candidate"),
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("ambiguous", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "duplicate-element",
        operand: "subject",
        testId: "ambiguous",
        actual: { matchCount: 2 },
      });
      expect(report.findings.some(({ category }) => category === "layout")).toBe(
        false,
      );
    },
  ));

test("identifies unresolved registered targets by logical name", () =>
  withPage(
    '<div data-testid="dom-name" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            "logical missing target": page.locator(".not-present"),
            reference: page.locator('[data-testid="dom-name"]'),
          },
        }),
        rules: [sameSize("logical missing target", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "missing-element",
        operand: "subject",
        testId: "logical missing target",
        actual: { matchCount: 0 },
      });
    },
  ));

test("does not resolve registered targets that are not referenced by any rule", () =>
  withPage(
    '<div class="subject" style="width:20px;height:20px"></div><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      let calls = 0;
      const unused = {
        elementHandles: async () => {
          calls += 1;
          throw new Error("unused target must not resolve");
        },
      };
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            subject: page.locator(".subject"),
            reference: page.locator(".reference"),
            unused: unused as never,
          },
        }),
        rules: [sameSize("subject", "reference")],
      });
      expectPassed(report);
      expect(calls).toBe(0);
    },
  ));
