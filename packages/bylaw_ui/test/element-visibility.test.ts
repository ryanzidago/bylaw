import { expect, test } from "bun:test";

import { checkLayout, sameSize } from "bylaw-ui";
import { fixtureAdapter, hidden, rect, visible } from "./support";

test("evaluates a visible element with positive dimensions", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect()),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.passed).toBe(true);
});

for (const name of [
  "reports an element with the hidden attribute as unavailable",
  "reports an element under a hidden ancestor as unavailable",
  "reports an element with display none as unavailable",
  "reports an element under a display none ancestor as unavailable",
  "reports an element with visibility hidden as unavailable",
  "reports an element under a visibility hidden ancestor as unavailable",
  "reports an element with visibility collapse as unavailable",
  "reports an element with effective zero opacity as unavailable",
  "reports an element under a zero-opacity ancestor as unavailable",
]) {
  test(name, async () => {
    const report = await checkLayout({
      adapter: fixtureAdapter({
        subject: hidden("subject"),
        reference: visible("reference", rect()),
      }),
      rules: [sameSize("subject", "reference")],
    });
    expect(report.findings[0]).toMatchObject({
      category: "element-visibility",
      code: "hidden-element",
      operand: "subject",
    });
    expect(report.rules.skipped).toBe(1);
  });
}

for (const [name, subject] of [
  ["reports an element with zero width as unavailable", rect(0, 0, 0, 10)],
  ["reports an element with zero height as unavailable", rect(0, 0, 10, 0)],
  [
    "reports an element with zero width and zero height as unavailable",
    rect(0, 0, 0, 0),
  ],
] as const) {
  test(name, async () => {
    const report = await checkLayout({
      adapter: fixtureAdapter({
        subject: visible("subject", subject),
        reference: visible("reference", rect()),
      }),
      rules: [sameSize("subject", "reference")],
    });
    expect(report.findings[0]?.code).toBe("zero-size-element");
  });
}

test("treats an off-viewport element as visible", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect(-10_000, -10_000)),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.passed).toBe(true);
});

test("treats an element covered by another element as visible", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect()),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.passed).toBe(true);
});

test("skips rules that depend on a hidden element", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: hidden("subject"),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.rules.skipped).toBe(1);
});

test("continues evaluating rules that do not depend on a hidden element", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      hidden: hidden("hidden"),
      one: visible("one", rect()),
      two: visible("two", rect()),
    }),
    rules: [sameSize("hidden", "one"), sameSize("one", "two")],
  });
  expect(report.rules).toEqual({ total: 2, passed: 1, failed: 0, skipped: 1 });
});

test("treats an element with positive fractional opacity as visible", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      subject: visible("subject", rect()),
      reference: visible("reference", rect()),
    }),
    rules: [sameSize("subject", "reference")],
  });
  expect(report.passed).toBe(true);
});
