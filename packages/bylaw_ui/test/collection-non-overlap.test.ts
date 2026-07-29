import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  createAdapter,
  pairwiseNotOverlap,
  type CollectionFinding,
  type LayoutReport,
  type Rectangle,
} from "bylaw-ui";

async function checkRectangles(rectangles: Rectangle[]): Promise<LayoutReport> {
  return checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 500, height: 500 },
        targets: [{
          target: "controls",
          matches: rectangles.map((rect) => ({ hidden: false, rect })),
        }],
      }),
    }),
    rules: [pairwiseNotOverlap(collection("controls"))],
  });
}

test("passes when no collection members overlap", async () => {
  expect((await checkRectangles([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 20, y: 20, width: 10, height: 10 },
  ])).passed).toBe(true);
});

test("passes when collection members only touch at their boundaries", async () => {
  expect((await checkRectangles([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 10, y: 0, width: 10, height: 10 },
    { x: 20, y: 10, width: 10, height: 10 },
  ])).passed).toBe(true);
});

test("passes when collection members intersect horizontally but are vertically separate", async () => {
  expect((await checkRectangles([
    { x: 0, y: 0, width: 20, height: 10 },
    { x: 5, y: 20, width: 20, height: 10 },
  ])).passed).toBe(true);
});

test("passes when collection members intersect vertically but are horizontally separate", async () => {
  expect((await checkRectangles([
    { x: 0, y: 0, width: 10, height: 20 },
    { x: 20, y: 5, width: 10, height: 20 },
  ])).passed).toBe(true);
});

test("passes pairwise non-overlap when a collection contains one member", async () => {
  expect((await checkRectangles([
    { x: 0, y: 0, width: 10, height: 10 },
  ])).passed).toBe(true);
});

test("fails when two adjacent collection members overlap", async () => {
  const report = await checkRectangles([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 5, y: 5, width: 10, height: 10 },
  ]);
  expect(report.findings[0]).toMatchObject({
    code: "collection-overlap",
    subject: { target: "controls", collectionIndex: 0 },
    reference: { target: "controls", collectionIndex: 1 },
  });
});

test("fails when two non-adjacent collection members overlap", async () => {
  const report = await checkRectangles([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 20, y: 20, width: 10, height: 10 },
    { x: 5, y: 5, width: 10, height: 10 },
  ]);
  expect(report.findings).toHaveLength(1);
  expect(report.findings[0]).toMatchObject({
    subject: { collectionIndex: 0 },
    reference: { collectionIndex: 2 },
  });
});

test("fails when one collection member is nested inside another", async () => {
  const report = await checkRectangles([
    { x: 0, y: 0, width: 20, height: 20 },
    { x: 5, y: 5, width: 5, height: 5 },
  ]);
  expect(report.findings[0]).toMatchObject({
    actual: { horizontalPx: 5, verticalPx: 5 },
  });
});

test("fails when two collection members have identical rectangles", async () => {
  const rectangle = { x: 5, y: 5, width: 10, height: 10 };
  const report = await checkRectangles([rectangle, rectangle]);
  expect(report.findings[0]).toMatchObject({
    actual: { horizontalPx: 10, verticalPx: 10 },
  });
});

test("reports every overlapping pair in the collection", async () => {
  const report = await checkRectangles([
    { x: 0, y: 0, width: 20, height: 20 },
    { x: 5, y: 5, width: 20, height: 20 },
    { x: 10, y: 10, width: 20, height: 20 },
  ]);
  const findings = report.findings as Extract<
    CollectionFinding,
    { subject: unknown; reference: unknown }
  >[];
  expect(findings.map((finding) => [
    finding.subject.collectionIndex,
    finding.reference.collectionIndex,
  ])).toEqual([[0, 1], [0, 2], [1, 2]]);
});

test("does not report the same overlapping pair twice", async () => {
  const report = await checkRectangles([
    { x: 0, y: 0, width: 10, height: 10 },
    { x: 5, y: 5, width: 10, height: 10 },
  ]);
  expect(report.findings).toHaveLength(1);
});
