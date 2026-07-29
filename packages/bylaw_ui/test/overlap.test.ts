import { expect, test } from "bun:test";

import { notOverlap, overlap } from "bylaw-ui";
import { expectFailure, expectPass, rect } from "./support";

const overlapPasses = [
  {
    name: "overlap passes when rectangles intersect positively on both axes",
    subject: rect(0, 0, 10, 10),
    reference: rect(5, 5, 10, 10),
  },
  {
    name: "overlap passes when one rectangle is fully contained by the other",
    subject: rect(2, 2, 2, 2),
    reference: rect(0, 0, 10, 10),
  },
  {
    name: "overlap passes for identical rectangles",
    subject: rect(0, 0, 10, 10),
    reference: rect(0, 0, 10, 10),
  },
  {
    name: "overlap passes for a fractional positive intersection",
    subject: rect(0, 0, 1, 1),
    reference: rect(0.999, 0.999, 1, 1),
  },
];

for (const scenario of overlapPasses) {
  test(scenario.name, () =>
    expectPass(
      overlap("subject", "reference"),
      scenario.subject,
      scenario.reference,
    ),
  );
}

const missingOverlap = [
  {
    name: "overlap fails when rectangles are horizontally separated",
    subject: rect(0, 0),
    reference: rect(20, 0),
  },
  {
    name: "overlap fails when rectangles are vertically separated",
    subject: rect(0, 0),
    reference: rect(0, 20),
  },
  {
    name: "overlap fails when rectangles are separated on both axes",
    subject: rect(0, 0),
    reference: rect(20, 20),
  },
  {
    name: "overlap fails when rectangles touch at a vertical edge",
    subject: rect(0, 0),
    reference: rect(10, 0),
  },
  {
    name: "overlap fails when rectangles touch at a horizontal edge",
    subject: rect(0, 0),
    reference: rect(0, 10),
  },
  {
    name: "overlap fails when rectangles touch only at a corner",
    subject: rect(0, 0),
    reference: rect(10, 10),
  },
  {
    name: "overlap fails when intersection is positive on only one axis",
    subject: rect(0, 0),
    reference: rect(5, 20),
  },
];

for (const scenario of missingOverlap) {
  test(scenario.name, () =>
    expectFailure(
      overlap("subject", "reference"),
      scenario.subject,
      scenario.reference,
      "missing-overlap",
    ),
  );
}

const axisCases = [
  {
    axis: "horizontal" as const,
    subject: (depth: number) => rect(10 - depth, 0),
    reference: rect(0, 0),
  },
  {
    axis: "vertical" as const,
    subject: (depth: number) => rect(0, 10 - depth),
    reference: rect(0, 0),
  },
];

for (const { axis, subject, reference } of axisCases) {
  test(`accepts ${axis} overlap larger than a minimum`, () =>
    expectPass(
      overlap("subject", "reference", { [axis]: { minPx: 4 } }),
      subject(5),
      reference,
    ));

  test(`accepts ${axis} overlap exactly equal to a minimum`, () =>
    expectPass(
      overlap("subject", "reference", { [axis]: { minPx: 4 } }),
      subject(4),
      reference,
    ));

  test(`rejects ${axis} overlap smaller than a minimum`, () =>
    expectFailure(
      overlap("subject", "reference", { [axis]: { minPx: 4 } }),
      subject(3.99),
      reference,
      "overlap-out-of-range",
    ));

  test(`accepts ${axis} overlap smaller than a maximum`, () =>
    expectPass(
      overlap("subject", "reference", { [axis]: { maxPx: 4 } }),
      subject(3),
      reference,
    ));

  test(`accepts ${axis} overlap exactly equal to a maximum`, () =>
    expectPass(
      overlap("subject", "reference", { [axis]: { maxPx: 4 } }),
      subject(4),
      reference,
    ));

  test(`rejects ${axis} overlap larger than a maximum`, () =>
    expectFailure(
      overlap("subject", "reference", { [axis]: { maxPx: 4 } }),
      subject(4.01),
      reference,
      "overlap-out-of-range",
    ));

  test(`accepts ${axis} overlap inside a bounded range`, () =>
    expectPass(
      overlap("subject", "reference", {
        [axis]: { minPx: 2, maxPx: 4 },
      }),
      subject(3),
      reference,
    ));

  test(`accepts both endpoints of a bounded ${axis} overlap range`, async () => {
    const rule = overlap("subject", "reference", {
      [axis]: { minPx: 2, maxPx: 4 },
    });
    await expectPass(rule, subject(2), reference);
    await expectPass(rule, subject(4), reference);
  });

  test(`rejects ${axis} overlap below a bounded range`, () =>
    expectFailure(
      overlap("subject", "reference", {
        [axis]: { minPx: 2, maxPx: 4 },
      }),
      subject(1.99),
      reference,
      "overlap-out-of-range",
    ));

  test(`rejects ${axis} overlap above a bounded range`, () =>
    expectFailure(
      overlap("subject", "reference", {
        [axis]: { minPx: 2, maxPx: 4 },
      }),
      subject(4.01),
      reference,
      "overlap-out-of-range",
    ));
}

