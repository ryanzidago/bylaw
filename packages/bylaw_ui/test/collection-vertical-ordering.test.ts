import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  createAdapter,
  verticallyOrdered,
  type CollectionFinding,
  type LayoutReport,
  type PixelRange,
  type Rectangle,
} from "bylaw-ui";

async function checkRows(
  rectangles: Rectangle[],
  gap?: PixelRange,
): Promise<LayoutReport> {
  return checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 500, height: 500 },
        targets: [{
          target: "rows",
          matches: rectangles.map((rect) => ({ hidden: false, rect })),
        }],
      }),
    }),
    rules: [verticallyOrdered(collection("rows"), gap ? { gap } : undefined)],
  });
}

const ordered = [
  { x: 0, y: 0, width: 100, height: 10 },
  { x: 0, y: 20, width: 100, height: 10 },
  { x: 0, y: 40, width: 100, height: 10 },
];

test("passes when collection members are vertically ordered", async () => {
  expect((await checkRows(ordered)).passed).toBe(true);
});

test("passes when every adjacent gap is inside the allowed range", async () => {
  expect((await checkRows(ordered, { minPx: 9, maxPx: 11 })).passed).toBe(true);
});

test("passes when adjacent gaps equal the allowed range boundaries", async () => {
  const rows = [
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 0, y: 14, width: 10, height: 10 },
    { x: 0, y: 32, width: 10, height: 10 },
  ];
  expect((await checkRows(rows, { minPx: 4, maxPx: 8 })).passed).toBe(true);
});

test("passes with a minimum-only adjacent gap range", async () => {
  expect((await checkRows(ordered, { minPx: 10 })).passed).toBe(true);
});

test("passes with a maximum-only adjacent gap range", async () => {
  expect((await checkRows(ordered, { maxPx: 10 })).passed).toBe(true);
});

test("passes when adjacent members touch and zero gap is allowed", async () => {
  expect((await checkRows([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 0, y: 10, width: 10, height: 10 },
  ], { minPx: 0, maxPx: 0 })).passed).toBe(true);
});

test("passes vertical ordering when a collection contains one member", async () => {
  expect((await checkRows([ordered[0]!])).passed).toBe(true);
});

test("evaluates vertical ordering between adjacent collection members only", async () => {
  const report = await checkRows([
    { x: 0, y: 0, width: 10, height: 50 },
    { x: 0, y: 60, width: 10, height: 10 },
    { x: 0, y: 80, width: 10, height: 10 },
  ]);
  expect(report.passed).toBe(true);
  expect(report.findings).toEqual([]);
});

test("uses collection order instead of sorting members by coordinates", async () => {
  const report = await checkRows([
    { x: 0, y: 20, width: 10, height: 10 },
    { x: 0, y: 0, width: 10, height: 10 },
  ]);
  expect(report.findings[0]).toMatchObject({
    code: "collection-ordering-violation",
    subject: { target: "rows", collectionIndex: 0 },
    reference: { target: "rows", collectionIndex: 1 },
  });
});

test("fails when two adjacent collection members are out of vertical order", async () => {
  const report = await checkRows([
    ordered[0]!,
    { x: 0, y: 5, width: 10, height: 10 },
  ]);
  expect(report.rules.failed).toBe(1);
  expect(report.findings[0]).toMatchObject({
    code: "collection-ordering-violation",
  });
});

test("fails when an adjacent gap is smaller than the allowed minimum", async () => {
  const report = await checkRows([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 0, y: 14, width: 10, height: 10 },
  ], { minPx: 5 });
  expect(report.findings[0]).toMatchObject({
    code: "collection-gap-out-of-range",
    expected: { gap: { minPx: 5 } },
    actual: { gapPx: 4 },
  });
});

test("fails when an adjacent gap is larger than the allowed maximum", async () => {
  const report = await checkRows([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 0, y: 16, width: 10, height: 10 },
  ], { maxPx: 5 });
  expect(report.findings[0]).toMatchObject({
    code: "collection-gap-out-of-range",
    expected: { gap: { maxPx: 5 } },
    actual: { gapPx: 6 },
  });
});

test("distinguishes an out-of-order pair from an ordered pair with an invalid gap", async () => {
  const outOfOrder = await checkRows([
    { x: 0, y: 10, width: 10, height: 10 },
    { x: 0, y: 5, width: 10, height: 10 },
  ], { minPx: 2 });
  const badGap = await checkRows([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 0, y: 11, width: 10, height: 10 },
  ], { minPx: 2 });
  expect(outOfOrder.findings[0]).toMatchObject({
    code: "collection-ordering-violation",
  });
  expect(badGap.findings[0]).toMatchObject({
    code: "collection-gap-out-of-range",
  });
});

test("reports every adjacent pair whose vertical ordering fails", async () => {
  const report = await checkRows([
    { x: 0, y: 30, width: 10, height: 10 },
    { x: 0, y: 20, width: 10, height: 10 },
    { x: 0, y: 10, width: 10, height: 10 },
  ]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { subject: unknown; reference: unknown }
  >[];
  expect(findings.map((finding) => [
    finding.subject.collectionIndex,
    finding.reference.collectionIndex,
  ])).toEqual([[0, 1], [1, 2]]);
});

test("reports every adjacent pair whose gap is outside the allowed range", async () => {
  const report = await checkRows([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 0, y: 11, width: 10, height: 10 },
    { x: 0, y: 31, width: 10, height: 10 },
  ], { minPx: 2, maxPx: 5 });
  const findings = report.findings as Extract<
    CollectionFinding,
    { subject: unknown; reference: unknown }
  >[];
  expect(findings.map((finding) => [
    finding.subject.collectionIndex,
    finding.reference.collectionIndex,
  ])).toEqual([[0, 1], [1, 2]]);
});

test("preserves fractional gaps between collection members", async () => {
  const report = await checkRows([
    { x: 0, y: 0.25, width: 10, height: 10.25 },
    { x: 0, y: 11.75, width: 10, height: 10 },
  ], { minPx: 1.5, maxPx: 1.5 });
  expect(report.passed).toBe(true);
});
