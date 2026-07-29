import type {
  LayoutRule,
  LayoutViolationFinding,
  PixelRange,
  ToleranceRule,
} from "../types";
import type { Rectangle } from "./adapter";

type Edges = Rectangle & {
  right: number;
  bottom: number;
};

function edges(rect: Rectangle): Edges {
  return {
    ...rect,
    right: rect.x + rect.width,
    bottom: rect.y + rect.height,
  };
}

function inRange(value: number, range: PixelRange): boolean {
  return (
    (range.minPx === undefined || value >= range.minPx) &&
    (range.maxPx === undefined || value <= range.maxPx)
  );
}

function violation(
  rule: LayoutRule,
  ruleIndex: number,
  code: LayoutViolationFinding["code"],
  expected: LayoutViolationFinding["expected"],
  actual: LayoutViolationFinding["actual"],
): LayoutViolationFinding {
  return {
    category: "layout",
    code,
    ruleIndex,
    message: `Rule ${ruleIndex} (${rule.subject} ${rule.kind} ${rule.reference}) failed: ${code}`,
    subject: rule.subject,
    reference: rule.reference,
    relationship: rule.kind,
    expected,
    actual,
  };
}

function alignmentCoordinate(rect: Edges, alignment: string): number {
  switch (alignment) {
    case "left":
      return rect.x;
    case "right":
      return rect.right;
    case "top":
      return rect.y;
    case "bottom":
      return rect.bottom;
    case "centerX":
      return (rect.x + rect.right) / 2;
    case "centerY":
      return (rect.y + rect.bottom) / 2;
    default:
      throw new Error(`Unsupported alignment: ${alignment}`);
  }
}

function evaluateAlignment(
  rule: Extract<LayoutRule, { kind: "align" }>,
  ruleIndex: number,
  subject: Edges,
  reference: Edges,
): LayoutViolationFinding[] {
  const subjectCoordinate = alignmentCoordinate(subject, rule.alignment);
  const referenceCoordinate = alignmentCoordinate(reference, rule.alignment);
  const differencePx = Math.abs(subjectCoordinate - referenceCoordinate);
  const tolerancePx = rule.options?.tolerancePx ?? 0;

  return differencePx <= tolerancePx
    ? []
    : [
        violation(
          rule,
          ruleIndex,
          "alignment-mismatch",
          { alignment: rule.alignment, tolerancePx },
          { subjectCoordinate, referenceCoordinate, differencePx },
        ),
      ];
}

function signedGap(
  kind: "above" | "below" | "leftOf" | "rightOf",
  subject: Edges,
  reference: Edges,
): number {
  switch (kind) {
    case "leftOf":
      return reference.x - subject.right;
    case "rightOf":
      return subject.x - reference.right;
    case "above":
      return reference.y - subject.bottom;
    case "below":
      return subject.y - reference.bottom;
  }
}

function evaluateOrdering(
  rule: Extract<
    LayoutRule,
    { kind: "above" | "below" | "leftOf" | "rightOf" }
  >,
  ruleIndex: number,
  subject: Edges,
  reference: Edges,
): LayoutViolationFinding[] {
  const gapPx = signedGap(rule.kind, subject, reference);
  const boundaryCrossingPx = Math.max(0, -gapPx);
  const tolerancePx = rule.options?.tolerancePx ?? 0;

  if (boundaryCrossingPx > tolerancePx) {
    return [
      violation(
        rule,
        ruleIndex,
        "ordering-violation",
        { tolerancePx, ...(rule.options?.gap ? { gap: rule.options.gap } : {}) },
        { signedGapPx: gapPx, boundaryCrossingPx },
      ),
    ];
  }

  if (rule.options?.gap && !inRange(gapPx, rule.options.gap)) {
    return [
      violation(
        rule,
        ruleIndex,
        "gap-out-of-range",
        { gap: rule.options.gap, tolerancePx },
        { signedGapPx: gapPx, boundaryCrossingPx },
      ),
    ];
  }

  return [];
}

function overlapDepths(
  subject: Edges,
  reference: Edges,
): { horizontalPx: number; verticalPx: number } {
  return {
    horizontalPx: Math.max(
      0,
      Math.min(subject.right, reference.right) - Math.max(subject.x, reference.x),
    ),
    verticalPx: Math.max(
      0,
      Math.min(subject.bottom, reference.bottom) -
        Math.max(subject.y, reference.y),
    ),
  };
}

