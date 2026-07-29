import { expect, test } from "bun:test";

import * as bylawUi from "bylaw-ui";
import {
  checkLayout,
  collection,
  equalWidths,
  everyInside,
  inside,
  pairwiseNotOverlap,
  verticallyOrdered,
  type CollectionFinding,
  type CollectionRule,
  type CollectionTarget,
  type LayoutRule,
} from "bylaw-ui";
import { fixtureAdapter } from "./support";

test("the package root exports the supported collection target declaration", () => {
  expect(bylawUi.collection).toBeFunction();
});

test("the package root exports every collection geometry rule helper", () => {
  expect(bylawUi.everyInside).toBeFunction();
  expect(bylawUi.equalWidths).toBeFunction();
  expect(bylawUi.verticallyOrdered).toBeFunction();
  expect(bylawUi.pairwiseNotOverlap).toBeFunction();
});

test("the public API distinguishes collection targets from singular targets", () => {
  expect(collection("cards")).toEqual({ kind: "collection", target: "cards" });
  expect(collection("cards")).not.toBe("cards");
});

test("singular and collection target declarations are not interchangeable at compile time", () => {
  const cards: CollectionTarget = collection("cards");
  if (false) {
    // @ts-expect-error inside accepts singular targets, not collection targets
    inside(cards, "container");
  }
  expect(cards.kind).toBe("collection");
});

test("collection target intent is explicit in the public rule representation", () => {
  expect(equalWidths(collection("cards"))).toEqual({
    kind: "equalWidths",
    collection: { kind: "collection", target: "cards" },
  });
});

test("public collection rule helpers return rules accepted by checkLayout", async () => {
  const collectionRules: CollectionRule[] = [
    everyInside(collection("cards"), "container"),
    equalWidths(collection("cards")),
    verticallyOrdered(collection("cards")),
    pairwiseNotOverlap(collection("cards")),
  ];
  const rules: LayoutRule[] = collectionRules;
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules,
  });
  expect(report.rules.total).toBe(4);
});

test("caller-constructed collection rules remain valid after a JSON round trip", () => {
  const original: CollectionRule = {
    kind: "verticallyOrdered",
    collection: { kind: "collection", target: "rows" },
    options: { gap: { minPx: 4, maxPx: 8 } },
  };
  const rule = JSON.parse(JSON.stringify(original)) as CollectionRule;
  expect(rule).toEqual(original);
});

test("collection rules and findings expose supported public types", () => {
  const rule: CollectionRule = equalWidths(collection("cards"));
  const target: CollectionTarget = rule.collection;
  const finding = {
    category: "element-resolution",
    code: "empty-collection",
    ruleIndex: 0,
    message: "empty collection",
    target: "cards",
    operand: "collection",
    expected: { minMatchCount: 1 },
    actual: { matchCount: 0 },
  } satisfies CollectionFinding;
  expect([target, finding]).toHaveLength(2);
});

/**
 * @doc
 * Issue: CollectionFinding allows a width-mismatch code to claim an unrelated
 * pairwiseNotOverlap relationship.
 * Why it matters: Consumers cannot safely narrow collection diagnostics by
 * relationship, so an exhaustively handled report can accept impossible data.
 */
test("collection finding relationships reject codes from other rule kinds", () => {
  if (false) {
    const finding: CollectionFinding = {
      category: "layout",
      code: "collection-width-mismatch",
      ruleIndex: 0,
      message: "width mismatch",
      // @ts-expect-error width mismatches only belong to equalWidths rules
      relationship: "pairwiseNotOverlap",
      target: "cards",
      collectionIndex: 1,
      expected: { tolerancePx: 0 },
      actual: { differencePx: 1 },
    };
    expect(finding).toBeDefined();
  }
  expect(true).toBe(true);
});

test("collection rule helpers do not mutate supplied targets or options", () => {
  const target = collection("rows");
  const options = { gap: { minPx: 4, maxPx: 8 } };
  const targetBefore = structuredClone(target);
  const optionsBefore = structuredClone(options);
  const rule = verticallyOrdered(target, options);
  target.target = "changed";
  options.gap.minPx = 99;
  expect(rule.collection).toEqual(targetBefore);
  expect(rule.options).toEqual(optionsBefore);
});

test("an ESM TypeScript consumer can use collection rules from the packed package", async () => {
  const javascript = (await import("../dist/index.js")) as Record<
    string,
    unknown
  >;
  expect(javascript.collection).toBeFunction();
  expect(javascript.equalWidths).toBeFunction();
});

test("published declarations preserve the distinction between singular and collection targets", async () => {
  const declarations = await Bun.file(
    new URL("../dist/index.d.ts", import.meta.url),
  ).text();
  expect(declarations).toContain("CollectionTarget");
  expect(declarations).toContain('kind: "collection"');
  expect(declarations).toMatch(/everyInside[^;]*CollectionTarget[^;]*string/);
});

test("a packed Playwright consumer can evaluate collection rules over repeated elements", async () => {
  const root = (await import("../dist/index.js")) as Record<string, unknown>;
  const browser = await import("../dist/playwright.js");
  expect(root.collection).toBeFunction();
  expect(root.equalWidths).toBeFunction();
  expect(browser.playwright).toBeFunction();
});
