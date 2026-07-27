import { expect, test } from "bun:test";

import {
  assertLayout,
  LayoutAssertionError,
  type LayoutReport,
} from "bylaw-ui";

const passing: LayoutReport = {
  passed: true,
  rules: { total: 0, passed: 0, failed: 0, skipped: 0 },
  findings: [],
};

const failing: LayoutReport = {
  passed: false,
  rules: { total: 2, passed: 0, failed: 2, skipped: 0 },
  findings: [
    {
      category: "layout",
      code: "size-mismatch",
      ruleIndex: 0,
      message: "avatar and card sizes differ",
      subject: "avatar",
      reference: "card",
      relationship: "sameSize",
      expected: { tolerancePx: 0 },
      actual: { widthDifferencePx: 2, heightDifferencePx: 3 },
    },
    {
      category: "layout",
      code: "ordering-violation",
      ruleIndex: 1,
      message: "icon crosses timeline",
      subject: "icon",
      reference: "timeline",
      relationship: "leftOf",
      expected: { tolerancePx: 0 },
      actual: { signedGapPx: -2, boundaryCrossingPx: 2 },
    },
  ],
};

test("assertLayout does not throw for a passing report", () => {
  expect(() => assertLayout(passing)).not.toThrow();
});

test("assertLayout throws for a failing report", () => {
  expect(() => assertLayout(failing)).toThrow(LayoutAssertionError);
});

test("assertLayout exposes the original failing report on the thrown error", () => {
  try {
    assertLayout(failing);
    throw new Error("expected assertLayout to throw");
  } catch (error) {
    expect(error).toBeInstanceOf(LayoutAssertionError);
    expect((error as LayoutAssertionError).report).toBe(failing);
  }
});

test("assertLayout produces a useful human-readable failure message", () => {
  expect(() => assertLayout(failing)).toThrow(
    expect.objectContaining({
      message: expect.stringContaining("Layout assertion failed"),
    }),
  );
});

test("assertLayout includes multiple findings in its failure output", () => {
  try {
    assertLayout(failing);
  } catch (error) {
    expect((error as Error).message).toContain("avatar and card sizes differ");
    expect((error as Error).message).toContain("icon crosses timeline");
  }
});

test("assertLayout does not mutate the supplied report", () => {
  const before = structuredClone(failing);
  expect(() => assertLayout(failing)).toThrow();
  expect(failing).toEqual(before);
});

test("exports LayoutAssertionError", async () => {
  const root = await import("bylaw-ui");
  expect(root.LayoutAssertionError).toBe(LayoutAssertionError);
});

test("assertLayout throws LayoutAssertionError for a failing report", () => {
  try {
    assertLayout(failing);
  } catch (error) {
    expect(error).toBeInstanceOf(LayoutAssertionError);
  }
});

test("LayoutAssertionError exposes the original report", () => {
  expect(new LayoutAssertionError(failing).report).toBe(failing);
});

test("LayoutAssertionError retains the exact report object by identity", () => {
  expect(new LayoutAssertionError(failing).report).toBe(failing);
});

test("the assertion message identifies affected rule positions and test IDs", () => {
  const error = new LayoutAssertionError(failing);
  expect(error.message).toContain("rule 0");
  expect(error.message).toContain('"avatar"');
  expect(error.message).toContain('"card"');
  expect(error.message).toContain("rule 1");
});

test("callers can identify a layout assertion failure without parsing its message", () => {
  const error = new LayoutAssertionError(failing);
  expect(error).toBeInstanceOf(LayoutAssertionError);
  expect(error.name).toBe("LayoutAssertionError");
});

test("callers can recover the original report from a layout assertion failure", () => {
  expect(new LayoutAssertionError(failing).report).toBe(failing);
});

test("explicit assertions reject malformed report inputs", () => {
  expect(() => assertLayout(null as never)).toThrow(TypeError);
});
