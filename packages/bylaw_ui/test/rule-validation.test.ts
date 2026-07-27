import { expect, test } from "bun:test";

import {
  align,
  checkLayout,
  leftOf,
  notOverlap,
  overlap,
  sameSize,
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
  expect(report.passed).toBe(false);
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 1, skipped: 0 });
  expect(report.findings.some((finding) => finding.category === "invalid-rule")).toBe(
    true,
  );

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

const requiredIdCases = [
  ["reports an empty subject test ID as invalid", { kind: "sameSize", subject: "", reference: "b" }, "subject", "invalid-value"],
  ["reports an empty reference test ID as invalid", { kind: "sameSize", subject: "a", reference: "" }, "reference", "invalid-value"],
  ["reports a missing subject test ID as invalid", { kind: "sameSize", reference: "b" }, "subject", "missing-field"],
  ["reports a missing reference test ID as invalid", { kind: "sameSize", subject: "a" }, "reference", "missing-field"],
  ["reports a non-string subject test ID as invalid at runtime", { kind: "sameSize", subject: 1, reference: "b" }, "subject", "invalid-type"],
  ["reports a non-string reference test ID as invalid at runtime", { kind: "sameSize", subject: "a", reference: false }, "reference", "invalid-type"],
] as const;

for (const [name, rule, path, code] of requiredIdCases) {
  test(name, () => expectInvalid(rule, path, code));
}

test("reports an unknown rule kind as invalid", () =>
  expectInvalid(
    { kind: "near", subject: "a", reference: "b" },
    "kind",
    "invalid-value",
  ));

test("reports an unknown alignment value as invalid", () =>
  expectInvalid(
    { kind: "align", subject: "a", reference: "b", alignment: "middle" },
    "alignment",
    "invalid-value",
  ));

test("reports a missing rule kind as invalid", () =>
  expectInvalid({ subject: "a", reference: "b" }, "kind", "missing-field"));

test("reports a null rule as invalid", () => expectInvalid(null, "$", "invalid-type"));
test("reports a non-object rule as invalid", () =>
  expectInvalid("sameSize", "$", "invalid-type"));

for (const [name, value, pass] of [
  ["uses zero tolerance when tolerance is omitted", undefined, true],
  ["accepts zero tolerance", 0, true],
  ["accepts a positive fractional tolerance", 0.1, true],
  ["reports a negative tolerance as invalid", -1, false],
  ["reports NaN tolerance as invalid", Number.NaN, false],
  ["reports positive infinity tolerance as invalid", Number.POSITIVE_INFINITY, false],
  ["reports negative infinity tolerance as invalid", Number.NEGATIVE_INFINITY, false],
  ["reports a nonnumeric tolerance as invalid at runtime", "1", false],
] as const) {
  test(name, async () => {
    const rule = {
      kind: "sameSize",
      subject: "a",
      reference: "b",
      ...(value === undefined ? {} : { options: { tolerancePx: value } }),
    };
    const report = await validate(rule);

    if (pass) {
      expect(report.findings.some((finding) => finding.category === "invalid-rule")).toBe(
        false,
      );
    } else {
      expect(report.findings).toContainEqual(
        expect.objectContaining({
          category: "invalid-rule",
          fieldPath: "options.tolerancePx",
        }),
      );
    }
  });
}

const validRanges = [
  ["accepts a gap range containing only a minimum", leftOf("a", "b", { gap: { minPx: 1 } })],
  ["accepts a gap range containing only a maximum", leftOf("a", "b", { gap: { maxPx: 1 } })],
  ["accepts a gap range containing both bounds", leftOf("a", "b", { gap: { minPx: 1, maxPx: 2 } })],
  ["accepts equal gap bounds, including zero", leftOf("a", "b", { gap: { minPx: 0, maxPx: 0 } })],
  ["accepts an overlap range containing only a minimum", overlap("a", "b", { horizontal: { minPx: 0 } })],
  ["accepts an overlap range containing only a positive maximum", overlap("a", "b", { horizontal: { maxPx: 1 } })],
  ["accepts an overlap range containing both bounds when its maximum is positive", overlap("a", "b", { horizontal: { minPx: 0, maxPx: 1 } })],
  ["accepts equal positive overlap bounds", overlap("a", "b", { horizontal: { minPx: 1, maxPx: 1 } })],
] as const;

