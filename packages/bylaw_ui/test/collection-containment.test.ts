import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  createAdapter,
  everyInside,
  type CollectionFinding,
  type LayoutReport,
  type Rectangle,
} from "bylaw-ui";

const container = { x: 0, y: 0, width: 100, height: 100 };

function resolved(target: string, rect: Rectangle) {
  return { target, matchCount: 1 as const, hidden: false, rect };
}

async function checkMembers(
  rectangles: Rectangle[],
  options?: { tolerancePx?: number },
  containerResult: object = resolved("container", container),
): Promise<LayoutReport> {
  return checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 500, height: 500 },
        targets: [
          {
            target: "cards",
            matches: rectangles.map((rect) => ({ hidden: false, rect })),
          },
          containerResult,
        ],
      }),
    }),
    rules: [everyInside(collection("cards"), "container", options)],
  });
}

test("passes when every collection member is contained by the target element", async () => {
  const report = await checkMembers([
    { x: 10, y: 10, width: 20, height: 20 },
    { x: 40, y: 40, width: 20, height: 20 },
  ]);
  expect(report.passed).toBe(true);
  expect(report.findings).toEqual([]);
});

test("passes when collection members touch the target boundaries", async () => {
  expect(
    (
      await checkMembers([
        { x: 0, y: 0, width: 20, height: 20 },
        { x: 80, y: 80, width: 20, height: 20 },
      ])
    ).passed,
  ).toBe(true);
});

test("accepts collection member overflow within the configured tolerance", async () => {
  expect(
    (
      await checkMembers([{ x: -0.5, y: 0, width: 100.5, height: 100 }], {
        tolerancePx: 1,
      })
    ).passed,
  ).toBe(true);
});

test("accepts collection member overflow equal to the configured tolerance", async () => {
  expect(
    (
      await checkMembers([{ x: -1, y: -1, width: 102, height: 102 }], {
        tolerancePx: 1,
      })
    ).passed,
  ).toBe(true);
});

test("fails when collection member overflow exceeds the configured tolerance", async () => {
  const report = await checkMembers(
    [{ x: -1.01, y: 0, width: 101.01, height: 100 }],
    { tolerancePx: 1 },
  );
  expect(report.findings[0]).toMatchObject({
    code: "collection-containment-overflow",
    collectionIndex: 0,
    actual: { leftPx: 1.01 },
  });
});

test("fails when the first collection member overflows the target element", async () => {
  const report = await checkMembers([
    { x: -1, y: 0, width: 20, height: 20 },
    { x: 20, y: 20, width: 20, height: 20 },
  ]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([0]);
});

test("fails when a middle collection member overflows the target element", async () => {
  const report = await checkMembers([
    { x: 0, y: 0, width: 20, height: 20 },
    { x: 90, y: 20, width: 20, height: 20 },
    { x: 40, y: 40, width: 20, height: 20 },
  ]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([1]);
});

test("fails when the last collection member overflows the target element", async () => {
  const report = await checkMembers([
    { x: 0, y: 0, width: 20, height: 20 },
    { x: 20, y: 20, width: 20, height: 20 },
    { x: 40, y: 90, width: 20, height: 20 },
  ]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([2]);
});

test("reports every collection member that overflows the target element", async () => {
  const report = await checkMembers([
    { x: -1, y: 0, width: 20, height: 20 },
    { x: 90, y: 20, width: 20, height: 20 },
    { x: 40, y: 90, width: 20, height: 20 },
  ]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([0, 1, 2]);
});

test("reports collection member overflow across each target boundary", async () => {
  const report = await checkMembers([
    { x: -2, y: -3, width: 106, height: 108 },
  ]);
  expect(report.findings[0]).toMatchObject({
    actual: { leftPx: 2, rightPx: 4, topPx: 3, bottomPx: 5 },
  });
});

test("requires every collection member to intersect the target even with tolerance", async () => {
  const report = await checkMembers(
    [{ x: 101, y: 20, width: 10, height: 10 }],
    { tolerancePx: 20 },
  );
  expect(report.findings[0]).toMatchObject({
    code: "collection-containment-overflow",
    expected: { tolerancePx: 20, positiveIntersection: true },
    actual: { horizontalPx: 0 },
  });
});

test("does not evaluate containment when the singular target is missing", async () => {
  const report = await checkMembers(
    [{ x: -1, y: 0, width: 20, height: 20 }],
    undefined,
    { target: "container", matchCount: 0 },
  );
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 0, skipped: 1 });
  expect(report.findings).toEqual([
    expect.objectContaining({
      category: "element-resolution",
      code: "missing-element",
      target: "container",
    }),
  ]);
});

test("does not evaluate containment when the singular target has duplicate matches", async () => {
  const report = await checkMembers(
    [{ x: -1, y: 0, width: 20, height: 20 }],
    undefined,
    { target: "container", matchCount: 2 },
  );
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 0, skipped: 1 });
  expect(report.findings).toEqual([
    expect.objectContaining({
      category: "element-resolution",
      code: "duplicate-element",
      target: "container",
    }),
  ]);
});
