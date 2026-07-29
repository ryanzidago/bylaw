import type {
  CollectionFinding,
  CollectionRule,
  ElementFinding,
  InvalidRuleFinding,
  LayoutFinding,
  LayoutReport,
  LayoutRule,
  UnaryElementFinding,
  UnaryGeometryRule,
} from "./types.js";
import { isAdapter, type Adapter } from "./adapter.js";
import {
  isInternalAdapter,
  type InternalAdapter,
  type RawElementMeasurement,
  type RawCollectionMeasurement,
} from "./internal/adapter.js";
import {
  evaluateGeometry,
  evaluateUnaryGeometry,
} from "./internal/geometry.js";
import { validateSnapshot } from "./internal/snapshot.js";
import { validatePublicSnapshot } from "./internal/public-snapshot.js";
import { validateRule } from "./internal/validation.js";

export type CheckLayoutInput = {
  adapter: Adapter | InternalAdapter;
  rules: LayoutRule[];
};

function assertInput(value: unknown): asserts value is {
  adapter: Adapter | InternalAdapter;
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

  if (!isAdapter(value.adapter) && !isInternalAdapter(value.adapter)) {
    throw new TypeError("checkLayout received an unsupported adapter");
  }
}

type SingularLayoutRule = Exclude<
  LayoutRule,
  UnaryGeometryRule | CollectionRule
>;

function isUnaryRule(rule: LayoutRule): rule is UnaryGeometryRule {
  return (
    rule.kind === "width" ||
    rule.kind === "height" ||
    rule.kind === "inViewport"
  );
}

function isCollectionRule(rule: LayoutRule): rule is CollectionRule {
  return (
    rule.kind === "everyInside" ||
    rule.kind === "equalWidths" ||
    rule.kind === "verticallyOrdered" ||
    rule.kind === "pairwiseNotOverlap"
  );
}

function binaryElementFinding(
  rule: SingularLayoutRule,
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
    target: testId,
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

function collectionElementFindings(
  rule: CollectionRule,
  ruleIndex: number,
  measurement: RawCollectionMeasurement,
): CollectionFinding[] {
  const target = rule.collection.target;
  if (measurement.matches.length === 0) {
    return [
      {
        category: "element-resolution",
        code: "empty-collection",
        ruleIndex,
        message: `Rule ${ruleIndex} collection target ${JSON.stringify(target)} matched 0 elements`,
        target,
        operand: "collection",
        expected: { minMatchCount: 1 },
        actual: { matchCount: 0 },
      },
    ];
  }

  return measurement.matches.flatMap((match, collectionIndex) => {
    if (!match.hidden && match.rect.width !== 0 && match.rect.height !== 0) {
      return [];
    }
    return [
      {
        category: "element-visibility" as const,
        code: match.hidden
          ? ("hidden-element" as const)
          : ("zero-size-element" as const),
        ruleIndex,
        message: `Rule ${ruleIndex} has ${match.hidden ? "hidden" : "zero-size"} collection target ${JSON.stringify(target)} member [${collectionIndex}]`,
        target,
        collectionIndex,
        operand: "collection" as const,
        expected: { visible: true as const, positiveSize: true as const },
        actual: {
          hidden: match.hidden,
          width: match.rect.width,
          height: match.rect.height,
        },
      },
    ];
  });
}

function overlapDepths(
  a: RawCollectionMeasurement["matches"][number]["rect"],
  b: RawCollectionMeasurement["matches"][number]["rect"],
) {
  return {
    horizontalPx: Math.max(
      0,
      Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x),
    ),
    verticalPx: Math.max(
      0,
      Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y),
    ),
  };
}

