import { expect, test } from "bun:test";

import { checkLayout, sameSize } from "bylaw-ui";
import { fixtureAdapter, hidden, rect, unresolved, visible } from "./support";

test("evaluates a rule when both test IDs resolve exactly once", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect()),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.passed).toBe(true);
});

for (const [name, subjectCount, referenceCount, expectedCodes] of [
  ["reports a missing subject element", 0, 1, ["missing-element"]],
  ["reports a missing reference element", 1, 0, ["missing-element"]],
  [
    "reports both elements when both are missing",
    0,
    0,
    ["missing-element", "missing-element"],
  ],
  ["reports a duplicated subject test ID", 2, 1, ["duplicate-element"]],
  ["reports a duplicated reference test ID", 1, 2, ["duplicate-element"]],
  [
    "reports both elements when both test IDs are duplicated",
    2,
    3,
    ["duplicate-element", "duplicate-element"],
  ],
] as const) {
  test(name, async () => {
    const measurements = {
      subject:
        subjectCount === 1
          ? visible("subject", rect())
          : unresolved("subject", subjectCount),
      reference:
        referenceCount === 1
          ? visible("reference", rect())
          : unresolved("reference", referenceCount),
    };
    const report = await checkLayout({
      adapter: fixtureAdapter(measurements),
      rules: [sameSize("subject", "reference")],
    });
    expect(report.rules).toEqual({
      total: 1,
      passed: 0,
      failed: 0,
      skipped: 1,
    });
    expect(report.findings.map(({ code }) => code)).toEqual([...expectedCodes]);
  });
}

test("treats duplicate matches as unresolved even when one match is visible", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: unresolved("subject", 2),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.findings[0]?.code).toBe("duplicate-element");
  expect(report.rules.skipped).toBe(1);
});

test("does not choose an arbitrary element from duplicate matches", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: unresolved("subject", 2),
      reference: visible("reference", rect(0, 0, 999, 999)),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.findings.some((finding) => finding.category === "layout")).toBe(
    false,
  );
});

test("evaluates a rule whose subject and reference use the same test ID", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ same: visible("same", rect()) }),
    rules: [sameSize("same", "same")],
  });
  expect(report).toMatchObject({
    passed: true,
    rules: { passed: 1, failed: 0, skipped: 0 },
  });
});

for (const [name, measurements] of [
  [
    "skips a rule whose subject measurement is unavailable",
    {
      subject: unresolved("subject", 0),
      reference: visible("reference", rect()),
    },
  ],
  [
    "skips a rule whose reference measurement is unavailable",
    { subject: visible("subject", rect()), reference: hidden("reference") },
  ],
] as const) {
  test(name, async () => {
    const report = await checkLayout({
      adapter: fixtureAdapter(measurements),
      rules: [sameSize("subject", "reference")],
    });
    expect(report.rules.skipped).toBe(1);
  });
}

test("skips every affected rule when an unavailable element is shared", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      shared: unresolved("shared", 0),
      one: visible("one", rect()),
      two: visible("two", rect()),
    }),
    rules: [sameSize("shared", "one"), sameSize("two", "shared")],
  });
  expect(report.rules.skipped).toBe(2);
  expect(report.findings.map(({ ruleIndex }) => ruleIndex)).toEqual([0, 1]);
});

test("continues evaluating rules that do not depend on an unavailable element", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      missing: unresolved("missing", 0),
      one: visible("one", rect()),
      two: visible("two", rect()),
    }),
    rules: [sameSize("missing", "one"), sameSize("one", "two")],
  });
  expect(report.rules).toEqual({ total: 2, passed: 1, failed: 0, skipped: 1 });
});

test("reports which rules were affected by an unavailable element", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      missing: unresolved("missing", 0),
      one: visible("one", rect()),
    }),
    rules: [sameSize("missing", "one"), sameSize("one", "missing")],
  });
  expect(report.findings).toEqual([
    expect.objectContaining({
      ruleIndex: 0,
      operand: "subject",
      testId: "missing",
    }),
    expect.objectContaining({
      ruleIndex: 1,
      operand: "reference",
      testId: "missing",
    }),
  ]);
});

test("does not report a skipped rule as a geometric violation", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: unresolved("subject", 0),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(
    report.findings.every((finding) => finding.category !== "layout"),
  ).toBe(true);
});
