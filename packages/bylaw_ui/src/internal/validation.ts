import type {
  InvalidRuleCode,
  InvalidRuleFinding,
  LayoutRule,
} from "../types.js";

const ruleKinds = new Set([
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
  "width",
  "height",
  "inViewport",
]);

const alignments = new Set([
  "left",
  "right",
  "top",
  "bottom",
  "centerX",
  "centerY",
]);

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function finding(
  ruleIndex: number,
  code: InvalidRuleCode,
  fieldPath: string,
  reason: string,
): InvalidRuleFinding {
  return {
    category: "invalid-rule",
    code,
    ruleIndex,
    message: `Rule ${ruleIndex} has an invalid ${fieldPath}: ${reason}`,
    fieldPath,
    reason,
  };
}

function validateTestId(
  rule: UnknownRecord,
  field: "subject" | "reference" | "target",
  ruleIndex: number,
): InvalidRuleFinding[] {
  if (!(field in rule) || rule[field] === undefined) {
    return [finding(ruleIndex, "missing-field", field, "is required")];
  }

  if (typeof rule[field] !== "string") {
    return [finding(ruleIndex, "invalid-type", field, "must be a string")];
  }

  if (rule[field].length === 0) {
    return [finding(ruleIndex, "invalid-value", field, "must not be empty")];
  }

  return [];
}

function validateUnaryRule(
  rule: UnknownRecord,
  kind: "width" | "height" | "inViewport",
  ruleIndex: number,
): InvalidRuleFinding[] {
  const findings: InvalidRuleFinding[] = [];
  const allowed = new Set(
    kind === "inViewport" ? ["kind", "target"] : ["kind", "target", "range"],
  );

  for (const field of Object.keys(rule)) {
    if (!allowed.has(field)) {
      findings.push(
        finding(ruleIndex, "unknown-field", field, "is not supported"),
      );
    }
  }

  findings.push(...validateTestId(rule, "target", ruleIndex));

  if (kind !== "inViewport") {
    if (!("range" in rule) || rule.range === undefined) {
      findings.push(
        finding(ruleIndex, "missing-field", "range", "is required"),
      );
    } else {
      findings.push(...validateRange(rule.range, "range", ruleIndex, false));
    }
  }

  return findings;
}

function validateFiniteNonnegative(
  value: unknown,
  path: string,
  ruleIndex: number,
): InvalidRuleFinding[] {
  if (typeof value !== "number") {
    return [finding(ruleIndex, "invalid-type", path, "must be a number")];
  }

  if (!Number.isFinite(value) || value < 0) {
    return [
      finding(
        ruleIndex,
        "invalid-value",
        path,
        "must be a finite nonnegative number",
      ),
    ];
  }

  return [];
}

function validateRange(
  value: unknown,
  path: string,
  ruleIndex: number,
  requirePositiveMaximum: boolean,
): InvalidRuleFinding[] {
  if (!isRecord(value)) {
    return [finding(ruleIndex, "invalid-type", path, "must be an object")];
  }

  const findings: InvalidRuleFinding[] = [];
  const allowed = new Set(["minPx", "maxPx"]);

  for (const field of Object.keys(value)) {
    if (!allowed.has(field)) {
      findings.push(
        finding(ruleIndex, "unknown-field", `${path}.${field}`, "is not supported"),
      );
    }
  }

  const hasMin = value.minPx !== undefined;
  const hasMax = value.maxPx !== undefined;

  if (!hasMin && !hasMax) {
    findings.push(
      finding(
        ruleIndex,
        "invalid-value",
        path,
        "must contain minPx or maxPx",
      ),
    );
  }

  if (hasMin) {
    findings.push(
      ...validateFiniteNonnegative(value.minPx, `${path}.minPx`, ruleIndex),
    );
  }

  if (hasMax) {
    findings.push(
      ...validateFiniteNonnegative(value.maxPx, `${path}.maxPx`, ruleIndex),
    );
  }

  if (
    typeof value.minPx === "number" &&
    Number.isFinite(value.minPx) &&
    typeof value.maxPx === "number" &&
    Number.isFinite(value.maxPx) &&
    value.minPx > value.maxPx
  ) {
    findings.push(
      finding(
        ruleIndex,
        "invalid-value",
        path,
        "minPx must not exceed maxPx",
      ),
    );
  }

  if (
    requirePositiveMaximum &&
    typeof value.maxPx === "number" &&
    value.maxPx === 0
  ) {
    findings.push(
      finding(
        ruleIndex,
        "invalid-value",
        `${path}.maxPx`,
        "must be greater than zero for overlap",
      ),
    );
  }

  return findings;
}

