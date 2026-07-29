import type {
  ElementFinding,
  InvalidRuleFinding,
  JsonValue,
  LayoutFinding,
  LayoutReport,
  LayoutViolationFinding,
  PixelRange,
} from "./types.js";

type DiagnosticRecord = { [key: string]: JsonValue | undefined };

function numberValue(record: DiagnosticRecord, key: string): number | undefined {
  const value = record[key];
  return typeof value === "number" ? value : undefined;
}

function booleanValue(
  record: DiagnosticRecord,
  key: string,
): boolean | undefined {
  const value = record[key];
  return typeof value === "boolean" ? value : undefined;
}

function stringValue(record: DiagnosticRecord, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" ? value : undefined;
}

function rangeValue(
  record: DiagnosticRecord,
  key: string,
): PixelRange | undefined {
  const value = record[key];
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }

  const minPx = numberValue(value, "minPx");
  const maxPx = numberValue(value, "maxPx");
  return minPx === undefined && maxPx === undefined ? undefined : { minPx, maxPx };
}

function px(value: number): string {
  return `${value}px`;
}

function range(range: PixelRange): string {
  if (range.minPx !== undefined && range.maxPx !== undefined) {
    return `${px(range.minPx)}–${px(range.maxPx)}`;
  }
  if (range.minPx !== undefined) {
    return `at least ${px(range.minPx)}`;
  }
  return `at most ${px(range.maxPx!)}`;
}

function appendValue(
  lines: string[],
  label: string,
  value: number | undefined,
): void {
  if (value !== undefined) {
    lines.push(`${label}: ${px(value)}`);
  }
}

function appendRangeResult(
  lines: string[],
  label: string,
  measured: number | undefined,
  allowed: PixelRange | undefined,
): void {
  if (measured === undefined || allowed === undefined) {
    return;
  }

  lines.push(`${label}: ${range(allowed)}`);
  if (allowed.minPx !== undefined && measured < allowed.minPx) {
    lines.push(`below minimum by: ${px(allowed.minPx - measured)}`);
  } else if (allowed.maxPx !== undefined && measured > allowed.maxPx) {
    lines.push(`above maximum by: ${px(measured - allowed.maxPx)}`);
  }
}

function appendToleranceResult(
  lines: string[],
  difference: number | undefined,
  tolerance: number | undefined,
  prefix = "",
): void {
  if (tolerance === undefined) {
    return;
  }

  if (prefix.length === 0) {
    lines.push(`allowed tolerance: ${px(tolerance)}`);
  }
  if (difference !== undefined && difference > tolerance) {
    lines.push(`${prefix}exceeds tolerance by: ${px(difference - tolerance)}`);
  }
}

function formatInvalidRule(finding: InvalidRuleFinding): string {
  return [
    "invalid rule:",
    `rule ${finding.ruleIndex}`,
    `field: ${finding.fieldPath}`,
    `reason: ${finding.reason}`,
    `detail: ${finding.message}`,
  ].join("\n");
}

function formatElement(finding: ElementFinding): string {
  const lines = [
    `${finding.code.replace("-element", " element")}:`,
    `rule ${finding.ruleIndex}`,
    `${finding.operand}: ${JSON.stringify(finding.testId)}`,
  ];

  if ("matchCount" in finding.expected && "matchCount" in finding.actual) {
    lines.push(`expected matches: ${finding.expected.matchCount}`);
    lines.push(`actual matches: ${finding.actual.matchCount}`);
  } else if ("width" in finding.actual) {
    lines.push(`measured width: ${px(finding.actual.width)}`);
    lines.push(`measured height: ${px(finding.actual.height)}`);
  }

  lines.push(`detail: ${finding.message}`);
  return lines.join("\n");
}

function formatAlignment(
  finding: LayoutViolationFinding,
  lines: string[],
): void {
  lines.push(`alignment: ${stringValue(finding.expected, "alignment")}`);
  appendValue(
    lines,
    "subject coordinate",
    numberValue(finding.actual, "subjectCoordinate"),
  );
  appendValue(
    lines,
    "reference coordinate",
    numberValue(finding.actual, "referenceCoordinate"),
  );
  const difference = numberValue(finding.actual, "differencePx");
  appendValue(lines, "difference", difference);
  appendToleranceResult(
    lines,
    difference,
    numberValue(finding.expected, "tolerancePx"),
  );
}

function formatOrdering(
  finding: LayoutViolationFinding,
  lines: string[],
): void {
  const signedGap = numberValue(finding.actual, "signedGapPx");
  const boundaryCrossing = numberValue(finding.actual, "boundaryCrossingPx");
  appendValue(lines, "signed gap", signedGap);
  appendValue(lines, "boundary crossing", boundaryCrossing);

  if (finding.code === "ordering-violation") {
    appendToleranceResult(
      lines,
      boundaryCrossing,
      numberValue(finding.expected, "tolerancePx"),
    );
    return;
  }

  appendValue(lines, "measured gap", signedGap);
  appendRangeResult(
    lines,
    "allowed gap",
    signedGap,
    rangeValue(finding.expected, "gap"),
  );
}

function formatOverlap(
  finding: LayoutViolationFinding,
  lines: string[],
): void {
  const horizontal = numberValue(finding.actual, "horizontalPx");
  const vertical = numberValue(finding.actual, "verticalPx");
  appendValue(lines, "horizontal overlap", horizontal);
  appendValue(lines, "vertical overlap", vertical);

  if (finding.code === "missing-overlap") {
    lines.push("required overlap: positive on both axes");
    return;
  }
  if (booleanValue(finding.expected, "overlap") === false) {
    lines.push("allowed overlap: none");
    return;
  }

  appendRangeResult(
    lines,
    "allowed horizontal overlap",
    horizontal,
    rangeValue(finding.expected, "horizontal"),
  );
  appendRangeResult(
    lines,
    "allowed vertical overlap",
    vertical,
    rangeValue(finding.expected, "vertical"),
  );
}

