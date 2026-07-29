import { expect } from "bun:test";

import {
  checkLayout,
  type LayoutFinding,
  type LayoutRule,
  type CollectionRule,
  type UnaryGeometryRule,
} from "bylaw-ui";
import {
  createInternalAdapter,
  type RawElementMeasurement,
  type Rectangle,
} from "../src/internal/adapter";

export function rect(x = 0, y = 0, width = 10, height = 10): Rectangle {
  return { x, y, width, height };
}

export function visible(
  testId: string,
  rectangle: Rectangle,
): RawElementMeasurement {
  return { testId, count: 1, hidden: false, rect: rectangle };
}

export function hidden(
  testId: string,
  rectangle = rect(),
): RawElementMeasurement {
  return { testId, count: 1, hidden: true, rect: rectangle };
}

export function unresolved(
  testId: string,
  count: number,
): RawElementMeasurement {
  return { testId, count, hidden: null, rect: null };
}

export function fixtureAdapter(
  measurements: Record<string, RawElementMeasurement>,
  onMeasure?: (testIds: readonly string[]) => void,
) {
  return createInternalAdapter(async (rawTargets) => {
    const targets = rawTargets as unknown as readonly (
      string | import("bylaw-ui").CollectionTarget
    )[];
    onMeasure?.(
      targets.map((target) =>
        typeof target === "string" ? target : target.target,
      ),
    );

    return {
      viewport: { width: 1280, height: 720 },
      elements: targets.map((requested) => {
        const testId =
          typeof requested === "string" ? requested : requested.target;
        return typeof requested === "string"
          ? (measurements[testId] ?? unresolved(testId, 0))
          : {
              testId,
              count: 0,
              hidden: null,
              rect: null,
              matches: [],
            };
      }),
    };
  });
}

type BinaryLayoutRule = Exclude<LayoutRule, UnaryGeometryRule | CollectionRule>;

export async function checkRule(
  rule: BinaryLayoutRule,
  subjectRect: Rectangle,
  referenceRect: Rectangle,
) {
  const measurements =
    rule.subject === rule.reference
      ? { [rule.subject]: visible(rule.subject, subjectRect) }
      : {
          [rule.subject]: visible(rule.subject, subjectRect),
          [rule.reference]: visible(rule.reference, referenceRect),
        };

  return checkLayout({
    adapter: fixtureAdapter(measurements),
    rules: [rule],
  });
}

export async function expectPass(
  rule: BinaryLayoutRule,
  subjectRect: Rectangle,
  referenceRect: Rectangle,
) {
  const report = await checkRule(rule, subjectRect, referenceRect);
  expect(report.passed).toBe(true);
  expect(report.rules).toEqual({ total: 1, passed: 1, failed: 0, skipped: 0 });
  expect(report.findings).toEqual([]);
}

export async function expectFailure(
  rule: BinaryLayoutRule,
  subjectRect: Rectangle,
  referenceRect: Rectangle,
  code: LayoutFinding["code"],
) {
  const report = await checkRule(rule, subjectRect, referenceRect);
  expect(report.passed).toBe(false);
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 1, skipped: 0 });
  expect(report.findings[0]?.code).toBe(code);
  return report.findings[0]!;
}