function collectionLayoutFindings(
  rule: CollectionRule,
  ruleIndex: number,
  measurement: RawCollectionMeasurement,
  container?: RawElementMeasurement,
): CollectionFinding[] {
  const target = rule.collection.target;
  const matches = measurement.matches;
  const common = {
    category: "layout" as const,
    ruleIndex,
  };

  if (rule.kind === "everyInside") {
    if (!container?.rect)
      throw new Error("Available containers must have rectangles");
    const tolerancePx = rule.options?.tolerancePx ?? 0;
    return matches.flatMap((match, collectionIndex) => {
      const memberRect = match.rect;
      const containerRect = container.rect!;
      const overlap = overlapDepths(memberRect, containerRect);
      const actual = {
        memberRect,
        containerRect,
        leftPx: Math.max(0, containerRect.x - memberRect.x),
        rightPx: Math.max(
          0,
          memberRect.x +
            memberRect.width -
            (containerRect.x + containerRect.width),
        ),
        topPx: Math.max(0, containerRect.y - memberRect.y),
        bottomPx: Math.max(
          0,
          memberRect.y +
            memberRect.height -
            (containerRect.y + containerRect.height),
        ),
        ...overlap,
      };
      const passes =
        overlap.horizontalPx > 0 &&
        overlap.verticalPx > 0 &&
        actual.leftPx <= tolerancePx &&
        actual.rightPx <= tolerancePx &&
        actual.topPx <= tolerancePx &&
        actual.bottomPx <= tolerancePx;
      return passes
        ? []
        : [
            {
              ...common,
              relationship: "everyInside" as const,
              code: "collection-containment-overflow" as const,
              message: `Rule ${ruleIndex} collection target ${JSON.stringify(target)} member [${collectionIndex}] is not inside ${JSON.stringify(rule.container)}`,
              target,
              collectionIndex,
              expected: { tolerancePx, positiveIntersection: true },
              actual,
            },
          ];
    });
  }

  if (rule.kind === "equalWidths") {
    const reference = matches[0]!;
    const tolerancePx = rule.options?.tolerancePx ?? 0;
    return matches.slice(1).flatMap((match, offset) => {
      const collectionIndex = offset + 1;
      const differencePx =
        Math.round(
          Math.abs(match.rect.width - reference.rect.width) * 1_000_000_000_000,
        ) / 1_000_000_000_000;
      return differencePx <= tolerancePx
        ? []
        : [
            {
              ...common,
              relationship: "equalWidths" as const,
              code: "collection-width-mismatch" as const,
              message: `Rule ${ruleIndex} collection target ${JSON.stringify(target)} member [${collectionIndex}] width differs`,
              target,
              collectionIndex,
              expected: { tolerancePx },
              actual: {
                referenceRect: reference.rect,
                memberRect: match.rect,
                referenceWidthPx: reference.rect.width,
                memberWidthPx: match.rect.width,
                differencePx,
              },
            },
          ];
    });
  }

  if (rule.kind === "verticallyOrdered") {
    return matches
      .slice(0, -1)
      .flatMap((subject, index): CollectionFinding[] => {
        const reference = matches[index + 1]!;
        const gapPx = reference.rect.y - (subject.rect.y + subject.rect.height);
        const pair = {
          subject: { target, collectionIndex: index },
          reference: { target, collectionIndex: index + 1 },
        };
        if (gapPx < 0) {
          return [
            {
              ...common,
              relationship: "verticallyOrdered" as const,
              ...pair,
              code: "collection-ordering-violation" as const,
              message: `Rule ${ruleIndex} collection members [${index}] and [${index + 1}] are out of order`,
              expected: {
                ...(rule.options?.gap ? { gap: rule.options.gap } : {}),
              },
              actual: {
                subjectRect: subject.rect,
                referenceRect: reference.rect,
                gapPx,
              },
            },
          ];
        }
        const gap = rule.options?.gap;
        const valid =
          gap === undefined ||
          ((gap.minPx === undefined || gapPx >= gap.minPx) &&
            (gap.maxPx === undefined || gapPx <= gap.maxPx));
        return valid
          ? []
          : [
              {
                ...common,
                relationship: "verticallyOrdered" as const,
                ...pair,
                code: "collection-gap-out-of-range" as const,
                message: `Rule ${ruleIndex} collection members [${index}] and [${index + 1}] have an invalid gap`,
                expected: { gap: gap! },
                actual: {
                  subjectRect: subject.rect,
                  referenceRect: reference.rect,
                  gapPx,
                },
              },
            ];
      });
  }

  const findings: CollectionFinding[] = [];
  for (let left = 0; left < matches.length; left += 1) {
    for (let right = left + 1; right < matches.length; right += 1) {
      const subject = matches[left]!;
      const reference = matches[right]!;
      const depths = overlapDepths(subject.rect, reference.rect);
      if (depths.horizontalPx > 0 && depths.verticalPx > 0) {
        findings.push({
          ...common,
          relationship: "pairwiseNotOverlap",
          code: "collection-overlap",
          message: `Rule ${ruleIndex} collection members [${left}] and [${right}] overlap`,
          subject: { target, collectionIndex: left },
          reference: { target, collectionIndex: right },
          expected: { overlap: false },
          actual: {
            subjectRect: subject.rect,
            referenceRect: reference.rect,
            ...depths,
          },
        });
      }
    }
  }
  return findings;
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

  const requestedTargets = validRules.flatMap(({ rule }) => {
    if (isUnaryRule(rule)) return [rule.target];
    if (isCollectionRule(rule)) {
      return rule.kind === "everyInside"
        ? [rule.collection, rule.container]
        : [rule.collection];
    }
    return [rule.subject, rule.reference];
  });
  const uniqueTargets = requestedTargets.filter(
    (target, index) =>
      requestedTargets.findIndex((candidate) =>
        typeof target === "string" && typeof candidate === "string"
          ? target === candidate
          : typeof target !== "string" &&
            typeof candidate !== "string" &&
            target.target === candidate.target,
      ) === index,
  );
  const measured = isAdapter(input.adapter)
    ? await input.adapter.measure(uniqueTargets)
    : await input.adapter.measure(
        uniqueTargets as unknown as readonly string[],
      );
  const snapshot = isAdapter(input.adapter)
    ? validatePublicSnapshot(measured, uniqueTargets)
    : validateSnapshot(measured, uniqueTargets);
  const byRequest = new Map(
    snapshot.elements.map((measurement) => [
      `${"matches" in measurement ? "collection" : "singular"}:${measurement.testId}`,
      measurement,
    ]),
  );
  const skippedRuleIndexes = new Set<number>();
  let passed = 0;

  for (const { rule, ruleIndex } of validRules) {
    if (isCollectionRule(rule)) {
      const collectionMeasurement = byRequest.get(
        `collection:${rule.collection.target}`,
      );
      if (!collectionMeasurement || !("matches" in collectionMeasurement)) {
        throw new Error(
          "Validated snapshot must contain the requested collection",
        );
      }
      const memberFindings = collectionElementFindings(
        rule,
        ruleIndex,
        collectionMeasurement,
      );
      let container: RawElementMeasurement | undefined;
      let containerUnavailable = false;
      if (rule.kind === "everyInside") {
        const measuredContainer = byRequest.get(`singular:${rule.container}`);
        if (!measuredContainer || "matches" in measuredContainer) {
          throw new Error(
            "Validated snapshot must contain the requested container",
          );
        }
        container = measuredContainer;
        const containerFinding = unaryElementFinding(
          { kind: "inViewport", target: rule.container },
          ruleIndex,
          container,
        );
        if (containerFinding) {
          findings.push(containerFinding);
          containerUnavailable = true;
        }
      }
      if (memberFindings.length > 0 || containerUnavailable) {
        findings.push(...memberFindings);
        skippedRuleIndexes.add(ruleIndex);
        continue;
      }
      const layoutFindings = collectionLayoutFindings(
        rule,
        ruleIndex,
        collectionMeasurement,
        container,
      );
      if (layoutFindings.length > 0) {
        findings.push(...layoutFindings);
        failedRuleIndexes.add(ruleIndex);
      } else {
        passed += 1;
      }
      continue;
    }

    if (isUnaryRule(rule)) {
      const target = byRequest.get(`singular:${rule.target}`);

      if (!target || "matches" in target) {
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

    const subject = byRequest.get(`singular:${rule.subject}`);
    const reference = byRequest.get(`singular:${rule.reference}`);

    if (
      !subject ||
      !reference ||
      "matches" in subject ||
      "matches" in reference
    ) {
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
