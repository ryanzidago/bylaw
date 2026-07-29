import { expect, test } from "bun:test";

import { checkLayout, height, type PixelRange } from "bylaw-ui";
import { fixtureAdapter, rect, visible } from "./support";

async function checkHeight(actualHeight: number, range: PixelRange) {
  return checkLayout({
    adapter: fixtureAdapter({
      target: visible("target", rect(100, -50, 37, actualHeight)),
    }),
    rules: [height("target", range)],
  });
}

async function expectHeightPass(actualHeight: number, range: PixelRange) {
  const report = await checkHeight(actualHeight, range);
  expect(report).toMatchObject({
    passed: true,
    rules: { total: 1, passed: 1, failed: 0, skipped: 0 },
    findings: [],
  });
}

async function expectHeightFailure(actualHeight: number, range: PixelRange) {
  const report = await checkHeight(actualHeight, range);
  expect(report).toMatchObject({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
  });
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "layout",
      relationship: "height",
      target: "target",
      expected: { range },
      actual: { heightPx: actualHeight },
    }),
  );
}

test("height accepts a target whose height equals the inclusive minimum", () =>
  expectHeightPass(10, { minPx: 10, maxPx: 20 }));

test("height accepts a target whose height equals the inclusive maximum", () =>
  expectHeightPass(20, { minPx: 10, maxPx: 20 }));

test("height accepts a target whose height falls between the minimum and maximum", () =>
  expectHeightPass(15, { minPx: 10, maxPx: 20 }));

test("height rejects a target whose height falls below the minimum", () =>
  expectHeightFailure(9.99, { minPx: 10, maxPx: 20 }));

test("height rejects a target whose height exceeds the maximum", () =>
  expectHeightFailure(20.01, { minPx: 10, maxPx: 20 }));

test("height accepts a target whose height equals an exact fixed range", () =>
  expectHeightPass(48, { minPx: 48, maxPx: 48 }));

test("height accepts a target above a minimum-only range", () =>
  expectHeightPass(10.25, { minPx: 10 }));

test("height rejects a target below a minimum-only range", () =>
  expectHeightFailure(9.999, { minPx: 10 }));

test("height accepts a target below a maximum-only range", () =>
  expectHeightPass(19.75, { maxPx: 20 }));

test("height rejects a target above a maximum-only range", () =>
  expectHeightFailure(20.001, { maxPx: 20 }));

test("height preserves fractional CSS-pixel measurements and bounds", async () => {
  await expectHeightPass(10.125, { minPx: 10.125, maxPx: 10.125 });
  await expectHeightFailure(10.125, { maxPx: 10.124 });
});

test("height ignores the target width and viewport-relative position", async () => {
  const rule = height("target", { minPx: 10, maxPx: 10 });
  const reports = await Promise.all(
    [rect(-999_999, 999_999, 1, 10), rect(999_999, -999_999, 10_000, 10)].map(
      (rectangle) =>
        checkLayout({
          adapter: fixtureAdapter({ target: visible("target", rectangle) }),
          rules: [rule],
        }),
    ),
  );
  expect(reports.map(({ passed }) => passed)).toEqual([true, true]);
});