for (const [name, rule] of validRanges) {
  test(name, async () => {
    const report = await validate(rule);
    expect(report.findings.some((finding) => finding.category === "invalid-rule")).toBe(
      false,
    );
  });
}

const invalidRanges = [
  ["reports an empty range as invalid", {}, "options.gap"],
  ["reports a negative minimum bound as invalid", { minPx: -1 }, "options.gap.minPx"],
  ["reports a negative maximum bound as invalid", { maxPx: -1 }, "options.gap.maxPx"],
  ["reports a minimum greater than the maximum as invalid", { minPx: 2, maxPx: 1 }, "options.gap"],
  ["reports a NaN range bound as invalid", { minPx: Number.NaN }, "options.gap.minPx"],
  ["reports an infinite range bound as invalid", { maxPx: Number.POSITIVE_INFINITY }, "options.gap.maxPx"],
  ["reports a nonnumeric range bound as invalid at runtime", { minPx: "1" }, "options.gap.minPx"],
] as const;

for (const [name, gap, path] of invalidRanges) {
  test(name, () =>
    expectInvalid(
      { kind: "leftOf", subject: "a", reference: "b", options: { gap } },
      path,
    ));
}

test("reports a non-object options value as invalid at runtime", () =>
  expectInvalid(
    { kind: "sameSize", subject: "a", reference: "b", options: "no" },
    "options",
    "invalid-type",
  ));

for (const [name, kind, field] of [
  ["reports a non-object gap range as invalid at runtime", "leftOf", "gap"],
  ["reports a non-object horizontal overlap range as invalid at runtime", "overlap", "horizontal"],
  ["reports a non-object vertical overlap range as invalid at runtime", "overlap", "vertical"],
] as const) {
  test(name, () =>
    expectInvalid(
      { kind, subject: "a", reference: "b", options: { [field]: 1 } },
      `options.${field}`,
      "invalid-type",
    ));
}

test("reports every invalid field on a rule rather than stopping at the first", async () => {
  const report = await expectInvalid({
    kind: "align",
    subject: "",
    reference: 1,
    alignment: "middle",
    surprise: true,
    options: { tolerancePx: -1, mystery: 2 },
  });
  expect(report.findings.length).toBe(6);
});

test("counts a rule with several invalid fields as one failed rule", async () => {
  const report = await expectInvalid({
    kind: "sameSize",
    subject: "",
    reference: "",
  });
  expect(report.findings.length).toBe(2);
  expect(report.rules.failed).toBe(1);
});

test("continues evaluating valid rules after an invalid rule", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [
      { kind: "sameSize", subject: "", reference: "b" } as LayoutRule,
      { kind: "sameSize", subject: "missing", reference: "also-missing" },
    ],
  });
  expect(report.rules).toEqual({ total: 2, passed: 0, failed: 1, skipped: 1 });
});

test("does not report a geometric violation for an invalid rule", async () => {
  const report = await expectInvalid({
    kind: "sameSize",
    subject: "",
    reference: "b",
  });
  expect(report.findings.some((finding) => finding.category === "layout")).toBe(
    false,
  );
});

test("identifies the invalid rule without prescribing an internal validation object shape", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [
      sameSize("a", "b"),
      { kind: "sameSize", subject: "", reference: "b" } as LayoutRule,
    ],
  });
  expect(report.findings).toContainEqual(
    expect.objectContaining({ category: "invalid-rule", ruleIndex: 1 }),
  );
});

test("reports an unknown top-level rule field as invalid", () =>
  expectInvalid(
    { kind: "sameSize", subject: "a", reference: "b", unknown: true },
    "unknown",
    "unknown-field",
  ));

