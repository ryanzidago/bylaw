import { expect, test } from "bun:test";

import { checkLayout, width, type LayoutRule, type PixelRange } from "bylaw-ui";
import { fixtureAdapter, rect, visible } from "./support";

async function checkWidth(actualWidth: number, range: PixelRange) {
  return checkLayout({
    adapter: fixtureAdapter({
      target: visible("target", rect(100, -50, actualWidth, 37)),
    }),
    rules: [width("target", range)],
  });
}

async function expectWidthPass(actualWidth: number, range: PixelRange) {
  const report = await checkWidth(actualWidth, range);
  expect(report).toMatchObject({
    passed: true,
    rules: { total: 1, passed: 1, failed: 0, skipped: 0 },
    findings: [],
  });
}

async function expectWidthFailure(actualWidth: number, range: PixelRange) {
  const report = await checkWidth(actualWidth, range);
  expect(report).toMatchObject({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
  });
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "layout",
      relationship: "width",
      target: "target",
      expected: { range },
      actual: { widthPx: actualWidth },
    }),
  );
}

test("width accepts a target whose width equals the inclusive minimum", () =>
  expectWidthPass(10, { minPx: 10, maxPx: 20 }));

test("width accepts a target whose width equals the inclusive maximum", () =>
  expectWidthPass(20, { minPx: 10, maxPx: 20 }));

test("width accepts a target whose width falls between the minimum and maximum", () =>
  expectWidthPass(15, { minPx: 10, maxPx: 20 }));

test("width rejects a target whose width falls below the minimum", () =>
  expectWidthFailure(9.99, { minPx: 10, maxPx: 20 }));

test("width rejects a target whose width exceeds the maximum", () =>
  expectWidthFailure(20.01, { minPx: 10, maxPx: 20 }));

test("width accepts a target whose width equals an exact fixed range", () =>
  expectWidthPass(270, { minPx: 270, maxPx: 270 }));

test("width accepts a target above a minimum-only range", () =>
  expectWidthPass(10.25, { minPx: 10 }));

test("width rejects a target below a minimum-only range", () =>
  expectWidthFailure(9.999, { minPx: 10 }));

test("width accepts a target below a maximum-only range", () =>
  expectWidthPass(19.75, { maxPx: 20 }));

test("width rejects a target above a maximum-only range", () =>
  expectWidthFailure(20.001, { maxPx: 20 }));

test("width preserves fractional CSS-pixel measurements and bounds", async () => {
  await expectWidthPass(10.125, { minPx: 10.125, maxPx: 10.125 });
  await expectWidthFailure(10.125, { maxPx: 10.124 });
});

test("width ignores the target height and viewport-relative position", async () => {
  const rule = width("target", { minPx: 10, maxPx: 10 });
  const reports = await Promise.all(
    [rect(-999_999, 999_999, 10, 1), rect(999_999, -999_999, 10, 10_000)].map(
      (rectangle) =>
        checkLayout({
          adapter: fixtureAdapter({ target: visible("target", rectangle) }),
          rules: [rule as LayoutRule],
        }),
    ),
  );
  expect(reports.map(({ passed }) => passed)).toEqual([true, true]);
});
