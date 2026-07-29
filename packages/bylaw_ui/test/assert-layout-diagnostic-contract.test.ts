import { test } from "bun:test";

test("a passing report still produces no assertion error or diagnostic output", () => {
  const { expect } = require("bun:test");
  const { assertLayout } = require("bylaw-ui");
  expect(() =>
    assertLayout({
      passed: true,
      rules: { total: 1, passed: 1, failed: 0, skipped: 0 },
      findings: [],
    }),
  ).not.toThrow();
});

test("each failure renders the rule before measurements, constraints, and violation amounts", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "layout",
    code: "size-mismatch",
    ruleIndex: 0,
    message: "legacy",
    subject: "avatar",
    reference: "card",
    relationship: "sameWidth",
    expected: { tolerancePx: 1 },
    actual: {
      subjectWidthPx: 1038,
      referenceWidthPx: 1040,
      widthDifferencePx: 2,
    },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  }).message;
  expect(message.indexOf("sameWidth failed")).toBeLessThan(
    message.indexOf("subject width: 1038px"),
  );
  expect(message.indexOf("subject width: 1038px")).toBeLessThan(
    message.indexOf("allowed tolerance: 1px"),
  );
  expect(message.indexOf("allowed tolerance: 1px")).toBeLessThan(
    message.indexOf("exceeds tolerance by: 1px"),
  );
});

test("multiple failures preserve the order of findings in the original report", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const make = (relationship: string, ruleIndex: number) => ({
    category: "layout",
    code: "size-mismatch",
    ruleIndex,
    message: "legacy",
    subject: `s${ruleIndex}`,
    reference: `r${ruleIndex}`,
    relationship,
    expected: { tolerancePx: 0 },
    actual: { widthDifferencePx: 1 },
  });
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 3, passed: 0, failed: 3, skipped: 0 },
    findings: [
      make("sameHeight", 2),
      make("sameWidth", 0),
      make("sameSize", 1),
    ],
  }).message;
  expect(message.indexOf("sameHeight failed")).toBeLessThan(
    message.indexOf("sameWidth failed"),
  );
  expect(message.indexOf("sameWidth failed")).toBeLessThan(
    message.indexOf("sameSize failed"),
  );
});

test("identical reports produce identical diagnostic messages", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const report = {
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [
      {
        category: "layout",
        code: "size-mismatch",
        ruleIndex: 0,
        message: "legacy",
        subject: "a",
        reference: "b",
        relationship: "sameWidth",
        expected: { tolerancePx: 0 },
        actual: { widthDifferencePx: 1 },
      },
    ],
  };
  expect(new LayoutAssertionError(structuredClone(report)).message).toBe(
    new LayoutAssertionError(structuredClone(report)).message,
  );
});

test("multiple failures use stable separators that keep each diagnostic readable", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const make = (relationship: string, ruleIndex: number) => ({
    category: "layout",
    code: "size-mismatch",
    ruleIndex,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship,
    expected: { tolerancePx: 0 },
    actual: { widthDifferencePx: 1 },
  });
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 2, passed: 0, failed: 2, skipped: 0 },
    findings: [make("sameWidth", 0), make("sameHeight", 1)],
  }).message;
  expect(message).toMatch(/sameWidth failed:[\s\S]+\n\nsameHeight failed:/);
});

test("multiple operand findings for one skipped rule do not inflate the failed rule count", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const common = {
    category: "element-resolution",
    code: "missing-element",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    expected: { matchCount: 1 },
    actual: { matchCount: 0 },
  };
  const report = {
    passed: false,
    rules: { total: 1, passed: 0, failed: 0, skipped: 1 },
    findings: [
      { ...common, operand: "subject", testId: "a" },
      { ...common, operand: "reference", testId: "b" },
    ],
  };
  expect(new LayoutAssertionError(report).message).toContain(
    "0 failed, 1 skipped",
  );
});

