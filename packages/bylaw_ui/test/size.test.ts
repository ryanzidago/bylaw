import { expect, test } from "bun:test";

import { sameHeight, sameSize, sameWidth } from "bylaw-ui";
import { expectFailure, expectPass, rect } from "./support";

for (const dimension of ["Width", "Height"] as const) {
  const helper = dimension === "Width" ? sameWidth : sameHeight;
  const subject = (difference: number) =>
    dimension === "Width" ? rect(100, -50, 10 + difference, 5) : rect(100, -50, 5, 10 + difference);
  const reference =
    dimension === "Width" ? rect(-100, 50, 10, 99) : rect(-100, 50, 99, 10);
  const label = `same${dimension}`;

  test(`${label} passes for equal ${dimension.toLowerCase()}s`, () =>
    expectPass(helper("subject", "reference"), subject(0), reference));

  test(`${label} passes when the ${dimension.toLowerCase()} difference is smaller than tolerance`, () =>
    expectPass(
      helper("subject", "reference", { tolerancePx: 1 }),
      subject(0.9),
      reference,
    ));

  test(`${label} passes when the ${dimension.toLowerCase()} difference equals tolerance`, () =>
    expectPass(
      helper("subject", "reference", { tolerancePx: 1 }),
      subject(1),
      reference,
    ));

  test(`${label} fails when the ${dimension.toLowerCase()} difference exceeds tolerance`, () =>
    expectFailure(
      helper("subject", "reference", { tolerancePx: 1 }),
      subject(1.01),
      reference,
      "size-mismatch",
    ));

  test(`${label} treats the ${dimension.toLowerCase()} difference as absolute`, async () => {
    await expectPass(
      helper("subject", "reference", { tolerancePx: 1 }),
      subject(1),
      reference,
    );
    await expectPass(
      helper("subject", "reference", { tolerancePx: 1 }),
      reference,
      subject(1),
    );
  });

  test(`${label} preserves fractional ${dimension.toLowerCase()}s`, () =>
    expectFailure(
      helper("subject", "reference", { tolerancePx: 0.2 }),
      subject(0.200_001),
      reference,
      "size-mismatch",
    ));

  test(`${label} ignores rectangle position`, () =>
    expectPass(
      helper("subject", "reference"),
      subject(0),
      { ...reference, x: 999_999, y: -999_999 },
    ));

  test(`${label} rejects unequal ${dimension.toLowerCase()}s when tolerance is omitted`, () =>
    expectFailure(
      helper("subject", "reference"),
      subject(0.001),
      reference,
      "size-mismatch",
    ));
}

test("sameSize passes when both dimensions are equal", () =>
  expectPass(sameSize("subject", "reference"), rect(0, 0, 10, 20), rect(50, 50, 10, 20)));

test("sameSize passes when both differences are within tolerance", () =>
  expectPass(
    sameSize("subject", "reference", { tolerancePx: 1 }),
    rect(0, 0, 10.9, 20.9),
    rect(50, 50, 10, 20),
  ));

test("sameSize passes when both differences equal tolerance", () =>
  expectPass(
    sameSize("subject", "reference", { tolerancePx: 1 }),
    rect(0, 0, 11, 21),
    rect(50, 50, 10, 20),
  ));

for (const [name, subject] of [
  ["sameSize fails when only width exceeds tolerance", rect(0, 0, 11.01, 20)],
  ["sameSize fails when only height exceeds tolerance", rect(0, 0, 10, 21.01)],
  ["sameSize fails when both dimensions exceed tolerance", rect(0, 0, 11.01, 21.01)],
] as const) {
  test(name, () =>
    expectFailure(
      sameSize("subject", "reference", { tolerancePx: 1 }),
      subject,
      rect(50, 50, 10, 20),
      "size-mismatch",
    ));
}

test("sameSize applies the same tolerance independently to both dimensions", () =>
  expectPass(
    sameSize("subject", "reference", { tolerancePx: 1 }),
    rect(0, 0, 9, 21),
    rect(50, 50, 10, 20),
  ));

test("sameSize reports both dimension differences", async () => {
  const finding = await expectFailure(
    sameSize("subject", "reference"),
    rect(0, 0, 12.5, 23.75),
    rect(50, 50, 10, 20),
    "size-mismatch",
  );
  expect(finding).toMatchObject({
    actual: { widthDifferencePx: 2.5, heightDifferencePx: 3.75 },
  });
});

test("sameSize compares both dimension differences independently of operand direction", async () => {
  const rule = sameSize("subject", "reference", { tolerancePx: 1 });
  await expectPass(rule, rect(0, 0, 11, 19), rect(0, 0, 10, 20));
  await expectPass(rule, rect(0, 0, 10, 20), rect(0, 0, 11, 19));
});

test("sameSize rejects unequal dimensions when tolerance is omitted", () =>
  expectFailure(
    sameSize("subject", "reference"),
    rect(0, 0, 10, 20.001),
    rect(0, 0, 10, 20),
    "size-mismatch",
  ));
