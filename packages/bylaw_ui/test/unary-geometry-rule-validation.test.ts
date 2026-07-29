import { expect, test } from "bun:test";

import {
  checkLayout,
  height,
  width,
  type LayoutReport,
  type LayoutRule,
} from "bylaw-ui";
import { fixtureAdapter } from "./support";

async function validate(rule: unknown): Promise<LayoutReport> {
  return checkLayout({
    adapter: fixtureAdapter({}),
    rules: [rule as LayoutRule],
  });
}

async function expectInvalid(
  rule: unknown,
  fieldPath?: string,
  code?: string,
): Promise<LayoutReport> {
  const report = await validate(rule);
  expect(report).toMatchObject({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
  });
  expect(
    report.findings.some(({ category }) => category === "invalid-rule"),
  ).toBe(true);
  if (fieldPath !== undefined) {
    expect(report.findings).toContainEqual(
      expect.objectContaining({
        category: "invalid-rule",
        fieldPath,
        ...(code === undefined ? {} : { code }),
      }),
    );
  }
  return report;
}

test("reports a missing unary target as invalid", () =>
  expectInvalid(
    { kind: "width", range: { minPx: 10 } },
    "target",
    "missing-field",
  ));

test("reports an empty unary target as invalid", () =>
  expectInvalid(
    { kind: "height", target: "", range: { minPx: 10 } },
    "target",
    "invalid-value",
  ));

test("reports a non-string unary target as invalid at runtime", () =>
  expectInvalid({ kind: "inViewport", target: 42 }, "target", "invalid-type"));

test("reports a reference field on a unary rule as unknown", () =>
  expectInvalid(
    {
      kind: "width",
      target: "target",
      reference: "synthetic",
      range: { minPx: 10 },
    },
    "reference",
    "unknown-field",
  ));

test("reports a missing width range as invalid", () =>
  expectInvalid({ kind: "width", target: "target" }, "range", "missing-field"));

test("reports a missing height range as invalid", () =>
  expectInvalid(
    { kind: "height", target: "target" },
    "range",
    "missing-field",
  ));

test("reports an empty width range as invalid", () =>
  expectInvalid(
    { kind: "width", target: "target", range: {} },
    "range",
    "invalid-value",
  ));

test("reports an empty height range as invalid", () =>
  expectInvalid(
    { kind: "height", target: "target", range: {} },
    "range",
    "invalid-value",
  ));

test("reports a negative unary range bound as invalid", () =>
  expectInvalid(
    { kind: "width", target: "target", range: { minPx: -1 } },
    "range.minPx",
    "invalid-value",
  ));

test("reports a NaN unary range bound as invalid", () =>
  expectInvalid(
    { kind: "height", target: "target", range: { maxPx: Number.NaN } },
    "range.maxPx",
    "invalid-value",
  ));

test("reports an infinite unary range bound as invalid", () =>
  expectInvalid(
    {
      kind: "width",
      target: "target",
      range: { maxPx: Number.POSITIVE_INFINITY },
    },
    "range.maxPx",
    "invalid-value",
  ));

test("reports a nonnumeric unary range bound as invalid at runtime", () =>
  expectInvalid(
    { kind: "height", target: "target", range: { minPx: "10" } },
    "range.minPx",
    "invalid-type",
  ));

test("reports a unary range minimum greater than its maximum as invalid", () =>
  expectInvalid(
    {
      kind: "width",
      target: "target",
      range: { minPx: 20, maxPx: 10 },
    },
    "range",
    "invalid-value",
  ));

test("reports a non-object unary range as invalid at runtime", () =>
  expectInvalid(
    { kind: "height", target: "target", range: 10 },
    "range",
    "invalid-type",
  ));

test("reports unknown unary rule fields as invalid", async () => {
  const report = await expectInvalid({
    kind: "inViewport",
    target: "target",
    surprise: true,
  });
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "invalid-rule",
      fieldPath: "surprise",
      code: "unknown-field",
    }),
  );
});

test("reports every invalid field on a unary rule rather than stopping at the first", async () => {
  const report = await expectInvalid({
    kind: "width",
    target: "",
    reference: "synthetic",
    range: { minPx: -1, maxPx: Number.POSITIVE_INFINITY, surprise: true },
    surprise: true,
  });
  expect(
    report.findings.map((finding) =>
      "fieldPath" in finding ? finding.fieldPath : undefined,
    ),
  ).toEqual([
    "reference",
    "surprise",
    "target",
    "range.surprise",
    "range.minPx",
    "range.maxPx",
  ]);
  expect(report.rules.failed).toBe(1);
});

test("public unary helpers throw synchronously for invalid runtime ranges", () => {
  expect(() => width("target", {})).toThrow(TypeError);
  expect(() => height("target", { minPx: -1 })).toThrow(TypeError);
  expect(() => width("target", { maxPx: Number.POSITIVE_INFINITY })).toThrow(
    TypeError,
  );
  expect(() =>
    height("target", { minPx: "10" } as unknown as { minPx: number }),
  ).toThrow(TypeError);
});

test("public unary helpers throw synchronously for invalid runtime targets", () => {
  expect(() => width("", { minPx: 10 })).toThrow(TypeError);
  expect(() => height(42 as unknown as string, { minPx: 10 })).toThrow(
    TypeError,
  );
});
