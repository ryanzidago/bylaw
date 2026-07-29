import { test } from "bun:test";

import { checkLayout, sameSize } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import {
  browserHarness,
  expectElementFinding,
  expectPassed,
} from "./logical-target-support";

const withPage = browserHarness();

test("continues resolving exact data-testid values without a registry", () =>
  withPage(
    '<div data-testid="subject" style="width:20px;height:20px"></div><div data-testid="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      expectPassed(
        await checkLayout({
          adapter: playwright(page),
          rules: [sameSize("subject", "reference")],
        }),
      );
    },
  ));

test("uses a registered target before data-testid fallback for the same name", () =>
  withPage(
    '<div data-testid="target" style="width:10px;height:10px"></div><div class="registered" style="width:30px;height:30px"></div><div data-testid="reference" style="width:30px;height:30px"></div>',
    async (page) => {
      expectPassed(
        await checkLayout({
          adapter: playwright(page, {
            targets: { target: page.locator(".registered") },
          }),
          rules: [sameSize("target", "reference")],
        }),
      );
    },
  ));

test("does not fall back to data-testid when a registered target matches no elements", () =>
  withPage(
    '<div data-testid="target" style="width:20px;height:20px"></div><div data-testid="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { target: page.locator(".missing") },
        }),
        rules: [sameSize("target", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "missing-element",
        operand: "subject",
        testId: "target",
        actual: { matchCount: 0 },
      });
    },
  ));

test("does not fall back to data-testid when a registered target matches multiple elements", () =>
  withPage(
    '<div data-testid="target" style="width:20px;height:20px"></div><div class="registered"></div><div class="registered"></div><div data-testid="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { target: page.locator(".registered") },
        }),
        rules: [sameSize("target", "reference")],
      });
      expectElementFinding(report, {
        category: "element-resolution",
        code: "duplicate-element",
        operand: "subject",
        testId: "target",
        actual: { matchCount: 2 },
      });
    },
  ));

test("falls back to exact data-testid addressing for an unregistered name", () =>
  withPage(
    '<div data-testid="unregistered" style="width:25px;height:15px"></div><div class="peer" style="width:25px;height:15px"></div>',
    async (page) => {
      expectPassed(
        await checkLayout({
          adapter: playwright(page, {
            targets: { peer: page.locator(".peer") },
          }),
          rules: [sameSize("unregistered", "peer")],
        }),
      );
    },
  ));

test("supports registered and fallback targets in the same check", () =>
  withPage(
    '<div class="registered" style="width:25px;height:15px"></div><div data-testid="fallback" style="width:25px;height:15px"></div>',
    async (page) => {
      expectPassed(
        await checkLayout({
          adapter: playwright(page, {
            targets: { registered: page.locator(".registered") },
          }),
          rules: [sameSize("registered", "fallback")],
        }),
      );
    },
  ));