function evaluateOverlap(
  rule: Extract<LayoutRule, { kind: "overlap" | "notOverlap" }>,
  ruleIndex: number,
  subject: Edges,
  reference: Edges,
): LayoutViolationFinding[] {
  const depths = overlapDepths(subject, reference);
  const intersects = depths.horizontalPx > 0 && depths.verticalPx > 0;

  if (rule.kind === "notOverlap") {
    return intersects
      ? [
          violation(rule, ruleIndex, "overlap-out-of-range", { overlap: false }, depths),
        ]
      : [];
  }

  if (!intersects) {
    return [
      violation(rule, ruleIndex, "missing-overlap", { overlap: true }, depths),
    ];
  }

  const horizontalValid =
    rule.options?.horizontal === undefined ||
    inRange(depths.horizontalPx, rule.options.horizontal);
  const verticalValid =
    rule.options?.vertical === undefined ||
    inRange(depths.verticalPx, rule.options.vertical);

  return horizontalValid && verticalValid
    ? []
    : [
        violation(
          rule,
          ruleIndex,
          "overlap-out-of-range",
          {
            ...(rule.options?.horizontal
              ? { horizontal: rule.options.horizontal }
              : {}),
            ...(rule.options?.vertical ? { vertical: rule.options.vertical } : {}),
          },
          depths,
        ),
      ];
}

function evaluateInside(
  rule: ToleranceRule,
  ruleIndex: number,
  subject: Edges,
  reference: Edges,
): LayoutViolationFinding[] {
  const tolerancePx = rule.options?.tolerancePx ?? 0;
  const overflow = {
    leftPx: Math.max(0, reference.x - subject.x),
    rightPx: Math.max(0, subject.right - reference.right),
    topPx: Math.max(0, reference.y - subject.y),
    bottomPx: Math.max(0, subject.bottom - reference.bottom),
  };
  const intersection = overlapDepths(subject, reference);
  const intersects =
    intersection.horizontalPx > 0 && intersection.verticalPx > 0;
  const withinTolerance = Object.values(overflow).every(
    (value) => value <= tolerancePx,
  );

  return intersects && withinTolerance
    ? []
    : [
        violation(
          rule,
          ruleIndex,
          "containment-overflow",
          { tolerancePx, positiveIntersection: true },
          { ...overflow, ...intersection },
        ),
      ];
}

function evaluateSize(
  rule: ToleranceRule,
  ruleIndex: number,
  subject: Edges,
  reference: Edges,
): LayoutViolationFinding[] {
  const tolerancePx = rule.options?.tolerancePx ?? 0;
  const widthDifferencePx = Math.abs(subject.width - reference.width);
  const heightDifferencePx = Math.abs(subject.height - reference.height);
  const widthValid =
    rule.kind === "sameHeight" || widthDifferencePx <= tolerancePx;
  const heightValid =
    rule.kind === "sameWidth" || heightDifferencePx <= tolerancePx;

  return widthValid && heightValid
    ? []
    : [
        violation(
          rule,
          ruleIndex,
          "size-mismatch",
          { tolerancePx },
          { widthDifferencePx, heightDifferencePx },
        ),
      ];
}

export function evaluateGeometry(
  rule: LayoutRule,
  ruleIndex: number,
  subjectRect: Rectangle,
  referenceRect: Rectangle,
): LayoutViolationFinding[] {
  const subject = edges(subjectRect);
  const reference = edges(referenceRect);

  switch (rule.kind) {
    case "align":
      return evaluateAlignment(rule, ruleIndex, subject, reference);
    case "above":
    case "below":
    case "leftOf":
    case "rightOf":
      return evaluateOrdering(rule, ruleIndex, subject, reference);
    case "overlap":
    case "notOverlap":
      return evaluateOverlap(rule, ruleIndex, subject, reference);
    case "inside":
      return evaluateInside(rule, ruleIndex, subject, reference);
    case "sameWidth":
    case "sameHeight":
    case "sameSize":
      return evaluateSize(rule, ruleIndex, subject, reference);
  }
}
