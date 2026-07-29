import type {
  BinaryLayoutViolationFinding,
  CollectionFinding,
  ElementFinding,
  HeightLayoutViolationFinding,
  InvalidRuleFinding,
  JsonValue,
  LayoutFinding,
  LayoutReport,
  LayoutViolationFinding,
  ViewportLayoutViolationFinding,
  WidthLayoutViolationFinding,
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

function object(data: DiagnosticData, key: string): DiagnosticData | undefined {
  const value = data[key];
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value
    : undefined;
}

function pixels(value: number): string {
  return `${Object.is(value, -0) ? 0 : value}px`;
}

function decimalParts(value: number): { coefficient: bigint; scale: number } {
  const match = value
    .toString()
    .match(/^(-?)(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$/i);

  if (match === null) {
    throw new TypeError(`Cannot format non-finite pixel value: ${value}`);
  }

  const fraction = match[3] ?? "";
  const exponent = Number(match[4] ?? 0);
  const sign = match[1] === "-" ? -1n : 1n;
  let coefficient = sign * BigInt(`${match[2]}${fraction}`);
  let scale = fraction.length - exponent;

  if (scale < 0) {
    coefficient *= 10n ** BigInt(-scale);
    scale = 0;
  }

  return { coefficient, scale };
}

function calculatedPixels(minuend: number, subtrahend: number): string {
  const left = decimalParts(minuend);
  const right = decimalParts(subtrahend);
  const scale = Math.max(left.scale, right.scale);
  const leftCoefficient = left.coefficient * 10n ** BigInt(scale - left.scale);
  const rightCoefficient =
    right.coefficient * 10n ** BigInt(scale - right.scale);
  const difference = leftCoefficient - rightCoefficient;
  const sign = difference < 0n ? "-" : "";
  const digits = (difference < 0n ? -difference : difference)
    .toString()
    .padStart(scale + 1, "0");

  if (scale === 0) return `${sign}${digits}px`;

  const integer = digits.slice(0, -scale);
  const fraction = digits.slice(-scale).replace(/0+$/, "");
  return fraction.length === 0
    ? `${sign}${integer}px`
    : `${sign}${integer}.${fraction}px`;
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
    ? `${label}: ${calculatedPixels(value, tolerance)}`
    : undefined;
}

function range(data: DiagnosticData | undefined): PixelRange | undefined {
  if (data === undefined) return undefined;

  const minPx = number(data, "minPx");
  const maxPx = number(data, "maxPx");
  return minPx === undefined && maxPx === undefined
    ? undefined
    : {
        ...(minPx === undefined ? {} : { minPx }),
        ...(maxPx === undefined ? {} : { maxPx }),
      };
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
    return `${label} below minimum by: ${calculatedPixels(allowed.minPx, value)}`;
  }
  if (allowed.maxPx !== undefined && value > allowed.maxPx) {
    return `${label} above maximum by: ${calculatedPixels(value, allowed.maxPx)}`;
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

function commonLayoutLines(finding: BinaryLayoutViolationFinding): string[] {
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

function alignmentDiagnostic(finding: BinaryLayoutViolationFinding): string[] {
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

function orderingDiagnostic(finding: BinaryLayoutViolationFinding): string[] {
  const actual = finding.actual;
  return compact([
    ...commonLayoutLines(finding),
    pixelLine("signed gap", number(actual, "signedGapPx")),
    pixelLine("boundary crossing", number(actual, "boundaryCrossingPx")),
    ...toleranceLines(finding.expected, number(actual, "boundaryCrossingPx")),
  ]);
}

function gapDiagnostic(finding: BinaryLayoutViolationFinding): string[] {
  const measured = number(finding.actual, "signedGapPx");
  const allowed = range(object(finding.expected, "gap"));
  return compact([
    ...commonLayoutLines(finding),
    pixelLine("measured gap", measured),
    allowed === undefined
      ? undefined
      : `allowed gap: ${rangeDescription(allowed)}`,
    rangeViolation("", measured, allowed)?.trimStart(),
  ]);
}

function overlapDiagnostic(finding: BinaryLayoutViolationFinding): string[] {
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

function containmentDiagnostic(
  finding: BinaryLayoutViolationFinding,
): string[] {
  const actual = finding.actual;
  const tolerance = number(finding.expected, "tolerancePx") ?? 0;
  const sides = ["left", "right", "top", "bottom"] as const;
  const overflows = sides.map((side) => number(actual, `${side}Px`));
  const maximum = Math.max(...overflows.filter((value) => value !== undefined));

  return compact([
    ...commonLayoutLines(finding),
    ...sides.map((side) =>
      pixelLine(`${side} overflow`, number(actual, `${side}Px`)),
    ),
    pixelLine("horizontal intersection", number(actual, "horizontalPx")),
    pixelLine("vertical intersection", number(actual, "verticalPx")),
    finding.expected.positiveIntersection === true
      ? "required intersection: positive on both axes"
      : undefined,
    `allowed tolerance: ${pixels(tolerance)}`,
    Number.isFinite(maximum)
      ? `maximum overflow: ${pixels(maximum)}`
      : undefined,
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

function sizeDiagnostic(finding: BinaryLayoutViolationFinding): string[] {
  const actual = finding.actual;
  const tolerance = number(finding.expected, "tolerancePx") ?? 0;
  const widthDifference = number(actual, "widthDifferencePx");
  const heightDifference = number(actual, "heightDifferencePx");
  const comparesWidth =
    finding.relationship === "sameWidth" || finding.relationship === "sameSize";
  const comparesHeight =
    finding.relationship === "sameHeight" ||
    finding.relationship === "sameSize";

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
          comparesHeight
            ? "width exceeds tolerance by"
            : "exceeds tolerance by",
          widthDifference,
          tolerance,
        )
      : undefined,
    comparesHeight
      ? excessLine(
          comparesWidth
            ? "height exceeds tolerance by"
            : "exceeds tolerance by",
          heightDifference,
          tolerance,
        )
      : undefined,
  ]);
}

function dimensionDiagnostic(
  finding: WidthLayoutViolationFinding | HeightLayoutViolationFinding,
): string[] {
  const measured =
    finding.relationship === "width"
      ? finding.actual.widthPx
      : finding.actual.heightPx;

  return compact([
    `${finding.relationship} failed:`,
    `rule ${finding.ruleIndex}`,
    `target: ${JSON.stringify(finding.target)}`,
    pixelLine(`measured ${finding.relationship}`, measured),
    `allowed ${finding.relationship}: ${rangeDescription(finding.expected.range)}`,
    rangeViolation(finding.relationship, measured, finding.expected.range),
  ]);
}

function viewportDiagnostic(finding: ViewportLayoutViolationFinding): string[] {
  const target = finding.actual.target;
  const viewport = finding.expected.viewport;

  return [
    `${finding.relationship} failed:`,
    `rule ${finding.ruleIndex}`,
    `target: ${JSON.stringify(finding.target)}`,
    `target edges: left ${pixels(target.leftPx)}, top ${pixels(target.topPx)}, right ${pixels(target.rightPx)}, bottom ${pixels(target.bottomPx)}`,
    `viewport edges: left ${pixels(viewport.leftPx)}, top ${pixels(viewport.topPx)}, right ${pixels(viewport.rightPx)}, bottom ${pixels(viewport.bottomPx)}`,
  ];
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
    case "dimension-out-of-range":
      return dimensionDiagnostic(finding);
    case "viewport-overflow":
      return viewportDiagnostic(finding);
  }
}

function collectionDiagnostic(finding: CollectionFinding): string[] {
  if (finding.code === "empty-collection") {
    return [
      `collection target ${JSON.stringify(finding.target)} matched 0 elements`,
      `rule ${finding.ruleIndex}`,
      `message: ${finding.message}`,
    ];
  }

  if (
    finding.code === "hidden-element" ||
    finding.code === "zero-size-element"
  ) {
    return [
      `target ${JSON.stringify(finding.target)} member [${finding.collectionIndex}]`,
      `message: ${finding.message}`,
    ];
  }

  const identity =
    "collectionIndex" in finding
      ? [
          `target ${JSON.stringify(finding.target)} member [${finding.collectionIndex}]`,
        ]
      : [
          `target ${JSON.stringify(finding.subject.target)} member [${finding.subject.collectionIndex}]`,
          `target ${JSON.stringify(finding.reference.target)} member [${finding.reference.collectionIndex}]`,
        ];
  if (finding.code === "collection-width-mismatch") {
    return [
      ...identity,
      `expected width difference <= ${pixels(number(finding.expected, "tolerancePx") ?? 0)}`,
      `actual difference ${pixels(number(finding.actual, "differencePx") ?? 0)}`,
      `message: ${finding.message}`,
    ];
  }
  return [...identity, `message: ${finding.message}`];
}

function findingDiagnostic(finding: LayoutFinding): string {
  switch (finding.category) {
    case "invalid-rule":
      return invalidRuleDiagnostic(finding).join("\n");
    case "element-resolution":
    case "element-visibility":
      return (
        finding.code === "empty-collection" ||
        ("operand" in finding && finding.operand === "collection")
          ? collectionDiagnostic(finding as CollectionFinding)
          : elementDiagnostic(finding)
      ).join("\n");
    case "layout":
      return (
        finding.code.startsWith("collection-")
          ? collectionDiagnostic(finding as CollectionFinding)
          : [
              ...layoutDiagnostic(finding as LayoutViolationFinding),
              `message: ${finding.message}`,
            ]
      ).join("\n");
  }
}

function reportSummary(report: LayoutReport): string {
  const failedLabel =
    report.rules.failed === 1 ? "failed rule" : "failed rules";
  const skippedLabel =
    report.rules.skipped === 1 ? "skipped rule" : "skipped rules";
  return `Layout assertion failed: ${report.rules.failed} failed, ${report.rules.skipped} skipped (${report.rules.failed} ${failedLabel}, ${report.rules.skipped} ${skippedLabel})`;
}

export class LayoutAssertionError extends Error {
  readonly report: LayoutReport;

  constructor(report: LayoutReport) {
    const details = report.findings.map(findingDiagnostic).join("\n\n");
    super(
      `${reportSummary(report)}${details.length > 0 ? `\n\n${details}` : ""}`,
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
