import { expect, test } from "bun:test";

import {
  assertLayout,
  checkLayout,
  height,
  inViewport,
  width,
  type LayoutRule,
} from "bylaw-ui";
import {
  fixtureAdapter,
  hidden,
  rect,
  unresolved,
  visible,
} from "./support";

test("width produces a unary rule without a reference target", () => {
  expect(width("sidebar", { minPx: 260, maxPx: 280 })).toEqual({
    kind: "width",
    target: "sidebar",
    range: { minPx: 260, maxPx: 280 },
  });
  expect(width("sidebar", { minPx: 260 })).not.toHaveProperty("reference");
});

test("height produces a unary rule without a reference target", () => {
  expect(height("toolbar", { minPx: 48, maxPx: 48 })).toEqual({
    kind: "height",
    target: "toolbar",
    range: { minPx: 48, maxPx: 48 },
  });
  expect(height("toolbar", { minPx: 48 })).not.toHaveProperty("reference");
});

test("inViewport produces a unary rule without a reference target", () => {
  expect(inViewport("dialog")).toEqual({
    kind: "inViewport",
    target: "dialog",
  });
  expect(inViewport("dialog")).not.toHaveProperty("reference");
});

test("unary rules resolve and measure only their target", async () => {
  const measured: string[][] = [];
  const report = await checkLayout({
    adapter: fixtureAdapter(
      { target: visible("target", rect(0, 0, 10, 10)) },
      (testIds) => measured.push([...testIds]),
    ),
    rules: [
      width("target", { minPx: 10 }),
      height("target", { minPx: 10 }),
      inViewport("target"),
    ],
  });
  expect(measured).toEqual([["target"]]);
  expect(report.rules.passed).toBe(3);
});

test("a unary rule with a missing target is skipped with a missing-element finding", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ target: unresolved("target", 0) }),
    rules: [width("target", { minPx: 10 })],
  });
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 0, skipped: 1 });
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "element-resolution",
      code: "missing-element",
      operand: "target",
      target: "target",
      testId: "target",
      actual: { matchCount: 0 },
    }),
  );
});

test("a unary rule with a duplicated target is skipped with a duplicate-element finding", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ target: unresolved("target", 2) }),
    rules: [height("target", { minPx: 10 })],
  });
  expect(report.rules.skipped).toBe(1);
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "element-resolution",
      code: "duplicate-element",
      operand: "target",
      target: "target",
      actual: { matchCount: 2 },
    }),
  );
});

test("a unary rule with a hidden target is skipped with a hidden-element finding", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ target: hidden("target") }),
    rules: [inViewport("target")],
  });
  expect(report.rules.skipped).toBe(1);
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "element-visibility",
      code: "hidden-element",
      operand: "target",
      target: "target",
      actual: { hidden: true },
    }),
  );
});

test("a unary rule with a zero-width target is skipped with a zero-size-element finding", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ target: visible("target", rect(0, 0, 0, 10)) }),
    rules: [width("target", { minPx: 0 })],
  });
  expect(report.rules.skipped).toBe(1);
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "element-visibility",
      code: "zero-size-element",
      operand: "target",
      actual: { hidden: false, width: 0, height: 10 },
    }),
  );
});

test("a unary rule with a zero-height target is skipped with a zero-size-element finding", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ target: visible("target", rect(0, 0, 10, 0)) }),
    rules: [height("target", { minPx: 0 })],
  });
  expect(report.rules.skipped).toBe(1);
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "element-visibility",
      code: "zero-size-element",
      operand: "target",
      actual: { hidden: false, width: 10, height: 0 },
    }),
  );
});

test("a width finding reports the actual width and expected pixel range", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ panel: visible("panel", rect(0, 0, 241.5, 100)) }),
    rules: [width("panel", { minPx: 260, maxPx: 280 })],
  });
  expect(report.findings[0]).toMatchObject({
    relationship: "width",
    expected: { range: { minPx: 260, maxPx: 280 } },
    actual: { widthPx: 241.5 },
  });
});

