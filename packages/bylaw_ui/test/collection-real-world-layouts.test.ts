import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  createAdapter,
  equalWidths,
  everyInside,
  pairwiseNotOverlap,
  sameWidth,
  verticallyOrdered,
  type LayoutRule,
} from "bylaw-ui";

const rect = (x: number, y: number, width: number, height: number) => ({
  x,
  y,
  width,
  height,
});

function repeated(target: string, rectangles: ReturnType<typeof rect>[]) {
  return {
    target,
    matches: rectangles.map((rectangle) => ({
      hidden: false,
      rect: rectangle,
    })),
  };
}

function singular(target: string, rectangle: ReturnType<typeof rect>) {
  return { target, matchCount: 1 as const, hidden: false, rect: rectangle };
}

function check(rule: LayoutRule, targets: object[]) {
  return checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 1280, height: 720 },
        targets,
      }),
    }),
    rules: [rule],
  });
}

const filesContainer = singular(
  "files-changed",
  rect(100, 50, 800, 600),
);
const validCards = repeated("file-card", [
  rect(120, 80, 760, 120),
  rect(120, 220, 760, 120),
  rect(120, 360, 760, 120),
]);

test("validates that every file card is contained by the files changed container", async () => {
  const report = await check(
    everyInside(collection("file-card"), "files-changed"),
    [validCards, filesContainer],
  );
  expect(report.passed).toBe(true);
});

test("reports the file card that overflows the files changed container", async () => {
  const cards = repeated("file-card", [
    rect(120, 80, 760, 120),
    rect(120, 220, 800, 120),
    rect(120, 360, 760, 120),
  ]);
  const report = await check(
    everyInside(collection("file-card"), "files-changed"),
    [cards, filesContainer],
  );
  expect(report.findings[0]).toMatchObject({
    target: "file-card",
    collectionIndex: 1,
    code: "collection-containment-overflow",
  });
});

test("validates equal widths across every file card", async () => {
  const report = await check(
    equalWidths(collection("file-card")),
    [validCards],
  );
  expect(report.passed).toBe(true);
});

test("reports the file card whose width differs from the other file cards", async () => {
  const cards = repeated("file-card", [
    rect(120, 80, 760, 120),
    rect(120, 220, 740, 120),
    rect(120, 360, 760, 120),
  ]);
  const report = await check(equalWidths(collection("file-card")), [cards]);
  expect(report.findings[0]).toMatchObject({
    target: "file-card",
    collectionIndex: 1,
    actual: { referenceWidthPx: 760, memberWidthPx: 740 },
  });
});

test("validates vertical ordering and gaps across every hunk header", async () => {
  const headers = repeated("hunk-header", [
    rect(100, 100, 800, 32),
    rect(100, 148, 800, 32),
    rect(100, 196, 800, 32),
  ]);
  const report = await check(
    verticallyOrdered(collection("hunk-header"), {
      gap: { minPx: 16, maxPx: 16 },
    }),
    [headers],
  );
  expect(report.passed).toBe(true);
});

test("reports the hunk header pair whose vertical gap is invalid", async () => {
  const headers = repeated("hunk-header", [
    rect(100, 100, 800, 32),
    rect(100, 148, 800, 32),
    rect(100, 200, 800, 32),
  ]);
  const report = await check(
    verticallyOrdered(collection("hunk-header"), {
      gap: { minPx: 16, maxPx: 16 },
    }),
    [headers],
  );
  expect(report.findings[0]).toMatchObject({
    subject: { target: "hunk-header", collectionIndex: 1 },
    reference: { target: "hunk-header", collectionIndex: 2 },
    actual: { gapPx: 20 },
  });
});

test("validates that unified diff rows do not overlap", async () => {
  const rows = repeated("unified-row", [
    rect(100, 100, 800, 24),
    rect(100, 124, 800, 24),
    rect(100, 148, 800, 24),
  ]);
  expect((await check(
    pairwiseNotOverlap(collection("unified-row")),
    [rows],
  )).passed).toBe(true);
});

test("reports both unified diff rows that overlap", async () => {
  const rows = repeated("unified-row", [
    rect(100, 100, 800, 24),
    rect(100, 120, 800, 24),
  ]);
  const report = await check(
    pairwiseNotOverlap(collection("unified-row")),
    [rows],
  );
  expect(report.findings[0]).toMatchObject({
    subject: { target: "unified-row", collectionIndex: 0 },
    reference: { target: "unified-row", collectionIndex: 1 },
  });
});

test("validates pairwise non-overlap across repeated toolbar controls", async () => {
  const controls = repeated("toolbar-control", [
    rect(20, 20, 32, 32),
    rect(60, 20, 32, 32),
    rect(100, 20, 32, 32),
  ]);
  expect((await check(
    pairwiseNotOverlap(collection("toolbar-control")),
    [controls],
  )).passed).toBe(true);
});

test("rejects a singular toolbar target when multiple controls match", async () => {
  const report = await check(
    sameWidth("toolbar-control", "reference-control"),
    [
      { target: "toolbar-control", matchCount: 3 },
      singular("reference-control", rect(0, 0, 32, 32)),
    ],
  );
  expect(report.findings[0]).toMatchObject({
    code: "duplicate-element",
    target: "toolbar-control",
    actual: { matchCount: 3 },
  });
});
