import { expect, test } from "bun:test";

import { inside } from "bylaw-ui";
import { expectFailure, expectPass, rect } from "./support";

const contained = [
  ["inside passes when the subject is strictly inside the reference", rect(2, 2, 4, 4)],
  ["inside passes when subject and reference rectangles are identical", rect()],
  ["inside passes when the subject shares the reference left edge", rect(0, 2, 4, 4)],
  ["inside passes when the subject shares the reference right edge", rect(6, 2, 4, 4)],
  ["inside passes when the subject shares the reference top edge", rect(2, 0, 4, 4)],
  ["inside passes when the subject shares the reference bottom edge", rect(2, 6, 4, 4)],
  ["inside passes when the subject shares every reference boundary", rect()],
] as const;

for (const [name, subject] of contained) {
  test(name, () => expectPass(inside("subject", "reference"), subject, rect()));
}

const overflowCases = [
  ["inside fails when the subject overflows the left edge", rect(-1, 2, 4, 4)],
  ["inside fails when the subject overflows the right edge", rect(7, 2, 4, 4)],
  ["inside fails when the subject overflows the top edge", rect(2, -1, 4, 4)],
  ["inside fails when the subject overflows the bottom edge", rect(2, 7, 4, 4)],
  ["inside fails when the subject is larger on both horizontal sides", rect(-1, 2, 12, 4)],
  ["inside fails when the subject is larger on both vertical sides", rect(2, -1, 4, 12)],
  ["inside fails when the subject encloses the reference", rect(-1, -1, 12, 12)],
] as const;

for (const [name, subject] of overflowCases) {
  test(name, () =>
    expectFailure(
      inside("subject", "reference"),
      subject,
      rect(),
      "containment-overflow",
    ));
}

const sides = [
  {
    side: "left",
    subject: (overflow: number) => rect(-overflow, 2, 4, 4),
  },
  {
    side: "right",
    subject: (overflow: number) => rect(6 + overflow, 2, 4, 4),
  },
  {
    side: "top",
    subject: (overflow: number) => rect(2, -overflow, 4, 4),
  },
  {
    side: "bottom",
    subject: (overflow: number) => rect(2, 6 + overflow, 4, 4),
  },
];

for (const { side, subject } of sides) {
  test(`inside accepts partial ${side} overflow smaller than the tolerance`, () =>
    expectPass(
      inside("subject", "reference", { tolerancePx: 1 }),
      subject(0.9),
      rect(),
    ));

  test(`inside accepts partial ${side} overflow exactly equal to the tolerance`, () =>
    expectPass(
      inside("subject", "reference", { tolerancePx: 1 }),
      subject(1),
      rect(),
    ));

  test(`inside rejects ${side} overflow greater than the tolerance`, () =>
    expectFailure(
      inside("subject", "reference", { tolerancePx: 1 }),
      subject(1.01),
      rect(),
      "containment-overflow",
    ));
}

test("inside requires every overflow to be within tolerance", () =>
  expectFailure(
    inside("subject", "reference", { tolerancePx: 1 }),
    rect(-1, -1.01, 12, 12.01),
    rect(),
    "containment-overflow",
  ));

test("inside preserves fractional overflow measurements", async () => {
  const finding = await expectFailure(
    inside("subject", "reference", { tolerancePx: 0.2 }),
    rect(-0.25, 2, 4, 4),
    rect(),
    "containment-overflow",
  );
  expect(finding).toMatchObject({ actual: { leftPx: 0.25 } });
});

test("inside supports rectangles positioned at negative coordinates", () =>
  expectPass(
    inside("subject", "reference"),
    rect(-90, -90, 10, 10),
    rect(-100, -100, 100, 100),
  ));

test("inside reports overflow separately for every side", async () => {
  const finding = await expectFailure(
    inside("subject", "reference"),
    rect(-1, -2, 14, 16),
    rect(),
    "containment-overflow",
  );
  expect(finding).toMatchObject({
    actual: { leftPx: 1, rightPx: 3, topPx: 2, bottomPx: 4 },
  });
});

test("inside accepts partial simultaneous boundary overflows when every overflow is within tolerance", () =>
  expectPass(
    inside("subject", "reference", { tolerancePx: 1 }),
    rect(-1, -1, 12, 12),
    rect(),
  ));

test("inside accepts partial boundary overflow within tolerance", () =>
  expectPass(
    inside("subject", "reference", { tolerancePx: 2 }),
    rect(-2, 1, 5, 5),
    rect(),
  ));

test("inside fails for a horizontally disjoint subject even when the separation is within tolerance", () =>
  expectFailure(
    inside("subject", "reference", { tolerancePx: 1 }),
    rect(10.5, 2, 1, 1),
    rect(),
    "containment-overflow",
  ));

test("inside fails for a vertically disjoint subject even when the separation is within tolerance", () =>
  expectFailure(
    inside("subject", "reference", { tolerancePx: 1 }),
    rect(2, 10.5, 1, 1),
    rect(),
    "containment-overflow",
  ));
