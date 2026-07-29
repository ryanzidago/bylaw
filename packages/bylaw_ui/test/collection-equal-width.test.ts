import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  createAdapter,
  equalWidths,
  type CollectionFinding,
  type LayoutReport,
} from "bylaw-ui";

function member(width: number, index: number) {
  return {
    hidden: false,
    rect: { x: 0, y: index * 20, width, height: 10 },
  };
}

async function checkWidths(
  widths: number[],
  options?: { tolerancePx?: number },
): Promise<LayoutReport> {
  return checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 500, height: 500 },
        targets: [
          {
            target: "cards",
            matches: widths.map(member),
          },
        ],
      }),
    }),
    rules: [equalWidths(collection("cards"), options)],
  });
}

test("passes when every collection member has the same width", async () => {
  const report = await checkWidths([100, 100, 100]);
  expect(report).toEqual({
    passed: true,
    rules: { total: 1, passed: 1, failed: 0, skipped: 0 },
    findings: [],
  });
});

test("passes the equal-width check when a collection contains one member", async () => {
  expect((await checkWidths([100])).passed).toBe(true);
});

test("fails when the two members of a collection have different widths", async () => {
  const report = await checkWidths([100, 101]);
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 1, skipped: 0 });
  expect(report.findings).toHaveLength(1);
  expect(report.findings[0]).toMatchObject({
    category: "layout",
    code: "collection-width-mismatch",
    target: "cards",
    collectionIndex: 1,
  });
});

test("accepts width differences within the configured tolerance", async () => {
  expect((await checkWidths([100, 100.9], { tolerancePx: 1 })).passed).toBe(
    true,
  );
});

test("accepts width differences equal to the configured tolerance", async () => {
  expect((await checkWidths([100, 101], { tolerancePx: 1 })).passed).toBe(true);
});

test("fails when a width difference exceeds the configured tolerance", async () => {
  const report = await checkWidths([100, 101.01], { tolerancePx: 1 });
  expect(report.findings[0]).toMatchObject({
    code: "collection-width-mismatch",
    expected: { tolerancePx: 1 },
    actual: {
      referenceWidthPx: 100,
      memberWidthPx: 101.01,
      differencePx: 1.01,
    },
  });
});

test("fails when the first collection member has a different width", async () => {
  const report = await checkWidths([101, 100, 100]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([1, 2]);
});

test("fails when a middle collection member has a different width", async () => {
  const report = await checkWidths([100, 101, 100]);
  expect(report.findings).toHaveLength(1);
  expect(report.findings[0]).toMatchObject({ collectionIndex: 1 });
});

test("fails when the last collection member has a different width", async () => {
  const report = await checkWidths([100, 100, 101]);
  expect(report.findings).toHaveLength(1);
  expect(report.findings[0]).toMatchObject({ collectionIndex: 2 });
});

test("reports every collection member whose width violates the collection contract", async () => {
  const report = await checkWidths([100, 101, 102, 100]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([1, 2]);
});

test("compares equal widths against the first collection member as a deterministic reference", async () => {
  const report = await checkWidths([101, 100, 100]);
  expect(report.findings).toEqual([
    expect.objectContaining({
      collectionIndex: 1,
      actual: expect.objectContaining({ referenceWidthPx: 101 }),
    }),
    expect.objectContaining({
      collectionIndex: 2,
      actual: expect.objectContaining({ referenceWidthPx: 101 }),
    }),
  ]);
});

test("preserves fractional widths when comparing collection members", async () => {
  const report = await checkWidths([100.25, 100.75]);
  expect(report.findings[0]).toMatchObject({
    actual: {
      referenceWidthPx: 100.25,
      memberWidthPx: 100.75,
      differencePx: 0.5,
    },
  });
});
