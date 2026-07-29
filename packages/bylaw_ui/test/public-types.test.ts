import { expect, test } from "bun:test";

import {
  above,
  align,
  checkLayout,
  inside,
  leftOf,
  notOverlap,
  overlap,
  sameSize,
  type Alignment,
  type ElementFinding,
  type LayoutFinding,
  type LayoutReport,
  type LayoutRule,
  type LayoutViolationFinding,
} from "bylaw-ui";
import { fixtureAdapter } from "./support";

test("align accepts every supported alignment value", () => {
  const values: Alignment[] = [
    "left",
    "right",
    "top",
    "bottom",
    "centerX",
    "centerY",
  ];
  expect(values.map((value) => align("a", "b", value).alignment)).toEqual(values);
});

test("align rejects unsupported alignment values at compile time", () => {
  if (false) {
    // @ts-expect-error unsupported alignment
    align("a", "b", "middle");
  }
  expect(true).toBe(true);
});

test("ordering helpers accept tolerance and gap options", () => {
  expect(
    leftOf("a", "b", {
      tolerancePx: 1,
      gap: { minPx: 2, maxPx: 3 },
    }).options,
  ).toEqual({ tolerancePx: 1, gap: { minPx: 2, maxPx: 3 } });
  expect(above("a", "b", { tolerancePx: 1 })).toBeDefined();
});

test("inside and size helpers accept tolerance options", () => {
  expect(inside("a", "b", { tolerancePx: 1 }).options).toEqual({
    tolerancePx: 1,
  });
  expect(sameSize("a", "b", { tolerancePx: 1 }).options).toEqual({
    tolerancePx: 1,
  });
});

test("overlap accepts independent horizontal and vertical ranges", () => {
  expect(
    overlap("a", "b", {
      horizontal: { minPx: 1 },
      vertical: { maxPx: 2 },
    }).options,
  ).toEqual({
    horizontal: { minPx: 1 },
    vertical: { maxPx: 2 },
  });
});

test("notOverlap does not accept overlap range options", () => {
  if (false) {
    // @ts-expect-error notOverlap accepts exactly two arguments
    notOverlap("a", "b", { horizontal: { minPx: 1 } });
  }
  expect(notOverlap("a", "b")).toBeDefined();
});

test("public rule helpers return values accepted by checkLayout", async () => {
  const rule: LayoutRule = sameSize("a", "b");
  const report: LayoutReport = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [rule],
  });
  const findings: LayoutFinding[] = report.findings;
  expect(findings).toBeArray();
});

test("exports the public LayoutRule type", () => {
  const rule: LayoutRule = sameSize("a", "b");
  expect(rule.kind).toBe("sameSize");
});

test("exports the public LayoutReport type", () => {
  const report: LayoutReport = {
    passed: true,
    rules: { total: 0, passed: 0, failed: 0, skipped: 0 },
    findings: [],
  };
  expect(report.passed).toBe(true);
});

test("exports the public LayoutFinding type", () => {
  const finding: LayoutFinding = {
    category: "invalid-rule",
    code: "missing-field",
    ruleIndex: 0,
    message: "missing",
    fieldPath: "kind",
    reason: "required",
  };
  expect(finding.category).toBe("invalid-rule");
});

/**
 * @doc
 * Issue: Binary findings accept unary relationship kinds.
 * Why it matters: Consumers cannot safely distinguish target-only findings from
 * subject/reference findings using the public relationship discriminant.
 */
test("binary findings reject unary relationship kinds at compile time", () => {
  const finding: Extract<LayoutViolationFinding, { subject: string }> = {
    category: "layout",
    code: "alignment-mismatch",
    ruleIndex: 0,
    message: "impossible binary viewport finding",
    subject: "subject",
    reference: "reference",
    // @ts-expect-error binary findings cannot describe unary relationships
    relationship: "inViewport",
    expected: {},
    actual: {},
  };

  expect(finding).toBeDefined();
});

/**
 * @doc
 * Issue: Unary layout findings accept codes belonging to binary rules.
 * Why it matters: Narrowing by relationship does not guarantee that the code
 * and diagnostic payload belong to the same rule.
 */
test("unary layout findings reject unrelated violation codes at compile time", () => {
  const finding: Extract<LayoutViolationFinding, { target: string }> = {
    category: "layout",
    // @ts-expect-error width findings only use dimension-out-of-range
    code: "alignment-mismatch",
    ruleIndex: 0,
    message: "impossible width finding",
    target: "sidebar",
    relationship: "width",
    expected: { range: { minPx: 260 } },
    actual: { widthPx: 240 },
  };

  expect(finding).toBeDefined();
});

/**
 * @doc
 * Issue: Unary element findings allow resolution codes with visibility payloads.
 * Why it matters: Consumers cannot safely interpret expected and actual after
 * narrowing on an element finding's code.
 */
test("unary element findings correlate codes with diagnostic payloads", () => {
  const finding: Extract<ElementFinding, { target: string }> = {
    category: "element-resolution",
    code: "missing-element",
    ruleIndex: 0,
    message: "missing target",
    target: "sidebar",
    operand: "target",
    testId: "sidebar",
    expected: { matchCount: 1 },
    // @ts-expect-error missing-element requires a match-count payload
    actual: { hidden: true },
  };

  expect(finding).toBeDefined();
});

/**
 * @doc
 * Issue: A width relationship does not narrow its diagnostic payload.
 * Why it matters: Callers should be able to consume structured width findings
 * without casts or defensive property checks.
 */
test("width findings narrow to their exact diagnostic payload", () => {
  function actualWidth(
    finding: LayoutViolationFinding,
  ): number | undefined {
    if (finding.relationship !== "width") {
      return undefined;
    }

    return finding.actual.widthPx;
  }

  expect(actualWidth).toBeFunction();
});
