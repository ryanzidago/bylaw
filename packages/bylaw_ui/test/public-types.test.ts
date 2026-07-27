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
  type LayoutFinding,
  type LayoutReport,
  type LayoutRule,
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
