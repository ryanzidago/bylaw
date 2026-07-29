import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  createAdapter,
  equalWidths,
  everyInside,
  pairwiseNotOverlap,
  verticallyOrdered,
  type CollectionFinding,
  type LayoutRule,
} from "bylaw-ui";

const rect = (x: number, y: number, width = 10, height = 10) => ({
  x,
  y,
  width,
  height,
});

function cards(rectangles: ReturnType<typeof rect>[]) {
  return {
    target: "cards",
    matches: rectangles.map((rectangle) => ({
      hidden: false,
      rect: rectangle,
    })),
  };
}

function container(rectangle = rect(0, 0, 100, 100)) {
  return {
    target: "container",
    matchCount: 1 as const,
    hidden: false,
    rect: rectangle,
  };
}

function reportFor(rules: LayoutRule[], targets: object[]) {
  return checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 500, height: 500 },
        targets,
      }),
    }),
    rules,
  });
}

test("an individual collection failure identifies its collection index", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 10), rect(0, 20, 11)])],
  );
  expect(report.findings[0]).toMatchObject({ collectionIndex: 1 });
});

test("collection indexes are zero-based and follow adapter element order", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 20), rect(0, 20, 10), rect(0, 40, 11)])],
  );
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map(({ collectionIndex }) => collectionIndex)).toEqual([
    1,
    2,
  ]);
});

test("an individual collection failure identifies its target element", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 10), rect(0, 20, 11)])],
  );
  expect(report.findings[0]).toMatchObject({ target: "cards" });
});

test("a pairwise collection failure identifies both collection indexes", async () => {
  const report = await reportFor(
    [pairwiseNotOverlap(collection("cards"))],
    [cards([rect(0, 0), rect(5, 5)])],
  );
  expect(report.findings[0]).toMatchObject({
    subject: { collectionIndex: 0 },
    reference: { collectionIndex: 1 },
  });
});

test("a pairwise collection failure identifies both target elements", async () => {
  const report = await reportFor(
    [pairwiseNotOverlap(collection("cards"))],
    [cards([rect(0, 0), rect(5, 5)])],
  );
  expect(report.findings[0]).toMatchObject({
    subject: { target: "cards" },
    reference: { target: "cards" },
  });
});

test("an empty collection finding reports expected and actual member counts", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([])],
  );
  expect(report.findings[0]).toMatchObject({
    code: "empty-collection",
    expected: { minMatchCount: 1 },
    actual: { matchCount: 0 },
  });
});

test("an individual collection finding exposes a stable category code and relationship", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 10), rect(0, 20, 11)])],
  );
  expect(report.findings[0]).toMatchObject({
    category: "layout",
    code: "collection-width-mismatch",
    relationship: "equalWidths",
  });
});

test("a containment finding includes member and container rectangles with directional overflow", async () => {
  const report = await reportFor(
    [everyInside(collection("cards"), "container")],
    [cards([rect(-2, -3, 106, 108)]), container()],
  );
  expect(report.findings[0]).toMatchObject({
    actual: {
      memberRect: rect(-2, -3, 106, 108),
      containerRect: rect(0, 0, 100, 100),
      leftPx: 2,
      rightPx: 4,
      topPx: 3,
      bottomPx: 5,
    },
  });
});

test("an equal-width finding includes compared members and measured width difference", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 10), rect(0, 20, 12)])],
  );
  expect(report.findings[0]).toMatchObject({
    actual: {
      referenceRect: rect(0, 0, 10),
      memberRect: rect(0, 20, 12),
      differencePx: 2,
    },
  });
});

test("a vertical-ordering finding includes adjacent member rectangles and signed gap", async () => {
  const report = await reportFor(
    [verticallyOrdered(collection("cards"))],
    [cards([rect(0, 20), rect(0, 5)])],
  );
  expect(report.findings[0]).toMatchObject({
    actual: {
      subjectRect: rect(0, 20),
      referenceRect: rect(0, 5),
      gapPx: -25,
    },
  });
});

test("a pairwise non-overlap finding includes both member rectangles and overlap depths", async () => {
  const report = await reportFor(
    [pairwiseNotOverlap(collection("cards"))],
    [cards([rect(0, 0), rect(5, 4)])],
  );
  expect(report.findings[0]).toMatchObject({
    actual: {
      subjectRect: rect(0, 0),
      referenceRect: rect(5, 4),
      horizontalPx: 5,
      verticalPx: 6,
    },
  });
});

