import { expect, test } from "bun:test";

import {
  above,
  align,
  below,
  inside,
  leftOf,
  notOverlap,
  overlap,
  rightOf,
  sameHeight,
  sameSize,
  sameWidth,
  type LayoutRule,
  type UnaryGeometryRule,
} from "bylaw-ui";
import { evaluateGeometry } from "../src/internal/geometry";
import { rect } from "./support";

type Rectangle = ReturnType<typeof rect>;
type BinaryLayoutRule = Exclude<LayoutRule, UnaryGeometryRule>;

function passes(rule: BinaryLayoutRule, subject: Rectangle, reference: Rectangle) {
  return evaluateGeometry(rule, 0, subject, reference).length === 0;
}

function translate(rectangle: Rectangle, x: number, y: number): Rectangle {
  return { ...rectangle, x: rectangle.x + x, y: rectangle.y + y };
}

function scale(rectangle: Rectangle, factor: number): Rectangle {
  return {
    x: rectangle.x * factor,
    y: rectangle.y * factor,
    width: rectangle.width * factor,
    height: rectangle.height * factor,
  };
}

let seed = 0x163;
function random() {
  seed = (seed * 1_664_525 + 1_013_904_223) >>> 0;
  return seed / 2 ** 32;
}

function randomRectangle(): Rectangle {
  return rect(
    random() * 2_000 - 1_000,
    random() * 2_000 - 1_000,
    random() * 100 + 0.01,
    random() * 100 + 0.01,
  );
}

const translations: Array<[string, BinaryLayoutRule]> = [
  ["alignment is unchanged when both rectangles are translated equally", align("a", "b", "centerX", { tolerancePx: 4 })],
  ["ordering is unchanged when both rectangles are translated equally", leftOf("a", "b", { tolerancePx: 4, gap: { minPx: 1, maxPx: 100 } })],
  ["overlap is unchanged when both rectangles are translated equally", overlap("a", "b", { horizontal: { minPx: 1, maxPx: 100 } })],
  ["containment is unchanged when both rectangles are translated equally", inside("a", "b", { tolerancePx: 4 })],
  ["size comparison is unchanged when both rectangles are translated equally", sameSize("a", "b", { tolerancePx: 4 })],
];

for (const [name, rule] of translations) {
  test(name, () => {
    for (let index = 0; index < 200; index += 1) {
      const subject = randomRectangle();
      const reference = randomRectangle();
      const x = random() * 1_000 - 500;
      const y = random() * 1_000 - 500;
      expect(
        passes(rule, translate(subject, x, y), translate(reference, x, y)),
      ).toBe(passes(rule, subject, reference));
    }
  });
}

const symmetric: Array<[string, BinaryLayoutRule]> = [
  ["alignment is symmetric when subject and reference are swapped", align("a", "b", "centerY", { tolerancePx: 3 })],
  ["overlap is symmetric when subject and reference are swapped", overlap("a", "b", { horizontal: { minPx: 2 }, vertical: { maxPx: 30 } })],
  ["notOverlap is symmetric when subject and reference are swapped", notOverlap("a", "b")],
  ["sameWidth is symmetric when subject and reference are swapped", sameWidth("a", "b", { tolerancePx: 3 })],
  ["sameHeight is symmetric when subject and reference are swapped", sameHeight("a", "b", { tolerancePx: 3 })],
  ["sameSize is symmetric when subject and reference are swapped", sameSize("a", "b", { tolerancePx: 3 })],
];

for (const [name, rule] of symmetric) {
  test(name, () => {
    for (let index = 0; index < 200; index += 1) {
      const subject = randomRectangle();
      const reference = randomRectangle();
      expect(passes(rule, subject, reference)).toBe(
        passes(rule, reference, subject),
      );
    }
  });
}

for (const [name, forward, reverse] of [
  ["leftOf subject reference is equivalent to rightOf reference subject", leftOf("a", "b", { tolerancePx: 2 }), rightOf("a", "b", { tolerancePx: 2 })],
  ["rightOf subject reference is equivalent to leftOf reference subject", rightOf("a", "b", { tolerancePx: 2 }), leftOf("a", "b", { tolerancePx: 2 })],
  ["above subject reference is equivalent to below reference subject", above("a", "b", { tolerancePx: 2 }), below("a", "b", { tolerancePx: 2 })],
  ["below subject reference is equivalent to above reference subject", below("a", "b", { tolerancePx: 2 }), above("a", "b", { tolerancePx: 2 })],
] as const) {
  test(name, () => {
    for (let index = 0; index < 200; index += 1) {
      const subject = randomRectangle();
      const reference = randomRectangle();
      expect(passes(forward, subject, reference)).toBe(
        passes(reverse, reference, subject),
      );
    }
  });
}

