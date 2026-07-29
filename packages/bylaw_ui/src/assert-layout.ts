import type {
  ElementFinding,
  InvalidRuleFinding,
  JsonValue,
  LayoutFinding,
  LayoutReport,
  LayoutViolationFinding,
} from "./types.js";

type DiagnosticData = { [key: string]: JsonValue | undefined };
type PixelRange = { minPx?: number; maxPx?: number };

function number(data: DiagnosticData, key: string): number | undefined {
  const value = data[key];
  return typeof value === "number" ? value : undefined;
}

function boolean(data: DiagnosticData, key: string): boolean | undefined {
  const value = data[key];
  return typeof value === "boolean" ? value : undefined;
}

function object(
  data: DiagnosticData,
  key: string,
): DiagnosticData | undefined {
  const value = data[key];
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value
    : undefined;
}

function pixels(value: number): string {
  const normalized = Number.parseFloat(value.toPrecision(15));
  return `${Object.is(normalized, -0) ? 0 : normalized}px`;
}

function pixelLine(
  label: string,
  value: number | undefined,
): string | undefined {
  return value === undefined ? undefined : `${label}: ${pixels(value)}`;
}

function excessLine(
  label: string,
  value: number | undefined,
  tolerance: number,
): string | undefined {
  return value !== undefined && value > tolerance
    ? `${label}: ${pixels(value - tolerance)}`
    : undefined;
}

function range(data: DiagnosticData | undefined): PixelRange | undefined {
  if (data === undefined) return undefined;

  const minPx = number(data, "minPx");
  const maxPx = number(data, "maxPx");
  return minPx === undefined && maxPx === undefined ? undefined : { minPx, maxPx };
}

function rangeDescription(value: PixelRange): string {
  if (value.minPx !== undefined && value.maxPx !== undefined) {
    return `${pixels(value.minPx)}–${pixels(value.maxPx)}`;
  }
  if (value.minPx !== undefined) return `at least ${pixels(value.minPx)}`;
  return `at most ${pixels(value.maxPx as number)}`;
}

function rangeViolation(
  label: string,
  value: number | undefined,
  allowed: PixelRange | undefined,
): string | undefined {
  if (value === undefined || allowed === undefined) return undefined;
  if (allowed.minPx !== undefined && value < allowed.minPx) {
    return `${label} below minimum by: ${pixels(allowed.minPx - value)}`;
  }
  if (allowed.maxPx !== undefined && value > allowed.maxPx) {
    return `${label} above maximum by: ${pixels(value - allowed.maxPx)}`;
  }
  return undefined;
}

function compact(lines: Array<string | undefined>): string[] {
  return lines.filter((line): line is string => line !== undefined);
}

function invalidRuleDiagnostic(finding: InvalidRuleFinding): string[] {
  return [
    `rule ${finding.ruleIndex} invalid rule:`,
    `field: ${finding.fieldPath}`,
    `reason: ${finding.reason}`,
    `message: ${finding.message}`,
  ];
}

function elementDiagnostic(finding: ElementFinding): string[] {
  const expected = finding.expected as DiagnosticData;
  const actual = finding.actual as DiagnosticData;
  const visible = boolean(actual, "hidden");
  const heading = finding.code.replace("-element", " element");

  return compact([
    `${heading}:`,
    `rule ${finding.ruleIndex}`,
    `${finding.operand}: ${JSON.stringify(finding.testId)}`,
    `test ID: ${JSON.stringify(finding.testId)}`,
    number(expected, "matchCount") === undefined
      ? undefined
      : `expected matches: ${number(expected, "matchCount")}`,
    number(actual, "matchCount") === undefined
      ? undefined
      : `actual matches: ${number(actual, "matchCount")}`,
    visible === undefined ? undefined : `visible: ${!visible}`,
    pixelLine("width", number(actual, "width")),
    pixelLine("height", number(actual, "height")),
    `message: ${finding.message}`,
  ]);
}

function commonLayoutLines(finding: LayoutViolationFinding): string[] {
  return [
    `${finding.relationship} failed:`,
    `rule ${finding.ruleIndex}`,
    `subject: ${JSON.stringify(finding.subject)}`,
    `reference: ${JSON.stringify(finding.reference)}`,
  ];
}

function toleranceLines(
  expected: DiagnosticData,
  measured: number | undefined,
  excessLabel = "exceeds tolerance by",
): string[] {
  const tolerance = number(expected, "tolerancePx") ?? 0;
  return compact([
    `allowed tolerance: ${pixels(tolerance)}`,
    excessLine(excessLabel, measured, tolerance),
  ]);
}

function alignmentDiagnostic(finding: LayoutViolationFinding): string[] {
  const expected = finding.expected;
  const actual = finding.actual;
  return compact([
    ...commonLayoutLines(finding),
    typeof expected.alignment === "string"
      ? `alignment: ${expected.alignment}`
      : undefined,
    pixelLine("subject coordinate", number(actual, "subjectCoordinate")),
    pixelLine("reference coordinate", number(actual, "referenceCoordinate")),
    pixelLine("difference", number(actual, "differencePx")),
    ...toleranceLines(expected, number(actual, "differencePx")),
  ]);
}

function orderingDiagnostic(finding: LayoutViolationFinding): string[] {
  const actual = finding.actual;
  return compact([
    ...commonLayoutLines(finding),
    pixelLine("signed gap", number(actual, "signedGapPx")),
    pixelLine("boundary crossing", number(actual, "boundaryCrossingPx")),
    ...toleranceLines(finding.expected, number(actual, "boundaryCrossingPx")),
  ]);
}

