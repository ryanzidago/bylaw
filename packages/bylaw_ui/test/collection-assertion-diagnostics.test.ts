import { expect, test } from "bun:test";

import {
  assertLayout,
  checkLayout,
  collection,
  createAdapter,
  equalWidths,
  LayoutAssertionError,
  pairwiseNotOverlap,
  type LayoutRule,
} from "bylaw-ui";

const rect = (x: number, y: number, width = 10, height = 10) => ({
  x,
  y,
  width,
  height,
});

async function failingReport(
  rule: LayoutRule,
  rectangles: ReturnType<typeof rect>[],
) {
  return checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [
          {
            target: "cards",
            matches: rectangles.map((rectangle) => ({
              hidden: false,
              rect: rectangle,
            })),
          },
        ],
      }),
    }),
    rules: [rule],
  });
}

function assertionError(report: Awaited<ReturnType<typeof failingReport>>) {
  try {
    assertLayout(report);
    throw new Error("expected assertLayout to throw");
  } catch (error) {
    expect(error).toBeInstanceOf(LayoutAssertionError);
    return error as LayoutAssertionError;
  }
}

test("an individual collection assertion diagnostic includes its index and target element", async () => {
  const report = await failingReport(equalWidths(collection("cards")), [
    rect(0, 0, 10),
    rect(0, 20, 11),
  ]);
  expect(assertionError(report).message).toContain('target "cards" member [1]');
});

test("a pairwise collection assertion diagnostic includes both indexes and target elements", async () => {
  const report = await failingReport(pairwiseNotOverlap(collection("cards")), [
    rect(0, 0),
    rect(5, 5),
  ]);
  const message = assertionError(report).message;
  expect(message).toContain('target "cards" member [0]');
  expect(message).toContain('target "cards" member [1]');
});

test("collection assertion diagnostics include measured values and expected constraints", async () => {
  const report = await failingReport(
    equalWidths(collection("cards"), { tolerancePx: 1 }),
    [rect(0, 0, 10), rect(0, 20, 12)],
  );
  const message = assertionError(report).message;
  expect(message).toContain("expected width difference <= 1px");
  expect(message).toContain("actual difference 2px");
});

test("an empty collection assertion diagnostic is distinct from a missing singular target", async () => {
  const report = await failingReport(equalWidths(collection("cards")), []);
  const message = assertionError(report).message;
  expect(message).toContain('collection target "cards" matched 0 elements');
  expect(message).not.toContain("missing singular target");
});

test("several findings from one collection rule do not inflate the assertion summary", async () => {
  const report = await failingReport(equalWidths(collection("cards")), [
    rect(0, 0, 20),
    rect(0, 20, 10),
    rect(0, 40, 11),
  ]);
  const message = assertionError(report).message;
  expect(report.findings).toHaveLength(2);
  expect(message).toContain("1 failed rule");
  expect(message).not.toContain("2 failed rules");
});

test("collection assertion diagnostics preserve finding order and the original report", async () => {
  const report = await failingReport(equalWidths(collection("cards")), [
    rect(0, 0, 20),
    rect(0, 20, 10),
    rect(0, 40, 11),
  ]);
  const error = assertionError(report);
  expect(error.report).toBe(report);
  expect(error.message.indexOf("member [1]")).toBeLessThan(
    error.message.indexOf("member [2]"),
  );
});
