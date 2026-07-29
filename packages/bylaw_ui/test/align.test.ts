import { expect, test } from "bun:test";

import { align, type Alignment } from "bylaw-ui";
import { expectFailure, expectPass, rect } from "./support";

const aligned: Record<Alignment, [ReturnType<typeof rect>, ReturnType<typeof rect>]> = {
  left: [rect(4, 0, 10, 10), rect(4, 30, 30, 20)],
  right: [rect(4, 0, 10, 10), rect(-16, 30, 30, 20)],
  top: [rect(0, 4, 10, 10), rect(30, 4, 20, 30)],
  bottom: [rect(0, 4, 10, 10), rect(30, -16, 20, 30)],
  centerX: [rect(5, 0, 10, 10), rect(-5, 30, 30, 20)],
  centerY: [rect(0, 5, 10, 10), rect(30, -5, 20, 30)],
};

for (const [alignment, [subject, reference]] of Object.entries(aligned) as Array<
  [Alignment, [ReturnType<typeof rect>, ReturnType<typeof rect>]]
>) {
  const label =
    alignment === "centerX"
      ? "horizontal centers"
      : alignment === "centerY"
        ? "vertical centers"
        : `${alignment} edges`;

  test(`aligns equal ${label}`, () =>
    expectPass(align("subject", "reference", alignment), subject, reference));

  test(`rejects unequal ${label} when tolerance is omitted`, () => {
    const shifted = { ...reference, x: reference.x + 1, y: reference.y + 1 };
    return expectFailure(
      align("subject", "reference", alignment),
      subject,
      shifted,
      "alignment-mismatch",
    );
  });
}

test("accepts an alignment difference smaller than the tolerance", () =>
  expectPass(
    align("subject", "reference", "left", { tolerancePx: 1 }),
    rect(0),
    rect(0.9),
  ));

test("accepts an alignment difference exactly equal to the tolerance", () =>
  expectPass(
    align("subject", "reference", "left", { tolerancePx: 1 }),
    rect(0),
    rect(1),
  ));

test("rejects an alignment difference greater than the tolerance", () =>
  expectFailure(
    align("subject", "reference", "left", { tolerancePx: 1 }),
    rect(0),
    rect(1.01),
    "alignment-mismatch",
  ));

test("applies alignment tolerance regardless of which operand has the larger coordinate", async () => {
  await expectPass(
    align("subject", "reference", "left", { tolerancePx: 1 }),
    rect(1),
    rect(0),
  );
  await expectPass(
    align("subject", "reference", "left", { tolerancePx: 1 }),
    rect(0),
    rect(1),
  );
});

test("computes horizontal centers from both rectangle edges", () =>
  expectPass(
    align("subject", "reference", "centerX"),
    rect(10, 0, 10),
    rect(5, 40, 20),
  ));

test("computes vertical centers from both rectangle edges", () =>
  expectPass(
    align("subject", "reference", "centerY"),
    rect(0, 10, 10, 10),
    rect(40, 5, 20, 20),
  ));

test("aligns centers of differently sized rectangles", () =>
  expectPass(
    align("subject", "reference", "centerX"),
    rect(9, 0, 2, 80),
    rect(0, 50, 20, 2),
  ));

test("preserves fractional coordinates when comparing alignment", () =>
  expectFailure(
    align("subject", "reference", "left", { tolerancePx: 0.2 }),
    rect(0.1),
    rect(0.300_001),
    "alignment-mismatch",
  ));

test("aligns rectangles positioned at negative coordinates", () =>
  expectPass(
    align("subject", "reference", "left"),
    rect(-20, -50),
    rect(-20, 100),
  ));

test("alignment ignores displacement on the orthogonal axis", () =>
  expectPass(
    align("subject", "reference", "left"),
    rect(5, -10_000),
    rect(5, 10_000),
  ));

test("reports which alignment relationship failed", async () => {
  const finding = await expectFailure(
    align("subject", "reference", "centerX"),
    rect(),
    rect(2),
    "alignment-mismatch",
  );
  expect(finding).toMatchObject({
    category: "layout",
    relationship: "align",
    expected: { alignment: "centerX" },
  });
});

test("reports the measured alignment difference", async () => {
  const finding = await expectFailure(
    align("subject", "reference", "left"),
    rect(1.25),
    rect(4.75),
    "alignment-mismatch",
  );
  expect(finding).toMatchObject({
    actual: {
      subjectCoordinate: 1.25,
      referenceCoordinate: 4.75,
      differencePx: 3.5,
    },
  });
});