function gapDiagnostic(finding: LayoutViolationFinding): string[] {
  const measured = number(finding.actual, "signedGapPx");
  const allowed = range(object(finding.expected, "gap"));
  return compact([
    ...commonLayoutLines(finding),
    pixelLine("measured gap", measured),
    allowed === undefined ? undefined : `allowed gap: ${rangeDescription(allowed)}`,
    rangeViolation("", measured, allowed)?.trimStart(),
  ]);
}

function overlapDiagnostic(finding: LayoutViolationFinding): string[] {
  const horizontal = number(finding.actual, "horizontalPx");
  const vertical = number(finding.actual, "verticalPx");
  const horizontalRange = range(object(finding.expected, "horizontal"));
  const verticalRange = range(object(finding.expected, "vertical"));
  const overlap = boolean(finding.expected, "overlap");

  return compact([
    ...commonLayoutLines(finding),
    pixelLine("horizontal overlap", horizontal),
    horizontalRange === undefined
      ? undefined
      : `allowed horizontal overlap: ${rangeDescription(horizontalRange)}`,
    rangeViolation("horizontal", horizontal, horizontalRange),
    pixelLine("vertical overlap", vertical),
    verticalRange === undefined
      ? undefined
      : `allowed vertical overlap: ${rangeDescription(verticalRange)}`,
    rangeViolation("vertical", vertical, verticalRange),
    overlap === true ? "required overlap: positive on both axes" : undefined,
    overlap === false ? "allowed overlap: none" : undefined,
  ]);
}

function containmentDiagnostic(finding: LayoutViolationFinding): string[] {
  const actual = finding.actual;
  const tolerance = number(finding.expected, "tolerancePx") ?? 0;
  const sides = ["left", "right", "top", "bottom"] as const;
  const overflows = sides.map((side) => number(actual, `${side}Px`));
  const maximum = Math.max(...overflows.filter((value) => value !== undefined));

  return compact([
    ...commonLayoutLines(finding),
    ...sides.map((side) => pixelLine(`${side} overflow`, number(actual, `${side}Px`))),
    pixelLine("horizontal intersection", number(actual, "horizontalPx")),
    pixelLine("vertical intersection", number(actual, "verticalPx")),
    finding.expected.positiveIntersection === true
      ? "required intersection: positive on both axes"
      : undefined,
    `allowed tolerance: ${pixels(tolerance)}`,
    Number.isFinite(maximum) ? `maximum overflow: ${pixels(maximum)}` : undefined,
    Number.isFinite(maximum)
      ? excessLine("exceeds tolerance by", maximum, tolerance)
      : undefined,
    ...sides.map((side) =>
      excessLine(
        `${side} exceeds tolerance by`,
        number(actual, `${side}Px`),
        tolerance,
      ),
    ),
  ]);
}

function sizeDiagnostic(finding: LayoutViolationFinding): string[] {
  const actual = finding.actual;
  const tolerance = number(finding.expected, "tolerancePx") ?? 0;
  const widthDifference = number(actual, "widthDifferencePx");
  const heightDifference = number(actual, "heightDifferencePx");
  const comparesWidth =
    finding.relationship === "sameWidth" || finding.relationship === "sameSize";
  const comparesHeight =
    finding.relationship === "sameHeight" || finding.relationship === "sameSize";

  return compact([
    ...commonLayoutLines(finding),
    comparesWidth
      ? pixelLine("subject width", number(actual, "subjectWidthPx"))
      : undefined,
    comparesWidth
      ? pixelLine("reference width", number(actual, "referenceWidthPx"))
      : undefined,
    comparesWidth
      ? pixelLine(
          comparesHeight ? "width difference" : "difference",
          widthDifference,
        )
      : undefined,
    comparesHeight
      ? pixelLine("subject height", number(actual, "subjectHeightPx"))
      : undefined,
    comparesHeight
      ? pixelLine("reference height", number(actual, "referenceHeightPx"))
      : undefined,
    comparesHeight
      ? pixelLine(
          comparesWidth ? "height difference" : "difference",
          heightDifference,
        )
      : undefined,
    `allowed tolerance: ${pixels(tolerance)}`,
    comparesWidth
      ? excessLine(
          comparesHeight ? "width exceeds tolerance by" : "exceeds tolerance by",
          widthDifference,
          tolerance,
        )
      : undefined,
    comparesHeight
      ? excessLine(
          comparesWidth ? "height exceeds tolerance by" : "exceeds tolerance by",
          heightDifference,
          tolerance,
        )
      : undefined,
  ]);
}

function layoutDiagnostic(finding: LayoutViolationFinding): string[] {
  switch (finding.code) {
    case "alignment-mismatch":
      return alignmentDiagnostic(finding);
    case "ordering-violation":
      return orderingDiagnostic(finding);
    case "gap-out-of-range":
      return gapDiagnostic(finding);
    case "missing-overlap":
    case "overlap-out-of-range":
      return overlapDiagnostic(finding);
    case "containment-overflow":
      return containmentDiagnostic(finding);
    case "size-mismatch":
      return sizeDiagnostic(finding);
  }
}

function findingDiagnostic(finding: LayoutFinding): string {
  switch (finding.category) {
    case "invalid-rule":
      return invalidRuleDiagnostic(finding).join("\n");
    case "element-resolution":
    case "element-visibility":
      return elementDiagnostic(finding).join("\n");
    case "layout":
      return [...layoutDiagnostic(finding), `message: ${finding.message}`].join("\n");
  }
}

function reportSummary(report: LayoutReport): string {
  return `Layout assertion failed: ${report.rules.failed} failed, ${report.rules.skipped} skipped`;
}

export class LayoutAssertionError extends Error {
  readonly report: LayoutReport;

  constructor(report: LayoutReport) {
    const details = report.findings.map(findingDiagnostic).join("\n\n");
    super(`${reportSummary(report)}${details.length > 0 ? `\n\n${details}` : ""}`);
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
