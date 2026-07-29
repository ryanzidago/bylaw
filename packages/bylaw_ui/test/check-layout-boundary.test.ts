import { expect, test } from "bun:test";

import { checkLayout, sameSize, type LayoutRule } from "bylaw-ui";
import { createInternalAdapter } from "../src/internal/adapter";
import { fixtureAdapter } from "./support";

test("an empty rule list returns a passing report without invoking Playwright", async () => {
  let invoked = false;
  const report = await checkLayout({
    adapter: fixtureAdapter({}, () => {
      invoked = true;
    }),
    rules: [],
  });
  expect(report).toEqual({
    passed: true,
    rules: { total: 0, passed: 0, failed: 0, skipped: 0 },
    findings: [],
  });
  expect(invoked).toBe(false);
});

test("an entirely invalid inline rule list returns findings without invoking Playwright", async () => {
  let invoked = false;
  const report = await checkLayout({
    adapter: fixtureAdapter({}, () => {
      invoked = true;
    }),
    rules: [{ kind: "sameSize", subject: "", reference: "b" } as LayoutRule],
  });
  expect(report.rules.failed).toBe(1);
  expect(invoked).toBe(false);
});

for (const [name, input, message] of [
  [
    "throws a TypeError when rules is missing",
    { adapter: fixtureAdapter({}) },
    "rules",
  ],
  ["throws a TypeError when the adapter is missing", { rules: [] }, "adapter"],
  [
    "throws a TypeError for an unsupported adapter value",
    { adapter: {}, rules: [] },
    "unsupported",
  ],
  [
    "throws a TypeError when rules is not an array",
    { adapter: fixtureAdapter({}), rules: {} },
    "array",
  ],
  [
    "throws a TypeError when the checkLayout argument is not an object",
    null,
    "object",
  ],
] as const) {
  test(name, () => {
    expect(checkLayout(input as never)).rejects.toThrow(
      expect.objectContaining({
        name: "TypeError",
        message: expect.stringContaining(message),
      }),
    );
  });
}

test("an empty rule list still validates that the adapter is present and supported", () => {
  expect(checkLayout({ rules: [] } as never)).rejects.toThrow(TypeError);
});

test("an entirely invalid inline rule list still validates that the adapter is present and supported", () => {
  expect(
    checkLayout({
      adapter: {},
      rules: [{ kind: "sameSize", subject: "", reference: "b" }],
    } as never),
  ).rejects.toThrow(TypeError);
});

test("checkLayout accepts only internally branded adapters", async () => {
  const adapter = createInternalAdapter(async () => ({
    viewport: { width: 1, height: 1 },
    elements: [],
  }));
  const report = await checkLayout({ adapter, rules: [] });
  expect(report.passed).toBe(true);
});

test("the package root does not export the internal adapter contract", async () => {
  const root = await import("bylaw-ui");
  expect(root).not.toHaveProperty("createInternalAdapter");
  expect(root).not.toHaveProperty("isInternalAdapter");
});

test("the package root does not export the internal geometry evaluator", async () => {
  const root = await import("bylaw-ui");
  expect(root).not.toHaveProperty("evaluateGeometry");
});

test("does not invoke the adapter twice for repeated element references", async () => {
  let calls = 0;
  const adapter = createInternalAdapter(async (testIds) => {
    calls += 1;
    return {
      viewport: { width: 100, height: 100 },
      elements: testIds.map((testId) => ({
        testId,
        count: 1,
        hidden: false,
        rect: { x: 0, y: 0, width: 10, height: 10 },
      })),
    };
  });
  await checkLayout({
    adapter,
    rules: [sameSize("a", "b"), sameSize("a", "b")],
  });
  expect(calls).toBe(1);
});