test("constrains only horizontal depth when only a horizontal range is supplied", () =>
  expectPass(
    overlap("subject", "reference", { horizontal: { minPx: 2 } }),
    rect(8, 9.9),
    rect(),
  ));

test("constrains only vertical depth when only a vertical range is supplied", () =>
  expectPass(
    overlap("subject", "reference", { vertical: { minPx: 2 } }),
    rect(9.9, 8),
    rect(),
  ));

test("requires both overlap ranges when both are supplied", () =>
  expectFailure(
    overlap("subject", "reference", {
      horizontal: { minPx: 2 },
      vertical: { minPx: 2 },
    }),
    rect(8, 9),
    rect(),
    "overlap-out-of-range",
  ));

test("still requires positive vertical intersection when only horizontal depth is constrained", () =>
  expectFailure(
    overlap("subject", "reference", { horizontal: { minPx: 2 } }),
    rect(8, 10),
    rect(),
    "missing-overlap",
  ));

test("still requires positive horizontal intersection when only vertical depth is constrained", () =>
  expectFailure(
    overlap("subject", "reference", { vertical: { minPx: 2 } }),
    rect(10, 8),
    rect(),
    "missing-overlap",
  ));

test("distinguishes missing overlap from out-of-range overlap", async () => {
  const rule = overlap("subject", "reference", { horizontal: { minPx: 5 } });
  const missing = await expectFailure(
    rule,
    rect(20),
    rect(),
    "missing-overlap",
  );
  const shallow = await expectFailure(
    rule,
    rect(8),
    rect(),
    "overlap-out-of-range",
  );
  expect(missing.code).not.toBe(shallow.code);
});

test("reports horizontal and vertical intersection depths", async () => {
  const finding = await expectFailure(
    overlap("subject", "reference", { horizontal: { minPx: 9 } }),
    rect(3, 4),
    rect(),
    "overlap-out-of-range",
  );
  expect(finding).toMatchObject({
    actual: { horizontalPx: 7, verticalPx: 6 },
  });
});

const notOverlapPasses = [
  ["notOverlap passes when rectangles are horizontally separated", rect(20, 0)],
  ["notOverlap passes when rectangles are vertically separated", rect(0, 20)],
  ["notOverlap passes when rectangles touch at an edge", rect(10, 0)],
  ["notOverlap passes when rectangles touch at a corner", rect(10, 10)],
] as const;

for (const [name, subject] of notOverlapPasses) {
  test(name, () =>
    expectPass(notOverlap("subject", "reference"), subject, rect()),
  );
}

const notOverlapFailures = [
  [
    "notOverlap fails when rectangles intersect positively on both axes",
    rect(5, 5),
  ],
  ["notOverlap fails when one rectangle contains the other", rect(2, 2, 2, 2)],
  ["notOverlap fails for identical rectangles", rect()],
] as const;

for (const [name, subject] of notOverlapFailures) {
  test(name, () =>
    expectFailure(
      notOverlap("subject", "reference"),
      subject,
      rect(),
      "overlap-out-of-range",
    ),
  );
}

test("notOverlap does not apply implicit tolerance", () =>
  expectFailure(
    notOverlap("subject", "reference"),
    rect(9.999, 9.999),
    rect(),
    "overlap-out-of-range",
  ));

test("overlap with a zero minimum still requires positive intersection", () =>
  expectFailure(
    overlap("subject", "reference", { horizontal: { minPx: 0 } }),
    rect(10),
    rect(),
    "missing-overlap",
  ));
