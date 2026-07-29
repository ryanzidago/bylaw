import { expect, test } from "bun:test";

import {
  LayoutAssertionError,
  type LayoutFinding,
  type LayoutReport,
  type LayoutRule,
} from "bylaw-ui";

const relationships: LayoutRule["kind"][] = [
  "align",
  "above",
  "below",
  "leftOf",
  "rightOf",
  "overlap",
  "notOverlap",
  "inside",
  "sameWidth",
  "sameHeight",
  "sameSize",
];

function layoutFinding(
  relationship: LayoutRule["kind"],
  ruleIndex: number,
  subject = `subject-${ruleIndex}`,
  reference = `reference-${ruleIndex}`,
): LayoutFinding {
  const common = {
    category: "layout" as const,
    ruleIndex,
    message: "legacy diagnostic",
    subject,
    reference,
    relationship,
  };

  switch (relationship) {
    case "align":
      return {
        ...common,
        code: "alignment-mismatch",
        expected: { alignment: "left", tolerancePx: 1 },
        actual: {
          subjectCoordinate: 12,
          referenceCoordinate: 10,
          differencePx: 2,
        },
      };
    case "above":
    case "below":
    case "leftOf":
    case "rightOf":
      return {
        ...common,
        code: "ordering-violation",
        expected: { tolerancePx: 1 },
        actual: { signedGapPx: -2, boundaryCrossingPx: 2 },
      };
    case "overlap":
      return {
        ...common,
        code: "missing-overlap",
        expected: { overlap: true },
        actual: { horizontalPx: 0, verticalPx: 10 },
      };
    case "notOverlap":
      return {
        ...common,
        code: "overlap-out-of-range",
        expected: { overlap: false },
        actual: { horizontalPx: 2, verticalPx: 3 },
      };
    case "inside":
      return {
        ...common,
        code: "containment-overflow",
        expected: { tolerancePx: 1, positiveIntersection: true },
        actual: {
          leftPx: 2,
          rightPx: 0,
          topPx: 0,
          bottomPx: 0,
          horizontalPx: 8,
          verticalPx: 10,
        },
      };
    case "sameWidth":
    case "sameHeight":
    case "sameSize":
      return {
        ...common,
        code: "size-mismatch",
        expected: { tolerancePx: 1 },
        actual: { widthDifferencePx: 2, heightDifferencePx: 3 },
      };
  }
}

function reportWith(
  findings: LayoutFinding[],
  failed = findings.length,
  total = failed,
): LayoutReport {
  return {
    passed: false,
    rules: { total, passed: total - failed, failed, skipped: 0 },
    findings,
  };
}

test("identifies the failed rule and its operands", () => {
  const message = new LayoutAssertionError(
    reportWith([layoutFinding("sameWidth", 3, "avatar", "card")], 1, 4),
  ).message;

  expect(message).toContain("rule 3");
  expect(message).toContain("sameWidth failed");
  expect(message).toContain('subject: "avatar"');
  expect(message).toContain('reference: "card"');
});

test("names every supported layout relationship in its failure message", () => {
  relationships.forEach((relationship) => {
    const message = new LayoutAssertionError(
      reportWith([layoutFinding(relationship, 0)], 1),
    ).message;

    expect(message).toContain(`${relationship} failed`);
  });
});

test("names the subject and reference for every layout relationship", () => {
  relationships.forEach((relationship) => {
    const message = new LayoutAssertionError(
      reportWith([layoutFinding(relationship, 0, "avatar", "profile-card")], 1),
    ).message;

    expect(message).toContain('subject: "avatar"');
    expect(message).toContain('reference: "profile-card"');
  });
});

test("renders multiple failures in stable order", () => {
  const findings = [
    layoutFinding("sameWidth", 0, "avatar", "card"),
    layoutFinding("leftOf", 1, "icon", "timeline"),
    layoutFinding("inside", 2, "dialog", "viewport"),
  ];
  const message = new LayoutAssertionError(reportWith(findings)).message;

  expect(message.indexOf("sameWidth failed")).toBeLessThan(
    message.indexOf("leftOf failed"),
  );
  expect(message.indexOf("leftOf failed")).toBeLessThan(
    message.indexOf("inside failed"),
  );
});

test("separates multiple failures into readable blocks", () => {
  const message = new LayoutAssertionError(
    reportWith([
      layoutFinding("sameWidth", 0),
      layoutFinding("sameHeight", 1),
    ]),
  ).message;

  expect(message).toContain("sameWidth failed:");
  expect(message).toMatch(/sameWidth failed:[\s\S]+\n\nsameHeight failed:/);
});

test(
  "renders several findings for the same rule without inflating the failed rule count",
  () => {
    const findings: LayoutFinding[] = [
      {
        category: "invalid-rule",
        code: "missing-field",
        ruleIndex: 0,
        message: "legacy first diagnostic",
        fieldPath: "subject",
        reason: "is required",
      },
      {
        category: "invalid-rule",
        code: "unknown-field",
        ruleIndex: 0,
        message: "legacy second diagnostic",
        fieldPath: "surprise",
        reason: "is not supported",
      },
    ];
    const message = new LayoutAssertionError(reportWith(findings, 1)).message;

    expect(message).toContain("Layout assertion failed for 1 rule");
    expect(message).toContain("subject");
    expect(message).toContain("surprise");
  },
);

test("renders geometric values and constraints in CSS pixels", () => {
  const message = new LayoutAssertionError(
    reportWith([layoutFinding("sameWidth", 0)], 1),
  ).message;

  expect(message).toContain("difference: 2px");
  expect(message).toContain("allowed tolerance: 1px");
});

test("preserves fractional geometric values", () => {
  const finding = layoutFinding("sameWidth", 0);
  if (finding.category !== "layout") {
    throw new Error("expected a layout finding");
  }
  finding.expected = { tolerancePx: 0.25 };
  finding.actual = { widthDifferencePx: 1.25, heightDifferencePx: 0 };

  const message = new LayoutAssertionError(reportWith([finding], 1)).message;

  expect(message).toContain("difference: 1.25px");
  expect(message).toContain("allowed tolerance: 0.25px");
});

test("retains the original structured report", () => {
  const report = reportWith([layoutFinding("sameWidth", 0)], 1);
  expect(new LayoutAssertionError(report).report).toBe(report);
});

test(
  "preserves structured expected and actual data after formatting the error",
  () => {
    const report = reportWith([layoutFinding("sameSize", 0)], 1);
    const before = structuredClone(report.findings[0]);

    const error = new LayoutAssertionError(report);

    expect(error.report.findings[0]).toEqual(before);
    expect(error.report.findings[0]).toBe(report.findings[0]);
  },
);