function validateOptions(
  rule: UnknownRecord,
  kind: string,
  ruleIndex: number,
): InvalidRuleFinding[] {
  if (!("options" in rule) || rule.options === undefined) {
    return [];
  }

  if (!isRecord(rule.options)) {
    return [
      finding(ruleIndex, "invalid-type", "options", "must be an object"),
    ];
  }

  if (kind === "notOverlap") {
    return [
      finding(
        ruleIndex,
        "invalid-value",
        "options",
        "is not supported by notOverlap",
      ),
    ];
  }

  const options = rule.options;
  const findings: InvalidRuleFinding[] = [];
  const allowed =
    kind === "overlap"
      ? new Set(["horizontal", "vertical"])
      : new Set(
          ["above", "below", "leftOf", "rightOf"].includes(kind)
            ? ["tolerancePx", "gap"]
            : ["tolerancePx"],
        );

  for (const field of Object.keys(options)) {
    if (!allowed.has(field)) {
      findings.push(
        finding(
          ruleIndex,
          "unknown-field",
          `options.${field}`,
          `is not supported by ${kind}`,
        ),
      );
    }
  }

  if ("tolerancePx" in options && options.tolerancePx !== undefined) {
    findings.push(
      ...validateFiniteNonnegative(
        options.tolerancePx,
        "options.tolerancePx",
        ruleIndex,
      ),
    );
  }

  if ("gap" in options && options.gap !== undefined && allowed.has("gap")) {
    findings.push(
      ...validateRange(options.gap, "options.gap", ruleIndex, false),
    );
  }

  for (const axis of ["horizontal", "vertical"] as const) {
    if (axis in options && options[axis] !== undefined && allowed.has(axis)) {
      findings.push(
        ...validateRange(
          options[axis],
          `options.${axis}`,
          ruleIndex,
          true,
        ),
      );
    }
  }

  return findings;
}

export function validateRule(
  value: unknown,
  ruleIndex: number,
): InvalidRuleFinding[] {
  if (!isRecord(value)) {
    return [
      finding(ruleIndex, "invalid-type", "$", "rule must be an object"),
    ];
  }

  const findings: InvalidRuleFinding[] = [];
  const kind = value.kind;

  if (!("kind" in value) || kind === undefined) {
    findings.push(finding(ruleIndex, "missing-field", "kind", "is required"));
  } else if (typeof kind !== "string") {
    findings.push(
      finding(ruleIndex, "invalid-type", "kind", "must be a string"),
    );
  } else if (!ruleKinds.has(kind)) {
    findings.push(
      finding(ruleIndex, "invalid-value", "kind", "is not a supported rule kind"),
    );
  }

  if (kind === "width" || kind === "height" || kind === "inViewport") {
    findings.push(...validateUnaryRule(value, kind, ruleIndex));
    return findings;
  }

  findings.push(...validateTestId(value, "subject", ruleIndex));
  findings.push(...validateTestId(value, "reference", ruleIndex));

  const allowedTopLevel = new Set(["kind", "subject", "reference", "options"]);

  if (kind === "align") {
    allowedTopLevel.add("alignment");

    if (!("alignment" in value) || value.alignment === undefined) {
      findings.push(
        finding(ruleIndex, "missing-field", "alignment", "is required"),
      );
    } else if (typeof value.alignment !== "string") {
      findings.push(
        finding(ruleIndex, "invalid-type", "alignment", "must be a string"),
      );
    } else if (!alignments.has(value.alignment)) {
      findings.push(
        finding(
          ruleIndex,
          "invalid-value",
          "alignment",
          "is not a supported alignment",
        ),
      );
    }
  }

  for (const field of Object.keys(value)) {
    if (!allowedTopLevel.has(field)) {
      findings.push(
        finding(ruleIndex, "unknown-field", field, "is not supported"),
      );
    }
  }

  if (typeof kind === "string" && ruleKinds.has(kind)) {
    findings.push(...validateOptions(value, kind, ruleIndex));
  }

  return findings;
}

export function isValidatedRule(value: unknown): value is LayoutRule {
  return validateRule(value, 0).length === 0;
}
