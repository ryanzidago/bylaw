import { expect, test } from "bun:test";

import * as bylawUi from "bylaw-ui";
import {
  above,
  align,
  below,
  checkLayout,
  inside,
  leftOf,
  notOverlap,
  overlap,
  rightOf,
  sameHeight,
  sameSize,
  sameWidth,
  type LayoutRule,
} from "bylaw-ui";
import { fixtureAdapter, rect, visible } from "./support";

for (const exportName of [
  "checkLayout",
  "assertLayout",
  "align",
  "above",
  "below",
  "leftOf",
  "rightOf",
  "overlap",
  "notOverlap",
  "inside",
  "sameWidth",
  "sameHeight",
  "sameSize",
] as const) {
  test(`exports ${exportName} from the package root`, () => {
    expect(bylawUi[exportName]).toBeFunction();
  });
}

test("accepts rules produced by the public rule helpers", async () => {
  const rules = [
    align("subject", "reference", "left"),
    above("subject", "reference"),
    below("subject", "reference"),
    leftOf("subject", "reference"),
    rightOf("subject", "reference"),
    overlap("subject", "reference"),
    notOverlap("subject", "reference"),
    inside("subject", "reference"),
    sameWidth("subject", "reference"),
    sameHeight("subject", "reference"),
    sameSize("subject", "reference"),
  ];

  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect(0, 0, 10, 10)),
      reference: visible("reference", rect(20, 20, 10, 10)),
    }),
    rules,
  });

  expect(report.rules.total).toBe(rules.length);
  expect(report.findings.some((finding) => finding.category === "invalid-rule")).toBe(
    false,
  );
});

test("accepts structurally valid inline rules", async () => {
  const rule: LayoutRule = {
    kind: "sameSize",
    subject: "subject",
    reference: "reference",
    options: { tolerancePx: 0 },
  };
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect()),
      reference: visible("reference", rect()),
    }),
    rules: [rule],
  });

  expect(report.passed).toBe(true);
});

test("uses subject as the first relationship operand", () => {
  expect(leftOf("first", "second").subject).toBe("first");
});

test("uses reference as the second relationship operand", () => {
  expect(leftOf("first", "second").reference).toBe("second");
});

test("does not mutate the supplied rule array", async () => {
  const rules = [sameSize("subject", "reference")];
  const original = [...rules];
  await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect()),
      reference: visible("reference", rect()),
    }),
    rules,
  });
  expect(rules).toEqual(original);
});

test("does not mutate supplied rule options", async () => {
  const options = { gap: { minPx: 1, maxPx: 4 }, tolerancePx: 2 };
  const original = structuredClone(options);
  const rule = leftOf("subject", "reference", options);
  options.gap.minPx = 99;

  expect(rule.options).toEqual(original);

  await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect(0, 0, 10, 10)),
      reference: visible("reference", rect(12, 0, 10, 10)),
    }),
    rules: [rule],
  });
  expect(rule.options).toEqual(original);
});