test("a height finding reports the actual height and expected pixel range", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ toolbar: visible("toolbar", rect(0, 0, 100, 39.25)) }),
    rules: [height("toolbar", { minPx: 48, maxPx: 48 })],
  });
  expect(report.findings[0]).toMatchObject({
    relationship: "height",
    expected: { range: { minPx: 48, maxPx: 48 } },
    actual: { heightPx: 39.25 },
  });
});

test("an inViewport finding reports the actual target and viewport edges", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      dialog: visible("dialog", rect(-5, 700, 1_300, 40)),
    }),
    rules: [inViewport("dialog")],
  });
  expect(report.findings[0]).toMatchObject({
    relationship: "inViewport",
    expected: {
      viewport: { leftPx: 0, topPx: 0, rightPx: 1280, bottomPx: 720 },
    },
    actual: {
      target: { leftPx: -5, topPx: 700, rightPx: 1295, bottomPx: 740 },
    },
  });
});

test("unary findings identify the subject without a reference target", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ sidebar: visible("sidebar", rect(0, 0, 200, 100)) }),
    rules: [width("sidebar", { minPx: 260 })],
  });
  expect(report.findings[0]).toMatchObject({ target: "sidebar" });
  expect(report.findings[0]).not.toHaveProperty("reference");
  expect(report.findings[0]).not.toHaveProperty("subject");
});

test("several failing unary rules produce distinct findings and accurate rule counts", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      sidebar: visible("sidebar", rect(-1, 0, 200, 30)),
    }),
    rules: [
      width("sidebar", { minPx: 260 }),
      height("sidebar", { minPx: 48 }),
      inViewport("sidebar"),
    ],
  });
  expect(report.rules).toEqual({ total: 3, passed: 0, failed: 3, skipped: 0 });
  expect(
    report.findings.map((finding) =>
      "relationship" in finding ? finding.relationship : undefined,
    ),
  ).toEqual(["width", "height", "inViewport"]);
});

test("a width assertion error includes the actual width and expected pixel range", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ sidebar: visible("sidebar", rect(0, 0, 241.5, 100)) }),
    rules: [width("sidebar", { minPx: 260, maxPx: 280 })],
  });
  expect(() => assertLayout(report)).toThrow(
    expect.objectContaining({
      message: expect.stringMatching(/sidebar[\s\S]*241\.5[\s\S]*260[\s\S]*280/i),
    }),
  );
});

test("a height assertion error includes the actual height and expected pixel range", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ toolbar: visible("toolbar", rect(0, 0, 100, 39.25)) }),
    rules: [height("toolbar", { minPx: 48, maxPx: 48 })],
  });
  expect(() => assertLayout(report)).toThrow(
    expect.objectContaining({
      message: expect.stringMatching(/toolbar[\s\S]*39\.25[\s\S]*48/i),
    }),
  );
});

test("an inViewport assertion error includes the actual target and viewport edges", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ dialog: visible("dialog", rect(-5, 700, 1_300, 40)) }),
    rules: [inViewport("dialog")],
  });
  expect(() => assertLayout(report)).toThrow(
    expect.objectContaining({
      message: expect.stringMatching(/dialog[\s\S]*-5[\s\S]*700[\s\S]*1295[\s\S]*740/i),
    }),
  );
});

test("an inViewport assertion error includes the expected viewport constraint", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({ dialog: visible("dialog", rect(-1, 0, 100, 100)) }),
    rules: [inViewport("dialog")],
  });
  expect(() => assertLayout(report)).toThrow(
    expect.objectContaining({
      message: expect.stringMatching(/viewport[\s\S]*0[\s\S]*1280[\s\S]*720/i),
    }),
  );
});

test("the README documents unary geometry rules and when to prefer relative rules", async () => {
  const readme = await Bun.file(new URL("../README.md", import.meta.url)).text();
  expect(readme).toContain("width(");
  expect(readme).toContain("height(");
  expect(readme).toContain("inViewport(");
  expect(readme).toMatch(/unary|single target/i);
  expect(readme).toMatch(/relative|sameWidth|sameHeight|sameSize/i);
});
