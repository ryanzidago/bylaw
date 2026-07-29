import { expect, test } from "bun:test";

import {
  align,
  checkLayout,
  inside,
  leftOf,
  LayoutAssertionError,
  notOverlap,
  overlap,
  sameSize,
  sameWidth,
  type LayoutRule,
} from "bylaw-ui";
import { evaluateGeometry } from "../src/internal/geometry";
import { LayoutExecutionError } from "../src/internal/snapshot";
import { fixtureAdapter, hidden, rect, unresolved, visible } from "./support";

async function checkInline(rule: LayoutRule) {
  return checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect()),
    }),
    rules: [rule],
  });
}

test("helpers return the canonical public inline rule representation", () => {
  expect(align("avatar", "timeline", "centerY", { tolerancePx: 1 })).toEqual({
    kind: "align",
    subject: "avatar",
    reference: "timeline",
    alignment: "centerY",
    options: { tolerancePx: 1 },
  });
  expect(leftOf("avatar", "timeline", { gap: { minPx: 8, maxPx: 16 } })).toEqual(
    {
      kind: "leftOf",
      subject: "avatar",
      reference: "timeline",
      options: { gap: { minPx: 8, maxPx: 16 } },
    },
  );
});

test("helper-produced rules remain valid after a JSON round trip", async () => {
  const rule = JSON.parse(
    JSON.stringify(sameSize("a", "b", { tolerancePx: 1 })),
  ) as LayoutRule;
  expect((await checkInline(rule)).passed).toBe(true);
});

test("accepts a caller-constructed align rule", async () => {
  const rule: LayoutRule = {
    kind: "align",
    subject: "a",
    reference: "b",
    alignment: "left",
  };
  expect((await checkInline(rule)).passed).toBe(true);
});

test("accepts caller-constructed ordering rules", async () => {
  const rule: LayoutRule = {
    kind: "leftOf",
    subject: "a",
    reference: "b",
    options: { tolerancePx: 10 },
  };
  expect((await checkInline(rule)).passed).toBe(true);
});

test("accepts caller-constructed overlap and not-overlap rules", async () => {
  const overlapping: LayoutRule = {
    kind: "overlap",
    subject: "a",
    reference: "b",
  };
  const separate: LayoutRule = {
    kind: "notOverlap",
    subject: "a",
    reference: "b",
  };
  expect((await checkInline(overlapping)).passed).toBe(true);
  expect(
    (
      await checkLayout({
        adapter: fixtureAdapter({
          a: visible("a", rect()),
          b: visible("b", rect(20)),
        }),
        rules: [separate],
      })
    ).passed,
  ).toBe(true);
});

test("accepts caller-constructed containment and size rules", async () => {
  const rules: LayoutRule[] = [
    { kind: "inside", subject: "a", reference: "b" },
    { kind: "sameWidth", subject: "a", reference: "b" },
    { kind: "sameHeight", subject: "a", reference: "b" },
    { kind: "sameSize", subject: "a", reference: "b" },
  ];
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect()),
    }),
    rules,
  });
  expect(report.rules.passed).toBe(4);
});

test("preserves test IDs exactly without trimming or normalization", () => {
  expect(sameSize(" a ", "\tb\n")).toMatchObject({
    subject: " a ",
    reference: "\tb\n",
  });
});

test("reports passed and rule counts through stable public fields", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect()),
      missing: unresolved("missing", 0),
    }),
    rules: [
      sameSize("a", "b"),
      sameWidth("a", "missing"),
      { kind: "sameSize", subject: "", reference: "b" } as LayoutRule,
    ],
  });
  expect(report).toMatchObject({
    passed: false,
    rules: { total: 3, passed: 1, failed: 1, skipped: 1 },
    findings: expect.any(Array),
  });
});