test("the assertion summary distinguishes failed rules from skipped rules", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const report = {
    passed: false,
    rules: { total: 4, passed: 1, failed: 2, skipped: 1 },
    findings: [],
  };
  const message = new LayoutAssertionError(report).message;
  expect(message).toContain("2 failed");
  expect(message).toContain("1 skipped");
});

test("a realistic broken page renders actionable alignment, gap, overlap, containment, and size diagnostics together", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const layouts = [
    [
      "alignment-mismatch",
      "align",
      { tolerancePx: 1 },
      { subjectCoordinate: 12, referenceCoordinate: 10, differencePx: 2 },
    ],
    [
      "gap-out-of-range",
      "leftOf",
      { gap: { minPx: 4, maxPx: 8 } },
      { signedGapPx: 2 },
    ],
    [
      "missing-overlap",
      "overlap",
      { overlap: true },
      { horizontalPx: 0, verticalPx: 10 },
    ],
    [
      "containment-overflow",
      "inside",
      { tolerancePx: 1 },
      { leftPx: 2, rightPx: 0, topPx: 0, bottomPx: 0 },
    ],
    [
      "size-mismatch",
      "sameWidth",
      { tolerancePx: 1 },
      { subjectWidthPx: 98, referenceWidthPx: 100, widthDifferencePx: 2 },
    ],
  ];
  const findings = layouts.map(
    ([code, relationship, expected, actual], ruleIndex) => ({
      category: "layout",
      code,
      ruleIndex,
      message: "legacy",
      subject: `subject-${ruleIndex}`,
      reference: `reference-${ruleIndex}`,
      relationship,
      expected,
      actual,
    }),
  );
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 5, passed: 0, failed: 5, skipped: 0 },
    findings,
  }).message;
  for (const relationship of [
    "align",
    "leftOf",
    "overlap",
    "inside",
    "sameWidth",
  ])
    expect(message).toContain(`${relationship} failed`);
});

test("constructing diagnostic output does not mutate the supplied report", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const report = {
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [
      {
        category: "layout",
        code: "size-mismatch",
        ruleIndex: 0,
        message: "legacy",
        subject: "a",
        reference: "b",
        relationship: "sameWidth",
        expected: { tolerancePx: 1 },
        actual: { widthDifferencePx: 2 },
      },
    ],
  };
  const before = structuredClone(report);
  new LayoutAssertionError(report);
  expect(report).toEqual(before);
});

test("the assertion error retains the exact original report object", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const report = {
    passed: false,
    rules: { total: 0, passed: 0, failed: 0, skipped: 0 },
    findings: [],
  };
  expect(new LayoutAssertionError(report).report).toBe(report);
});

test("structured expected data remains available after diagnostic rendering", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const expected = { tolerancePx: 1, gap: { minPx: 4, maxPx: 8 } };
  const finding = {
    category: "layout",
    code: "gap-out-of-range",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "leftOf",
    expected,
    actual: { signedGapPx: 2 },
  };
  const error = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  });
  expect(error.report.findings[0].expected).toBe(expected);
});

test("structured actual data retains existing derived measurements after diagnostic rendering", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const actual = { signedGapPx: -2, boundaryCrossingPx: 2 };
  const finding = {
    category: "layout",
    code: "ordering-violation",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "leftOf",
    expected: { tolerancePx: 1 },
    actual,
  };
  const error = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  });
  expect(error.report.findings[0].actual).toBe(actual);
});

test("structured actual data includes the raw subject and reference measurements used by diagnostics", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const subject = { x: 0, y: 0, width: 98, height: 47 };
  const reference = { x: 10, y: 10, width: 100, height: 50 };
  const actual = {
    subject,
    reference,
    widthDifferencePx: 2,
    heightDifferencePx: 3,
  };
  const finding = {
    category: "layout",
    code: "size-mismatch",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "sameSize",
    expected: { tolerancePx: 1 },
    actual,
  };
  const error = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  });
  expect(error.report.findings[0].actual.subject).toEqual(subject);
  expect(error.report.findings[0].actual.reference).toEqual(reference);
});
