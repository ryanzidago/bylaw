import type {
  ElementFinding,
  InvalidRuleFinding,
  LayoutFinding,
  LayoutReport,
  LayoutRule,
  UnaryElementFinding,
  UnaryGeometryRule,
} from "./types.js";
import {
  isInternalAdapter,
  type InternalAdapter,
  type RawElementMeasurement,
} from "./internal/adapter.js";
import {
  evaluateGeometry,
  evaluateUnaryGeometry,
} from "./internal/geometry.js";
import { validateSnapshot } from "./internal/snapshot.js";
import { validateRule } from "./internal/validation.js";

export type CheckLayoutInput = {
  adapter: InternalAdapter;
  rules: LayoutRule[];
};

function assertInput(value: unknown): asserts value is {
  adapter: InternalAdapter;
  rules: unknown[];
} {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError("checkLayout expects an object");
  }

  if (!("rules" in value)) {
    throw new TypeError("checkLayout requires rules");
  }

  if (!Array.isArray(value.rules)) {
    throw new TypeError("checkLayout rules must be an array");
  }

  if (!("adapter" in value)) {
    throw new TypeError("checkLayout requires an adapter");
  }

  if (!isInternalAdapter(value.adapter)) {
    throw new TypeError("checkLayout received an unsupported adapter");
  }
}

type BinaryLayoutRule = Exclude<LayoutRule, UnaryGeometryRule>;

function isUnaryRule(rule: LayoutRule): rule is UnaryGeometryRule {
  return (
    rule.kind === "width" ||
    rule.kind === "height" ||
    rule.kind === "inViewport"
  );
}

function binaryElementFinding(
  rule: BinaryLayoutRule,
  ruleIndex: number,
  operand: "subject" | "reference",
  measurement: RawElementMeasurement,
): ElementFinding | null {
  const testId = rule[operand];
  const common = {
    ruleIndex,
    subject: rule.subject,
    reference: rule.reference,
    operand,
    testId,
  };

  if (measurement.count === 0) {
    return {
      ...common,
      category: "element-resolution",
      code: "missing-element",
      message: `Rule ${ruleIndex} cannot resolve ${operand} ${JSON.stringify(testId)}`,
      expected: { matchCount: 1 },
      actual: { matchCount: 0 },
    };
  }

  if (measurement.count > 1) {
    return {
      ...common,
      category: "element-resolution",
      code: "duplicate-element",
      message: `Rule ${ruleIndex} resolves ${operand} ${JSON.stringify(testId)} more than once`,
      expected: { matchCount: 1 },
      actual: { matchCount: measurement.count },
    };
  }

  if (measurement.rect === null || measurement.hidden === null) {
    throw new Error(
      "Validated resolved measurements must contain element state",
    );
  }

  if (measurement.hidden) {
    return {
      ...common,
      category: "element-visibility",
      code: "hidden-element",
      message: `Rule ${ruleIndex} has hidden ${operand} ${JSON.stringify(testId)}`,
      expected: { visible: true, positiveSize: true },
      actual: {
        hidden: true,
        width: measurement.rect.width,
        height: measurement.rect.height,
      },
    };
  }

  if (measurement.rect.width === 0 || measurement.rect.height === 0) {
    return {
      ...common,
      category: "element-visibility",
      code: "zero-size-element",
      message: `Rule ${ruleIndex} has zero-size ${operand} ${JSON.stringify(testId)}`,
      expected: { visible: true, positiveSize: true },
      actual: {
        hidden: false,
        width: measurement.rect.width,
        height: measurement.rect.height,
      },
    };
  }

  return null;
}

function unaryElementFinding(
  rule: UnaryGeometryRule,
  ruleIndex: number,
  measurement: RawElementMeasurement,
): UnaryElementFinding | null {
  const common = {
    ruleIndex,
    target: rule.target,
    operand: "target" as const,
    testId: rule.target,
  };

  if (measurement.count === 0) {
    return {
      ...common,
      category: "element-resolution",
      code: "missing-element",
      message: `Rule ${ruleIndex} cannot resolve target ${JSON.stringify(rule.target)}`,
      expected: { matchCount: 1 },
      actual: { matchCount: 0 },
    };
  }

  if (measurement.count > 1) {
    return {
      ...common,
      category: "element-resolution",
      code: "duplicate-element",
      message: `Rule ${ruleIndex} resolves target ${JSON.stringify(rule.target)} more than once`,
      expected: { matchCount: 1 },
      actual: { matchCount: measurement.count },
    };
  }

  if (measurement.rect === null || measurement.hidden === null) {
    throw new Error(
      "Validated resolved measurements must contain element state",
    );
  }

  if (measurement.hidden) {
    return {
      ...common,
      category: "element-visibility",
      code: "hidden-element",
      message: `Rule ${ruleIndex} has hidden target ${JSON.stringify(rule.target)}`,
      expected: { visible: true, positiveSize: true },
      actual: { hidden: true },
    };
  }

  if (measurement.rect.width === 0 || measurement.rect.height === 0) {
    return {
      ...common,
      category: "element-visibility",
      code: "zero-size-element",
      message: `Rule ${ruleIndex} has zero-size target ${JSON.stringify(rule.target)}`,
      expected: { visible: true, positiveSize: true },
      actual: {
        hidden: false,
        width: measurement.rect.width,
        height: measurement.rect.height,
      },
    };
  }

  return null;
}