test("unconstrained overlap and notOverlap are complementary for valid rectangles", () => {
  for (let index = 0; index < 500; index += 1) {
    const subject = randomRectangle();
    const reference = randomRectangle();
    expect(passes(overlap("a", "b"), subject, reference)).toBe(
      !passes(notOverlap("a", "b"), subject, reference),
    );
  }
});

test("every valid rectangle is inside itself", () => {
  for (let index = 0; index < 500; index += 1) {
    const rectangle = randomRectangle();
    expect(passes(inside("a", "b"), rectangle, rectangle)).toBe(true);
  }
});

test("every valid rectangle has the same size as itself", () => {
  for (let index = 0; index < 500; index += 1) {
    const rectangle = randomRectangle();
    expect(passes(sameSize("a", "b"), rectangle, rectangle)).toBe(true);
  }
});

for (const [name, narrow, wide] of [
  ["increasing alignment tolerance cannot turn a pass into a failure", align("a", "b", "left", { tolerancePx: 1 }), align("a", "b", "left", { tolerancePx: 2 })],
  ["increasing ordering tolerance cannot turn a pass into a failure", leftOf("a", "b", { tolerancePx: 1 }), leftOf("a", "b", { tolerancePx: 2 })],
  ["increasing containment tolerance cannot turn a pass into a failure", inside("a", "b", { tolerancePx: 1 }), inside("a", "b", { tolerancePx: 2 })],
  ["increasing size tolerance cannot turn a pass into a failure", sameSize("a", "b", { tolerancePx: 1 }), sameSize("a", "b", { tolerancePx: 2 })],
  ["widening a gap range cannot turn a pass into a failure", leftOf("a", "b", { gap: { minPx: 2, maxPx: 4 } }), leftOf("a", "b", { gap: { minPx: 1, maxPx: 5 } })],
  ["widening an overlap range cannot turn a pass into a failure", overlap("a", "b", { horizontal: { minPx: 2, maxPx: 4 } }), overlap("a", "b", { horizontal: { minPx: 1, maxPx: 5 } })],
] as const) {
  test(name, () => {
    for (let index = 0; index < 500; index += 1) {
      const subject = randomRectangle();
      const reference = randomRectangle();
      if (passes(narrow, subject, reference)) {
        expect(passes(wide, subject, reference)).toBe(true);
      }
    }
  });
}

test("scaling both rectangles and every numeric constraint equally preserves the result", () => {
  for (let index = 0; index < 500; index += 1) {
    const subject = randomRectangle();
    const reference = randomRectangle();
    const factor = random() * 10 + 0.1;
    const original = leftOf("a", "b", {
      tolerancePx: 2,
      gap: { minPx: 3, maxPx: 20 },
    });
    const scaled = leftOf("a", "b", {
      tolerancePx: 2 * factor,
      gap: { minPx: 3 * factor, maxPx: 20 * factor },
    });
    expect(passes(scaled, scale(subject, factor), scale(reference, factor))).toBe(
      passes(original, subject, reference),
    );
  }
});

test("valid finite rectangle inputs never produce NaN diagnostic measurements", () => {
  for (let index = 0; index < 500; index += 1) {
    const findings = evaluateGeometry(
      sameSize("a", "b"),
      0,
      randomRectangle(),
      randomRectangle(),
    );
    expect(JSON.stringify(findings)).not.toMatch(/NaN|Infinity/);
  }
});

test("repeated evaluation of identical inputs produces the same result", () => {
  for (let index = 0; index < 500; index += 1) {
    const subject = randomRectangle();
    const reference = randomRectangle();
    const rule = overlap("a", "b", { horizontal: { minPx: 2 } });
    expect(evaluateGeometry(rule, 0, subject, reference)).toEqual(
      evaluateGeometry(rule, 0, subject, reference),
    );
  }
});
