import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  equalWidths,
  everyInside,
  verticallyOrdered,
  type LayoutReport,
  type LayoutRule,
} from "bylaw-ui";
import { fixtureAdapter } from "./support";

function validate(rule: unknown): Promise<LayoutReport> {
  return checkLayout({
    adapter: fixtureAdapter({}),
    rules: [rule as LayoutRule],
  });
}

async function expectInvalid(rule: unknown, fieldPath: string, code?: string) {
  const report = await validate(rule);
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 1, skipped: 0 });
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "invalid-rule",
      fieldPath,
      ...(code === undefined ? {} : { code }),
    }),
  );
  return report;
}

test("a public helper rejects an empty collection target name", () => {
  expect(() => collection("")).toThrow("target");
});

test("a public helper rejects a runtime-invalid collection target declaration", () => {
  expect(() =>
    equalWidths({ kind: "collection", target: 42 } as never),
  ).toThrow("collection");
});

test("a caller-constructed collection rule reports a missing collection operand", () =>
  expectInvalid({ kind: "equalWidths" }, "collection", "missing-field"));

test("a containment collection rule reports a missing singular container operand", () =>
  expectInvalid(
    {
      kind: "everyInside",
      collection: { kind: "collection", target: "cards" },
    },
    "container",
    "missing-field",
  ));

test("collection containment rejects a negative tolerance", () => {
  expect(() =>
    everyInside(collection("cards"), "container", { tolerancePx: -1 }),
  ).toThrow("options.tolerancePx");
});

test("collection equal-width rejects a negative tolerance", () => {
  expect(() => equalWidths(collection("cards"), { tolerancePx: -1 })).toThrow(
    "options.tolerancePx",
  );
});

test("collection tolerances reject non-finite values", () => {
  for (const tolerancePx of [
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
  ]) {
    expect(() =>
      everyInside(collection("cards"), "container", { tolerancePx }),
    ).toThrow("options.tolerancePx");
    expect(() => equalWidths(collection("cards"), { tolerancePx })).toThrow(
      "options.tolerancePx",
    );
  }
});

test("collection vertical ordering rejects an empty gap range", () => {
  expect(() => verticallyOrdered(collection("rows"), { gap: {} })).toThrow(
    "options.gap",
  );
});

test("collection vertical ordering rejects a minimum greater than its maximum", () => {
  expect(() =>
    verticallyOrdered(collection("rows"), {
      gap: { minPx: 9, maxPx: 8 },
    }),
  ).toThrow("options.gap");
});

test("collection vertical ordering rejects negative gap bounds", () => {
  expect(() =>
    verticallyOrdered(collection("rows"), { gap: { minPx: -1 } }),
  ).toThrow("options.gap.minPx");
  expect(() =>
    verticallyOrdered(collection("rows"), { gap: { maxPx: -1 } }),
  ).toThrow("options.gap.maxPx");
});

test("collection vertical ordering rejects non-finite gap bounds", () => {
  expect(() =>
    verticallyOrdered(collection("rows"), { gap: { minPx: Number.NaN } }),
  ).toThrow("options.gap.minPx");
  expect(() =>
    verticallyOrdered(collection("rows"), {
      gap: { maxPx: Number.POSITIVE_INFINITY },
    }),
  ).toThrow("options.gap.maxPx");
});

test("collection rules report unknown fields as invalid", () =>
  expectInvalid(
    {
      kind: "equalWidths",
      collection: { kind: "collection", target: "cards" },
      unsupported: true,
    },
    "unsupported",
    "unknown-field",
  ));

test("collection rule helpers reject unsupported option fields", () => {
  expect(() =>
    equalWidths(collection("cards"), { unsupported: true } as never),
  ).toThrow("options.unsupported");
});

test("an invalid collection rule does not resolve targets or evaluate geometry", async () => {
  let measurements = 0;
  const report = await checkLayout({
    adapter: fixtureAdapter({}, () => {
      measurements += 1;
    }),
    rules: [{ kind: "equalWidths" } as unknown as LayoutRule],
  });
  expect(report.findings[0]?.category).toBe("invalid-rule");
  expect(measurements).toBe(0);
});
