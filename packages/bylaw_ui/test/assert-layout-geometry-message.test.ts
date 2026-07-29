import { expect, test } from "bun:test";

import {
  align,
  inside,
  LayoutAssertionError,
  leftOf,
  notOverlap,
  overlap,
  sameHeight,
  sameSize,
  sameWidth,
  type LayoutRule,
} from "bylaw-ui";
import { checkRule, rect } from "./support";

async function failureMessage(
  rule: LayoutRule,
  subjectRect: ReturnType<typeof rect>,
  referenceRect: ReturnType<typeof rect>,
): Promise<string> {
  const report = await checkRule(rule, subjectRect, referenceRect);
  expect(report.passed).toBe(false);
  return new LayoutAssertionError(report).message;
}

function expectLines(message: string, lines: string[]): void {
  for (const line of lines) {
    expect(message).toContain(line);
  }
}

test(
  "reports alignment coordinates difference tolerance and excess",
  async () => {
    const message = await failureMessage(
      align("subject", "reference", "left", { tolerancePx: 1 }),
      rect(12),
      rect(10),
    );

    expectLines(message, [
      "align failed",
      "alignment: left",
      "subject coordinate: 12px",
      "reference coordinate: 10px",
      "difference: 2px",
      "allowed tolerance: 1px",
      "exceeds tolerance by: 1px",
    ]);
  },
);

test(
  "reports ordering gap boundary crossing tolerance and excess",
  async () => {
    const message = await failureMessage(
      leftOf("subject", "reference", { tolerancePx: 1 }),
      rect(0, 0, 12),
      rect(10),
    );

    expectLines(message, [
      "leftOf failed",
      "signed gap: -2px",
      "boundary crossing: 2px",
      "allowed tolerance: 1px",
      "exceeds tolerance by: 1px",
    ]);
  },
);

test("reports a measured gap below its allowed range", async () => {
  const message = await failureMessage(
    leftOf("subject", "reference", { gap: { minPx: 4, maxPx: 8 } }),
    rect(),
    rect(12),
  );

  expectLines(message, [
    "leftOf failed",
    "measured gap: 2px",
    "allowed gap: 4px–8px",
    "below minimum by: 2px",
  ]);
});

test("reports a measured gap above its allowed range", async () => {
  const message = await failureMessage(
    leftOf("subject", "reference", { gap: { minPx: 4, maxPx: 8 } }),
    rect(),
    rect(20),
  );

  expectLines(message, [
    "leftOf failed",
    "measured gap: 10px",
    "allowed gap: 4px–8px",
    "above maximum by: 2px",
  ]);
});

test("reports missing overlap geometry", async () => {
  const message = await failureMessage(
    overlap("subject", "reference"),
    rect(),
    rect(15),
  );

  expectLines(message, [
    "overlap failed",
    "horizontal overlap: 0px",
    "vertical overlap: 10px",
    "required overlap: positive on both axes",
  ]);
});

test("reports overlap below its allowed range", async () => {
  const message = await failureMessage(
    overlap("subject", "reference", {
      horizontal: { minPx: 4, maxPx: 8 },
    }),
    rect(),
    rect(8),
  );

  expectLines(message, [
    "overlap failed",
    "horizontal overlap: 2px",
    "allowed horizontal overlap: 4px–8px",
    "below minimum by: 2px",
  ]);
});

test("reports overlap above its allowed range", async () => {
  const message = await failureMessage(
    overlap("subject", "reference", {
      horizontal: { minPx: 4, maxPx: 6 },
    }),
    rect(),
    rect(2),
  );

  expectLines(message, [
    "overlap failed",
    "horizontal overlap: 8px",
    "allowed horizontal overlap: 4px–6px",
    "above maximum by: 2px",
  ]);
});

test("reports unexpected overlap geometry", async () => {
  const message = await failureMessage(
    notOverlap("subject", "reference"),
    rect(),
    rect(5),
  );

  expectLines(message, [
    "notOverlap failed",
    "horizontal overlap: 5px",
    "vertical overlap: 10px",
    "allowed overlap: none",
  ]);
});

test("reports containment overflow tolerance and excess", async () => {
  const message = await failureMessage(
    inside("subject", "reference", { tolerancePx: 1 }),
    rect(-2, 0, 14, 10),
    rect(),
  );

  expectLines(message, [
    "inside failed",
    "left overflow: 2px",
    "right overflow: 2px",
    "allowed tolerance: 1px",
    "exceeds tolerance by: 1px",
  ]);
});

test("reports geometry for disjoint containment", async () => {
  const message = await failureMessage(
    inside("subject", "reference"),
    rect(20, 0, 5, 5),
    rect(),
  );

  expectLines(message, [
    "inside failed",
    "right overflow: 15px",
    "horizontal intersection: 0px",
    "vertical intersection: 5px",
    "required intersection: positive on both axes",
  ]);
});

test(
  "reports width measurements difference tolerance and excess",
  async () => {
    const message = await failureMessage(
      sameWidth("subject", "reference", { tolerancePx: 1 }),
      rect(0, 0, 1_038),
      rect(0, 0, 1_040),
    );

    expectLines(message, [
      "sameWidth failed",
      "subject width: 1038px",
      "reference width: 1040px",
      "difference: 2px",
      "allowed tolerance: 1px",
      "exceeds tolerance by: 1px",
    ]);
  },
);

test(
  "reports height measurements difference tolerance and excess",
  async () => {
    const message = await failureMessage(
      sameHeight("subject", "reference", { tolerancePx: 1 }),
      rect(0, 0, 10, 718),
      rect(0, 0, 10, 720),
    );

    expectLines(message, [
      "sameHeight failed",
      "subject height: 718px",
      "reference height: 720px",
      "difference: 2px",
      "allowed tolerance: 1px",
      "exceeds tolerance by: 1px",
    ]);
  },
);

test("reports both dimensions for a size mismatch", async () => {
  const message = await failureMessage(
    sameSize("subject", "reference", { tolerancePx: 1 }),
    rect(0, 0, 98, 47),
    rect(0, 0, 100, 50),
  );

  expectLines(message, [
    "sameSize failed",
    "subject width: 98px",
    "reference width: 100px",
    "width difference: 2px",
    "subject height: 47px",
    "reference height: 50px",
    "height difference: 3px",
    "allowed tolerance: 1px",
    "width exceeds tolerance by: 1px",
    "height exceeds tolerance by: 2px",
  ]);
});
