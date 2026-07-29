import { expect, test } from "bun:test";

import {
  checkLayout,
  leftOf,
  sameHeight,
  sameSize,
  sameWidth,
  type LayoutRule,
} from "bylaw-ui";
import { fixtureAdapter, hidden, rect, unresolved, visible } from "./support";

test("returns a passing report for an empty rule list", async () => {
  const report = await checkLayout({ adapter: fixtureAdapter({}), rules: [] });
  expect(report.passed).toBe(true);
});

test("returns a passing report when every rule passes", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect()),
    }),
    rules: [sameSize("a", "b"), sameWidth("a", "b")],
  });
  expect(report).toMatchObject({
    passed: true,
    rules: { total: 2, passed: 2, failed: 0, skipped: 0 },
  });
});

test("returns a failing report when any rule fails", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(20, 0, 11, 10)),
    }),
    rules: [sameWidth("a", "b")],
  });
  expect(report.passed).toBe(false);
});

test("reports the total number of supplied rules", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [
      { kind: "sameSize", subject: "", reference: "b" } as LayoutRule,
      { kind: "sameSize", subject: "", reference: "b" } as LayoutRule,
    ],
  });
  expect(report.rules.total).toBe(2);
});

test("reports the number of passed rules", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect()),
    }),
    rules: [sameWidth("a", "b"), sameHeight("a", "b")],
  });
  expect(report.rules.passed).toBe(2);
});

test("reports the number of failed rules", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 11, 12)),
    }),
    rules: [sameWidth("a", "b"), sameHeight("a", "b")],
  });
  expect(report.rules.failed).toBe(2);
});

test("reports the number of skipped rules", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ a: unresolved("a", 0), b: unresolved("b", 0) }),
    rules: [sameSize("a", "b"), sameSize("b", "a")],
  });
  expect(report.rules.skipped).toBe(2);
});

test("counts each rule once regardless of how many findings explain it", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ a: unresolved("a", 0), b: unresolved("b", 0) }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings).toHaveLength(2);
  expect(report.rules.skipped).toBe(1);
});

test("returns every independent rule failure in one report", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect(0, 0, 10, 10)),
      b: visible("b", rect(5, 0, 11, 12)),
    }),
    rules: [leftOf("a", "b"), sameWidth("a", "b"), sameHeight("a", "b")],
  });
  expect(report.findings).toHaveLength(3);
});

test("continues evaluating after the first rule failure", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect(0, 0, 10, 10)),
      b: visible("b", rect(0, 0, 11, 10)),
    }),
    rules: [sameWidth("a", "b"), sameHeight("a", "b")],
  });
  expect(report.rules).toMatchObject({ passed: 1, failed: 1 });
});

test("reports invalid rules alongside geometric failures", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [
      { kind: "sameSize", subject: "", reference: "b" } as LayoutRule,
      sameSize("a", "b"),
    ],
  });
  expect(report.findings.map(({ category }) => category)).toEqual([
    "invalid-rule",
    "layout",
  ]);
});

test("reports element failures alongside independent geometric failures", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      missing: unresolved("missing", 0),
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("missing", "a"), sameSize("a", "b")],
  });
  expect(report.findings.map(({ category }) => category)).toEqual([
    "element-resolution",
    "layout",
  ]);
});

test("does not mark a report as passed when it contains findings", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ a: hidden("a"), b: visible("b", rect()) }),
    rules: [sameSize("a", "b")],
  });
  expect(report.findings.length).toBeGreaterThan(0);
  expect(report.passed).toBe(false);
});

test("does not mark a report as passed when any rule is skipped", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ a: unresolved("a", 0), b: visible("b", rect()) }),
    rules: [sameSize("a", "b")],
  });
  expect(report.rules.skipped).toBe(1);
  expect(report.passed).toBe(false);
});

test("identifies the rule associated with a geometric failure", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "a"), sameSize("a", "b")],
  });
  expect(report.findings[0]?.ruleIndex).toBe(1);
});

test("identifies the subject and reference associated with a failure", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect()),
      card: visible("card", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("avatar", "card")],
  });
  expect(report.findings[0]).toMatchObject({
    subject: "avatar",
    reference: "card",
  });
});

test("includes enough expected and actual geometry to diagnose a failure", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b", { tolerancePx: 2 })],
  });
  expect(report.findings[0]).toMatchObject({
    expected: { tolerancePx: 2 },
    actual: { widthDifferencePx: 10, heightDifferencePx: 10 },
  });
});

test("preserves fractional values in diagnostic geometry", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect(0.25, 0, 10.5, 10)),
      b: visible("b", rect(1.75, 0, 11.75, 10)),
    }),
    rules: [sameWidth("a", "b")],
  });
  expect(report.findings[0]).toMatchObject({
    actual: { widthDifferencePx: 1.25 },
  });
});

test("produces a JSON-serializable report", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  });
  expect(JSON.parse(JSON.stringify(report))).toEqual(report);
});

test("produces deterministic findings for identical inputs", async () => {
  const input = {
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect(0, 0, 20, 20)),
    }),
    rules: [sameSize("a", "b")],
  };
  expect(await checkLayout(input)).toEqual(await checkLayout(input));
});

test("counts an invalid rule with an unavailable operand as failed rather than skipped", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [
      { kind: "sameSize", subject: "", reference: "missing" } as LayoutRule,
    ],
  });
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 1, skipped: 0 });
});

test("does not report element-resolution findings for an invalid rule", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [
      { kind: "sameSize", subject: "", reference: "missing" } as LayoutRule,
    ],
  });
  expect(
    report.findings.some(({ category }) => category === "element-resolution"),
  ).toBe(false);
});

test("does not report visibility findings for an invalid rule", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ missing: hidden("missing") }),
    rules: [
      { kind: "sameSize", subject: "", reference: "missing" } as LayoutRule,
    ],
  });
  expect(
    report.findings.some(({ category }) => category === "element-visibility"),
  ).toBe(false);
});

test("counts identical supplied rules separately", async () => {
  const rule = sameSize("a", "b");
  const report = await checkLayout({
    adapter: fixtureAdapter({
      a: visible("a", rect()),
      b: visible("b", rect()),
    }),
    rules: [rule, rule],
  });
  expect(report.rules).toEqual({ total: 2, passed: 2, failed: 0, skipped: 0 });
});