function formatContainment(
  finding: LayoutViolationFinding,
  lines: string[],
): void {
  const overflows = [
    numberValue(finding.actual, "leftPx"),
    numberValue(finding.actual, "rightPx"),
    numberValue(finding.actual, "topPx"),
    numberValue(finding.actual, "bottomPx"),
  ];
  appendValue(lines, "left overflow", overflows[0]);
  appendValue(lines, "right overflow", overflows[1]);
  appendValue(lines, "top overflow", overflows[2]);
  appendValue(lines, "bottom overflow", overflows[3]);
  appendValue(
    lines,
    "horizontal intersection",
    numberValue(finding.actual, "horizontalPx"),
  );
  appendValue(
    lines,
    "vertical intersection",
    numberValue(finding.actual, "verticalPx"),
  );

  if (booleanValue(finding.expected, "positiveIntersection")) {
    lines.push("required intersection: positive on both axes");
  }

  const tolerance = numberValue(finding.expected, "tolerancePx");
  const greatestOverflow = Math.max(...overflows.filter((value) => value !== undefined));
  appendToleranceResult(lines, greatestOverflow, tolerance);
}

function formatSize(
  finding: LayoutViolationFinding,
  lines: string[],
): void {
  const measurements = finding.measurements ?? {};
  const widthDifference = numberValue(finding.actual, "widthDifferencePx");
  const heightDifference = numberValue(finding.actual, "heightDifferencePx");
  const tolerance = numberValue(finding.expected, "tolerancePx");

  if (finding.relationship !== "sameHeight") {
    appendValue(
      lines,
      "subject width",
      numberValue(measurements, "subjectWidthPx"),
    );
    appendValue(
      lines,
      "reference width",
      numberValue(measurements, "referenceWidthPx"),
    );
    appendValue(
      lines,
      finding.relationship === "sameSize" ? "width difference" : "difference",
      widthDifference,
    );
  }

  if (finding.relationship !== "sameWidth") {
    appendValue(
      lines,
      "subject height",
      numberValue(measurements, "subjectHeightPx"),
    );
    appendValue(
      lines,
      "reference height",
      numberValue(measurements, "referenceHeightPx"),
    );
    appendValue(
      lines,
      finding.relationship === "sameSize" ? "height difference" : "difference",
      heightDifference,
    );
  }

  if (tolerance !== undefined) {
    lines.push(`allowed tolerance: ${px(tolerance)}`);
  }
  if (finding.relationship !== "sameHeight") {
    if (
      widthDifference !== undefined &&
      tolerance !== undefined &&
      widthDifference > tolerance
    ) {
      const prefix = finding.relationship === "sameSize" ? "width " : "";
      lines.push(
        `${prefix}exceeds tolerance by: ${px(widthDifference - tolerance)}`,
      );
    }
  }
  if (finding.relationship !== "sameWidth") {
    if (
      heightDifference !== undefined &&
      tolerance !== undefined &&
      heightDifference > tolerance
    ) {
      const prefix = finding.relationship === "sameSize" ? "height " : "";
      lines.push(
        `${prefix}exceeds tolerance by: ${px(heightDifference - tolerance)}`,
      );
    }
  }
}

function formatLayout(finding: LayoutViolationFinding): string {
  const lines = [
    `${finding.relationship} failed:`,
    `rule ${finding.ruleIndex}`,
    `subject: ${JSON.stringify(finding.subject)}`,
    `reference: ${JSON.stringify(finding.reference)}`,
  ];

  switch (finding.code) {
    case "alignment-mismatch":
      formatAlignment(finding, lines);
      break;
    case "ordering-violation":
    case "gap-out-of-range":
      formatOrdering(finding, lines);
      break;
    case "missing-overlap":
    case "overlap-out-of-range":
      formatOverlap(finding, lines);
      break;
    case "containment-overflow":
      formatContainment(finding, lines);
      break;
    case "size-mismatch":
      formatSize(finding, lines);
      break;
  }

  lines.push(`detail: ${finding.message}`);
  return lines.join("\n");
}

function formatFinding(finding: LayoutFinding): string {
  switch (finding.category) {
    case "invalid-rule":
      return formatInvalidRule(finding);
    case "element-resolution":
    case "element-visibility":
      return formatElement(finding);
    case "layout":
      return formatLayout(finding);
  }
}

export class LayoutAssertionError extends Error {
  readonly report: LayoutReport;

  constructor(report: LayoutReport) {
    const details = report.findings.map(formatFinding).join("\n\n");
    const ruleCount = report.rules.failed + report.rules.skipped;

    super(
      `Layout assertion failed for ${ruleCount} ${ruleCount === 1 ? "rule" : "rules"}${
        details.length > 0 ? `:\n${details}` : ""
      }`,
    );
    this.name = "LayoutAssertionError";
    this.report = report;
  }
}

export function assertLayout(report: LayoutReport): void {
  if (
    typeof report !== "object" ||
    report === null ||
    typeof report.passed !== "boolean"
  ) {
    throw new TypeError("assertLayout expects a LayoutReport");
  }

  if (!report.passed) {
    throw new LayoutAssertionError(report);
  }
}