test("every finding exposes a stable category and code", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [{ kind: "sameSize", subject: "", reference: "b" } as LayoutRule],
  });
  expect(report.findings[0]).toMatchObject({
    category: "invalid-rule",
    code: "invalid-value",
  });
});

test("every finding exposes a stable machine-readable semantic category", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings[0]?.category).toBe("layout");
});

test("every rule-associated finding exposes its zero-based rule index", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "a"), sameSize("a", "b")],
  });
  expect(report.findings.map(({ ruleIndex }) => ruleIndex)).toEqual([1]);
});

test("findings identify the supplied rule by its input position", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "a"), sameSize("a", "b")],
  });
  expect(report.findings[0]?.ruleIndex).toBe(1);
});

test("operand findings expose subject and reference test IDs", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ a: unresolved("a", 0), b: visible("b", rect()) }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings[0]).toMatchObject({ subject: "a", reference: "b" });
});

test("geometric findings expose the subject and reference test IDs", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings[0]).toMatchObject({ subject: "a", reference: "b" });
});

test("invalid-rule findings expose machine-readable field paths and reasons", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [{ kind: "sameSize", subject: "", reference: "b" } as LayoutRule],
  });
  expect(report.findings[0]).toMatchObject({
    fieldPath: "subject",
    reason: expect.any(String),
  });
});

test("element-resolution findings distinguish missing and duplicate elements", async () => {
  const missing = await checkLayout({
    adapter: fixtureAdapter({ a: unresolved("a", 0), b: visible("b", rect()) }),
    rules: [sameSize("a", "b")],
  });
  const duplicate = await checkLayout({
    adapter: fixtureAdapter({ a: unresolved("a", 2), b: visible("b", rect()) }),
    rules: [sameSize("a", "b")],
  });
  expect([missing.findings[0]?.code, duplicate.findings[0]?.code]).toEqual([
    "missing-element",
    "duplicate-element",
  ]);
});

test("element-visibility findings identify the unavailable operand", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ a: hidden("a"), b: visible("b", rect()) }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings[0]).toMatchObject({
    code: "hidden-element",
    operand: "subject",
    testId: "a",
  });
});

test("layout findings identify the violated relationship", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings[0]).toMatchObject({ relationship: "sameSize" });
});

test("layout findings expose expected constraints as structured data", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b", { tolerancePx: 2 })],
  });
  expect(report.findings[0]).toMatchObject({ expected: { tolerancePx: 2 } });
});

test("layout findings expose measured values as structured data", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings[0]).toMatchObject({
    actual: { widthDifferencePx: 10, heightDifferencePx: 10 },
  });
});

test("alignment findings expose the measured difference in CSS pixels", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect(1)),
      b: visible("b", rect(3.5)),
    }),
    rules: [align("a", "b", "left")],
  });
  expect(report.findings[0]).toMatchObject({ actual: { differencePx: 2.5 } });
});

test("ordering findings distinguish boundary crossing from an out-of-range valid gap", async () => {
  const crossing = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect(-9)),
      b: visible("b", rect()),
    }),
    rules: [leftOf("a", "b", { gap: { minPx: 2 } })],
  });
  const gap = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect(-11)),
      b: visible("b", rect()),
    }),
    rules: [leftOf("a", "b", { gap: { minPx: 2 } })],
  });
  expect([crossing.findings[0]?.code, gap.findings[0]?.code]).toEqual([
    "ordering-violation",
    "gap-out-of-range",
  ]);
});

test("consumers can interpret findings without parsing human-readable messages", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  });
  const finding = report.findings[0]!;
  expect({
    category: finding.category,
    code: finding.code,
    ruleIndex: finding.ruleIndex,
    actual: "actual" in finding ? finding.actual : null,
  }).toEqual({
    category: "layout",
    code: "size-mismatch",
    ruleIndex: 0,
    actual: {
      subjectWidthPx: 10,
      referenceWidthPx: 20,
      widthDifferencePx: 10,
      subjectHeightPx: 10,
      referenceHeightPx: 20,
      heightDifferencePx: 10,
    },
  });
});

