import { expect, test } from "bun:test";

import * as bylawUi from "bylaw-ui";
import {
  checkLayout,
  height,
  inViewport,
  width,
  type HeightRule,
  type InViewportRule,
  type LayoutRule,
  type UnaryGeometryRule,
  type WidthRule,
} from "bylaw-ui";
import { fixtureAdapter, rect, visible } from "./support";

test("exports width from the package root", () => {
  expect(bylawUi.width).toBeFunction();
});

test("exports height from the package root", () => {
  expect(bylawUi.height).toBeFunction();
});

test("exports inViewport from the package root", () => {
  expect(bylawUi.inViewport).toBeFunction();
});

test("exports public unary geometry rule types", () => {
  const widthRule: WidthRule = width("sidebar", { minPx: 260 });
  const heightRule: HeightRule = height("toolbar", { maxPx: 48 });
  const viewportRule: InViewportRule = inViewport("dialog");
  const unaryRules: UnaryGeometryRule[] = [widthRule, heightRule, viewportRule];
  const layoutRules: LayoutRule[] = unaryRules;
  expect(layoutRules.map(({ kind }) => kind)).toEqual([
    "width",
    "height",
    "inViewport",
  ]);
});

test("width returns the canonical public inline rule representation", () => {
  expect(width("sidebar", { minPx: 260, maxPx: 280 })).toEqual({
    kind: "width",
    target: "sidebar",
    range: { minPx: 260, maxPx: 280 },
  });
});

test("height returns the canonical public inline rule representation", () => {
  expect(height("toolbar", { minPx: 48, maxPx: 48 })).toEqual({
    kind: "height",
    target: "toolbar",
    range: { minPx: 48, maxPx: 48 },
  });
});

test("inViewport returns the canonical public inline rule representation", () => {
  expect(inViewport("dialog")).toEqual({
    kind: "inViewport",
    target: "dialog",
  });
});

test("accepts caller-constructed width rules", async () => {
  const rule: WidthRule = {
    kind: "width",
    target: "sidebar",
    range: { minPx: 260, maxPx: 280 },
  };
  const report = await checkLayout({
    adapter: fixtureAdapter({
      sidebar: visible("sidebar", rect(0, 0, 270, 100)),
    }),
    rules: [rule],
  });
  expect(report.passed).toBe(true);
});

test("accepts caller-constructed height rules", async () => {
  const rule: HeightRule = {
    kind: "height",
    target: "toolbar",
    range: { minPx: 48, maxPx: 48 },
  };
  const report = await checkLayout({
    adapter: fixtureAdapter({
      toolbar: visible("toolbar", rect(0, 0, 100, 48)),
    }),
    rules: [rule],
  });
  expect(report.passed).toBe(true);
});

test("accepts caller-constructed inViewport rules", async () => {
  const rule: InViewportRule = { kind: "inViewport", target: "dialog" };
  const report = await checkLayout({
    adapter: fixtureAdapter({
      dialog: visible("dialog", rect(0, 0, 100, 100)),
    }),
    rules: [rule],
  });
  expect(report.passed).toBe(true);
});

test("unary rules remain valid after a JSON round trip", async () => {
  const original: UnaryGeometryRule[] = [
    width("target", { minPx: 10, maxPx: 20 }),
    height("target", { minPx: 10, maxPx: 20 }),
    inViewport("target"),
  ];
  const rules = JSON.parse(JSON.stringify(original)) as LayoutRule[];
  const report = await checkLayout({
    adapter: fixtureAdapter({ target: visible("target", rect(0, 0, 15, 15)) }),
    rules,
  });
  expect(rules).toEqual(original);
  expect(report.rules.passed).toBe(3);
});

test("unary rule helpers do not mutate supplied range options", () => {
  const range = { minPx: 10, maxPx: 20 };
  const original = structuredClone(range);
  const widthRule = width("target", range);
  const heightRule = height("target", range);

  range.minPx = 99;
  expect(widthRule.range).toEqual(original);
  expect(heightRule.range).toEqual(original);
  expect(widthRule.range).not.toBe(range);
  expect(heightRule.range).not.toBe(range);
});