test("collection reports remain JSON-serializable without adapter browser or DOM objects", async () => {
  const report = await reportFor(
    [pairwiseNotOverlap(collection("cards"))],
    [cards([rect(0, 0), rect(5, 5)])],
  );
  expect(JSON.parse(JSON.stringify(report))).toEqual(report);
  expect(JSON.stringify(report)).not.toContain("adapter");
});

test("collection findings follow rule order", async () => {
  const report = await reportFor(
    [
      equalWidths(collection("cards")),
      pairwiseNotOverlap(collection("cards")),
    ],
    [cards([rect(0, 0, 10), rect(5, 5, 11)])],
  );
  expect(report.findings.map(({ ruleIndex }) => ruleIndex)).toEqual([0, 1]);
});

test("individual collection findings follow collection order", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 20), rect(0, 20, 10), rect(0, 40, 11)])],
  );
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map(({ collectionIndex }) => collectionIndex)).toEqual([
    1,
    2,
  ]);
});

test("pairwise collection findings follow deterministic pair order", async () => {
  const report = await reportFor(
    [pairwiseNotOverlap(collection("cards"))],
    [cards([rect(0, 0, 20, 20), rect(2, 2, 20, 20), rect(4, 4, 20, 20)])],
  );
  const findings = report.findings as Extract<
    CollectionFinding,
    { subject: unknown; reference: unknown }
  >[];
  expect(findings.map(({ subject, reference }) => [
    subject.collectionIndex,
    reference.collectionIndex,
  ])).toEqual([[0, 1], [0, 2], [1, 2]]);
});

test("pairwise collection findings use ascending lexicographic index order", async () => {
  const report = await reportFor(
    [pairwiseNotOverlap(collection("cards"))],
    [cards([
      rect(0, 0, 20, 20),
      rect(2, 2, 20, 20),
      rect(4, 4, 20, 20),
      rect(6, 6, 20, 20),
    ])],
  );
  const findings = report.findings as Extract<
    CollectionFinding,
    { subject: unknown; reference: unknown }
  >[];
  const pairs = findings.map(({ subject, reference }) => [
    subject.collectionIndex,
    reference.collectionIndex,
  ]);
  expect(pairs).toEqual([
    [0, 1],
    [0, 2],
    [0, 3],
    [1, 2],
    [1, 3],
    [2, 3],
  ]);
});

test("repeated evaluation produces findings in the same order", async () => {
  const rules = [pairwiseNotOverlap(collection("cards"))];
  const targets = [
    cards([rect(0, 0, 20, 20), rect(2, 2, 20, 20), rect(4, 4, 20, 20)]),
  ];
  const first = await reportFor(rules, targets);
  const second = await reportFor(rules, targets);
  expect(second.findings).toEqual(first.findings);
});

test("a failed collection rule contributes one failed rule to the report summary", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 10), rect(0, 20, 11)])],
  );
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 1, skipped: 0 });
});

test("a passing collection rule contributes one passed rule to the report summary", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0), rect(0, 20)])],
  );
  expect(report.rules).toEqual({ total: 1, passed: 1, failed: 0, skipped: 0 });
});

test("an unresolved collection rule contributes one skipped rule to the report summary", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([])],
  );
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 0, skipped: 1 });
});

test("several findings from one collection rule count that rule only once", async () => {
  const report = await reportFor(
    [equalWidths(collection("cards"))],
    [cards([rect(0, 0, 20), rect(0, 20, 10), rect(0, 40, 11)])],
  );
  expect(report.findings).toHaveLength(2);
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 1, skipped: 0 });
});

test("mixed collection rules produce accurate passed failed and skipped counts", async () => {
  const report = await reportFor(
    [
      equalWidths(collection("cards")),
      pairwiseNotOverlap(collection("cards")),
      equalWidths(collection("empty")),
    ],
    [
      cards([rect(0, 0, 10), rect(0, 20, 11)]),
      { target: "empty", matches: [] },
    ],
  );
  expect(report.rules).toEqual({ total: 3, passed: 1, failed: 1, skipped: 1 });
});