export async function checkLayout(
  input: CheckLayoutInput,
): Promise<LayoutReport>;
export async function checkLayout(input: unknown): Promise<LayoutReport> {
  assertInput(input);

  const findings: LayoutFinding[] = [];
  const validRules: Array<{ rule: LayoutRule; ruleIndex: number }> = [];
  const failedRuleIndexes = new Set<number>();

  input.rules.forEach((value, ruleIndex) => {
    const invalidFindings: InvalidRuleFinding[] = validateRule(
      value,
      ruleIndex,
    );

    if (invalidFindings.length > 0) {
      findings.push(...invalidFindings);
      failedRuleIndexes.add(ruleIndex);
    } else {
      validRules.push({ rule: value as LayoutRule, ruleIndex });
    }
  });

  if (validRules.length === 0) {
    const failed = failedRuleIndexes.size;
    return {
      passed: failed === 0,
      rules: {
        total: input.rules.length,
        passed: 0,
        failed,
        skipped: 0,
      },
      findings,
    };
  }

  const testIds = [
    ...new Set(
      validRules.flatMap(({ rule }) =>
        isUnaryRule(rule) ? [rule.target] : [rule.subject, rule.reference],
      ),
    ),
  ];
  const snapshot = validateSnapshot(
    await input.adapter.measure(testIds),
    testIds,
  );
  const byTestId = new Map(
    snapshot.elements.map((measurement) => [measurement.testId, measurement]),
  );
  const skippedRuleIndexes = new Set<number>();
  let passed = 0;

  for (const { rule, ruleIndex } of validRules) {
    if (isUnaryRule(rule)) {
      const target = byTestId.get(rule.target);

      if (!target) {
        throw new Error(
          "Validated snapshot must contain every requested test ID",
        );
      }

      const targetFinding = unaryElementFinding(rule, ruleIndex, target);

      if (targetFinding !== null) {
        findings.push(targetFinding);
        skippedRuleIndexes.add(ruleIndex);
        continue;
      }

      if (target.rect === null) {
        throw new Error("Available measurements must contain rectangles");
      }

      const layoutFindings = evaluateUnaryGeometry(
        rule,
        ruleIndex,
        target.rect,
        snapshot.viewport,
      );

      if (layoutFindings.length > 0) {
        findings.push(...layoutFindings);
        failedRuleIndexes.add(ruleIndex);
      } else {
        passed += 1;
      }

      continue;
    }

    const subject = byTestId.get(rule.subject);
    const reference = byTestId.get(rule.reference);

    if (!subject || !reference) {
      throw new Error(
        "Validated snapshot must contain every requested test ID",
      );
    }

    const elementFindings = [
      binaryElementFinding(rule, ruleIndex, "subject", subject),
      ...(rule.subject === rule.reference
        ? []
        : [binaryElementFinding(rule, ruleIndex, "reference", reference)]),
    ].filter((value): value is ElementFinding => value !== null);

    if (elementFindings.length > 0) {
      findings.push(...elementFindings);
      skippedRuleIndexes.add(ruleIndex);
      continue;
    }

    if (subject.rect === null || reference.rect === null) {
      throw new Error("Available measurements must contain rectangles");
    }

    const layoutFindings = evaluateGeometry(
      rule,
      ruleIndex,
      subject.rect,
      reference.rect,
    );

    if (layoutFindings.length > 0) {
      findings.push(...layoutFindings);
      failedRuleIndexes.add(ruleIndex);
    } else {
      passed += 1;
    }
  }

  const failed = failedRuleIndexes.size;
  const skipped = skippedRuleIndexes.size;

  return {
    passed: findings.length === 0,
    rules: {
      total: input.rules.length,
      passed,
      failed,
      skipped,
    },
    findings,
  };
}