test("reports an unknown option field as invalid", () =>
  expectInvalid(
    {
      kind: "sameSize",
      subject: "a",
      reference: "b",
      options: { unknown: true },
    },
    "options.unknown",
    "unknown-field",
  ));

test("reports options unsupported by the rule kind as invalid", () =>
  expectInvalid(
    {
      kind: "notOverlap",
      subject: "a",
      reference: "b",
      options: {},
    },
    "options",
    "invalid-value",
  ));

test("treats an undefined optional property as omitted", async () => {
  const report = await validate({
    kind: "sameSize",
    subject: "a",
    reference: "b",
    options: { tolerancePx: undefined },
  });
  expect(report.findings.some((finding) => finding.category === "invalid-rule")).toBe(
    false,
  );
});

test("reports a null optional property as invalid", () =>
  expectInvalid(
    {
      kind: "sameSize",
      subject: "a",
      reference: "b",
      options: { tolerancePx: null },
    },
    "options.tolerancePx",
    "invalid-type",
  ));

test("reports every unknown and invalid field on the same rule", async () => {
  const report = await expectInvalid({
    kind: "leftOf",
    subject: "a",
    reference: "b",
    extra: 1,
    options: { tolerancePx: -1, extra: 2 },
  });
  expect(report.findings.map((finding) => "fieldPath" in finding && finding.fieldPath)).toEqual([
    "extra",
    "options.extra",
    "options.tolerancePx",
  ]);
});

for (const [name, axis, range] of [
  ["reports a horizontal overlap maximum of zero as invalid", "horizontal", { maxPx: 0 }],
  ["reports a vertical overlap maximum of zero as invalid", "vertical", { maxPx: 0 }],
  ["reports an overlap range fixed at zero as invalid", "horizontal", { minPx: 0, maxPx: 0 }],
] as const) {
  test(name, () =>
    expectInvalid(
      { kind: "overlap", subject: "a", reference: "b", options: { [axis]: range } },
      `options.${axis}.maxPx`,
      "invalid-value",
    ));
}

test("continues accepting zero as an overlap minimum", () => {
  expect(() => overlap("a", "b", { horizontal: { minPx: 0 } })).not.toThrow();
});

test("accepts a non-empty test ID containing leading or trailing whitespace", () => {
  expect(() => sameSize(" a ", " b ")).not.toThrow();
});

test("accepts a non-empty test ID containing only whitespace", () => {
  expect(() => sameSize(" ", "\t")).not.toThrow();
});

test("does not trim test IDs before resolution", () => {
  expect(sameSize(" a ", "b").subject).toBe(" a ");
});

test("public helpers throw synchronously for runtime-invalid subject IDs", () => {
  expect(() => sameSize("" as string, "b")).toThrow(TypeError);
  expect(() => sameSize(1 as never, "b")).toThrow(TypeError);
});

test("public helpers throw synchronously for runtime-invalid reference IDs", () => {
  expect(() => sameSize("a", "" as string)).toThrow(TypeError);
  expect(() => sameSize("a", null as never)).toThrow(TypeError);
});

test("align throws synchronously for a runtime-invalid alignment value", () => {
  expect(() => align("a", "b", "middle" as never)).toThrow(TypeError);
});

test("public helpers throw synchronously for invalid runtime options", () => {
  expect(() => sameSize("a", "b", { tolerancePx: -1 })).toThrow(TypeError);
});

test("public helpers throw synchronously for unknown option fields", () => {
  expect(() =>
    sameSize("a", "b", { tolerancePx: 1, unknown: true } as never),
  ).toThrow(TypeError);
});

test("public helpers throw synchronously for options unsupported by their rule kind", () => {
  expect(() => (notOverlap as never as (...args: unknown[]) => unknown)("a", "b", {})).toThrow(
    TypeError,
  );
});

test("the same invalid values in caller-constructed inline rules become findings", async () => {
  const report = await expectInvalid({
    kind: "sameSize",
    subject: "",
    reference: "b",
    options: { tolerancePx: -1 },
  });
  expect(report.findings.length).toBe(2);
});
