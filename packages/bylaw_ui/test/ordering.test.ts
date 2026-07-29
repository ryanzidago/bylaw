import { expect, test } from "bun:test";

import {
  above,
  below,
  leftOf,
  rightOf,
  type OrderingOptions,
  type OrderingRule,
} from "bylaw-ui";
import { expectFailure, expectPass, rect } from "./support";

type OrderingHelper = (
  subject: string,
  reference: string,
  options?: OrderingOptions,
) => OrderingRule;

const relationships: Array<{
  name: "leftOf" | "rightOf" | "above" | "below";
  helper: OrderingHelper;
  subject: (gap: number) => ReturnType<typeof rect>;
  reference: ReturnType<typeof rect>;
}> = [
  {
    name: "leftOf",
    helper: leftOf,
    subject: (gap) => rect(-10 - gap, 0),
    reference: rect(0, 100),
  },
  {
    name: "rightOf",
    helper: rightOf,
    subject: (gap) => rect(10 + gap, 0),
    reference: rect(0, 100),
  },
  {
    name: "above",
    helper: above,
    subject: (gap) => rect(0, -10 - gap),
    reference: rect(100, 0),
  },
  {
    name: "below",
    helper: below,
    subject: (gap) => rect(0, 10 + gap),
    reference: rect(100, 0),
  },
];

for (const { name, helper, subject, reference } of relationships) {
  test(`${name} passes when the subject is separated from the reference`, () =>
    expectPass(helper("subject", "reference"), subject(5), reference));

  test(`${name} passes when the subject touches the reference`, () =>
    expectPass(helper("subject", "reference"), subject(0), reference));

  test(`${name} fails when the subject crosses the reference boundary`, () =>
    expectFailure(
      helper("subject", "reference"),
      subject(-1),
      reference,
      "ordering-violation",
    ));

  test(`${name} accepts boundary crossing smaller than the tolerance`, () =>
    expectPass(
      helper("subject", "reference", { tolerancePx: 1 }),
      subject(-0.9),
      reference,
    ));

  test(`${name} accepts boundary crossing exactly equal to the tolerance`, () =>
    expectPass(
      helper("subject", "reference", { tolerancePx: 1 }),
      subject(-1),
      reference,
    ));

  test(`${name} rejects boundary crossing greater than the tolerance`, () =>
    expectFailure(
      helper("subject", "reference", { tolerancePx: 1 }),
      subject(-1.01),
      reference,
      "ordering-violation",
    ));
}

const gapCases: Array<{
  name: string;
  gap: number;
  range: { minPx?: number; maxPx?: number };
  pass: boolean;
}> = [
  { name: "accepts a gap larger than a minimum gap", gap: 5, range: { minPx: 4 }, pass: true },
  { name: "accepts a gap exactly equal to a minimum gap", gap: 4, range: { minPx: 4 }, pass: true },
  { name: "rejects a gap smaller than a minimum gap", gap: 3.99, range: { minPx: 4 }, pass: false },
  { name: "accepts a gap smaller than a maximum gap", gap: 3, range: { maxPx: 4 }, pass: true },
  { name: "accepts a gap exactly equal to a maximum gap", gap: 4, range: { maxPx: 4 }, pass: true },
  { name: "rejects a gap larger than a maximum gap", gap: 4.01, range: { maxPx: 4 }, pass: false },
  { name: "accepts a gap inside a bounded range", gap: 3, range: { minPx: 2, maxPx: 4 }, pass: true },
  { name: "rejects a gap below a bounded range", gap: 1.99, range: { minPx: 2, maxPx: 4 }, pass: false },
  { name: "rejects a gap above a bounded range", gap: 4.01, range: { minPx: 2, maxPx: 4 }, pass: false },
];

for (const scenario of gapCases) {
  test(scenario.name, () => {
    const rule = leftOf("subject", "reference", { gap: scenario.range });
    return scenario.pass
      ? expectPass(rule, rect(-10 - scenario.gap), rect())
      : expectFailure(rule, rect(-10 - scenario.gap), rect(), "gap-out-of-range");
  });
}

test("accepts both endpoints of a bounded gap range", async () => {
  const rule = leftOf("subject", "reference", { gap: { minPx: 2, maxPx: 4 } });
  await expectPass(rule, rect(-12), rect());
  await expectPass(rule, rect(-14), rect());
});

test("requires the ordering relationship even when the signed gap satisfies a supplied maximum", () =>
  expectFailure(
    leftOf("subject", "reference", {
      tolerancePx: 1,
      gap: { maxPx: 100 },
    }),
    rect(-8),
    rect(),
    "ordering-violation",
  ));

test("does not relax a minimum gap using ordering tolerance", () =>
  expectFailure(
    leftOf("subject", "reference", {
      tolerancePx: 2,
      gap: { minPx: 1 },
    }),
    rect(-9.5),
    rect(),
    "gap-out-of-range",
  ));

test("does not relax a maximum gap using ordering tolerance", () =>
  expectFailure(
    leftOf("subject", "reference", {
      tolerancePx: 2,
      gap: { maxPx: 1 },
    }),
    rect(-11.5),
    rect(),
    "gap-out-of-range",
  ));

test("distinguishes a broken ordering relationship from an out-of-range valid gap", async () => {
  const broken = await expectFailure(
    leftOf("subject", "reference", { gap: { minPx: 3 } }),
    rect(-9),
    rect(),
    "ordering-violation",
  );
  const range = await expectFailure(
    leftOf("subject", "reference", { gap: { minPx: 3 } }),
    rect(-12),
    rect(),
    "gap-out-of-range",
  );
  expect(broken.code).not.toBe(range.code);
});

test("preserves fractional gaps", async () => {
  const finding = await expectFailure(
    leftOf("subject", "reference", { gap: { minPx: 0.251 } }),
    rect(-10.25),
    rect(),
    "gap-out-of-range",
  );
  expect(finding).toMatchObject({ actual: { signedGapPx: 0.25 } });
});

test("supports ordering relationships at negative coordinates", () =>
  expectPass(
    leftOf("subject", "reference", { gap: { minPx: 5, maxPx: 5 } }),
    rect(-115, -200),
    rect(-100, 500),
  ));

test("reports the signed gap for a failed ordering rule", async () => {
  const finding = await expectFailure(
    leftOf("subject", "reference"),
    rect(-8),
    rect(),
    "ordering-violation",
  );
  expect(finding).toMatchObject({ actual: { signedGapPx: -2 } });
});

test("reports the amount of boundary crossing for a failed ordering rule", async () => {
  const finding = await expectFailure(
    leftOf("subject", "reference"),
    rect(-8),
    rect(),
    "ordering-violation",
  );
  expect(finding).toMatchObject({ actual: { boundaryCrossingPx: 2 } });
});

test("accepts touching rectangles with a zero-width gap range", () =>
  expectPass(
    leftOf("subject", "reference", { gap: { minPx: 0, maxPx: 0 } }),
    rect(-10),
    rect(),
  ));

test("horizontal ordering ignores vertical separation", () =>
  expectPass(leftOf("subject", "reference"), rect(-20, 10_000), rect(0, -10_000)));

test("vertical ordering ignores horizontal separation", () =>
  expectPass(above("subject", "reference"), rect(10_000, -20), rect(-10_000, 0)));