test("a JSON round trip preserves the report public semantics", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  });
  expect(JSON.parse(JSON.stringify(report))).toEqual(report);
});

test("geometry rules can be evaluated from measured rectangles without Playwright", () => {
  expect(
    evaluateGeometry(sameSize("a", "b"), 0, rect(), rect()),
  ).toEqual([]);
});

test("geometry evaluation can be tested without launching a browser", () => {
  expect(
    evaluateGeometry(inside("a", "b"), 0, rect(1, 1, 2, 2), rect()),
  ).toEqual([]);
});

test("pure geometry evaluation performs no browser operations", () => {
  const originalDocument = globalThis.document;
  expect(evaluateGeometry(notOverlap("a", "b"), 0, rect(), rect(20))).toEqual([]);
  expect(globalThis.document).toBe(originalDocument);
});

test("V1 does not expose caller-defined adapter construction as a supported public API", async () => {
  const root = await import("bylaw-ui");
  expect(root).not.toHaveProperty("createInternalAdapter");
  expect(root).not.toHaveProperty("InternalAdapter");
});

test("importing the package root does not load Playwright", async () => {
  const rootBundle = await Bun.file(
    new URL("../dist/index.js", import.meta.url),
  ).text();
  expect(rootBundle).not.toContain("playwright-core");
  expect(rootBundle).not.toContain("chromium");
  expect(rootBundle).not.toContain(".launch(");
});

test("preserves the original adapter error identity", async () => {
  const original = new Error("adapter failed");
  const caught = await checkLayout({
    adapter: fixtureAdapter({}, () => {
      throw original;
    }),
    rules: [sameSize("a", "b")],
  }).catch((error: unknown) => error);
  expect(caught).toBe(original);
});

test("rejects with the original error when the adapter throws", async () => {
  const original = new Error("original");
  const caught = await checkLayout({
    adapter: fixtureAdapter({}, () => {
      throw original;
    }),
    rules: [sameSize("a", "b")],
  }).catch((error: unknown) => error);
  expect(caught).toBe(original);
});

test("uses a distinct execution error for malformed adapter output", () => {
  expect(new LayoutExecutionError("malformed")).not.toBeInstanceOf(
    LayoutAssertionError,
  );
  expect(new LayoutExecutionError("malformed").name).toBe("LayoutExecutionError");
});

test("adapter and execution errors are not instances of LayoutAssertionError", () => {
  expect(new Error("adapter")).not.toBeInstanceOf(LayoutAssertionError);
  expect(new LayoutExecutionError("execution")).not.toBeInstanceOf(
    LayoutAssertionError,
  );
});

test("reports contain only finite JSON data and no browser or adapter objects", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect(0.25, -1.5, 10.75, 20.5)),
      b: visible("b", rect(2.5, 3.25, 30.5, 40.75)),
    }),
    rules: [
      align("a", "b", "left"),
      overlap("a", "b", { horizontal: { minPx: 20 } }),
      inside("a", "b"),
      sameSize("a", "b"),
    ],
  });
  const serialized = JSON.stringify(report);
  const roundTrip = JSON.parse(serialized) as unknown;

  function audit(value: unknown): void {
    if (typeof value === "number") {
      expect(Number.isFinite(value)).toBe(true);
      return;
    }

    if (Array.isArray(value)) {
      value.forEach(audit);
      return;
    }

    if (typeof value === "object" && value !== null) {
      for (const [key, nested] of Object.entries(value)) {
        expect([
          "adapter",
          "browser",
          "document",
          "elementHandle",
          "measure",
          "page",
          "rect",
          "viewport",
        ]).not.toContain(key);
        audit(nested);
      }
    }
  }

  audit(roundTrip);
  expect(serialized).not.toMatch(/NaN|Infinity/);
  expect(roundTrip).toEqual(report);
});
