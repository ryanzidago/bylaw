import { expect, test } from "bun:test";

import {
  checkLayout,
  collection,
  createAdapter,
  equalWidths,
  everyInside,
  sameWidth,
  type CollectionFinding,
} from "bylaw-ui";

const rectangle = { x: 0, y: 0, width: 10, height: 10 };

function match(rect = rectangle, overrides: { hidden?: boolean } = {}) {
  return { hidden: overrides.hidden ?? false, rect };
}

function adapterFor(targets: object[], onMeasure?: (targets: unknown) => void) {
  return createAdapter({
    measure: async (requestedTargets: unknown) => {
      onMeasure?.(requestedTargets);
      return { viewport: { width: 100, height: 100 }, targets };
    },
  });
}

test("a collection target resolves every matching element", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      {
        target: "cards",
        matches: [match(), match(), match()],
      },
    ]),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.passed).toBe(true);
});

test("a collection target preserves adapter element order", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      {
        target: "cards",
        matches: [match({ ...rectangle, width: 30 }), match(), match()],
      },
    ]),
    rules: [equalWidths(collection("cards"))],
  });
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([1, 2]);
});

test("a collection target accepts exactly one matching element", async () => {
  const report = await checkLayout({
    adapter: adapterFor([{ target: "cards", matches: [match()] }]),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.passed).toBe(true);
});

test("an empty collection reports a resolution finding", async () => {
  const report = await checkLayout({
    adapter: adapterFor([{ target: "cards", matches: [] }]),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.findings).toEqual([
    expect.objectContaining({
      category: "element-resolution",
      code: "empty-collection",
      target: "cards",
      expected: { minMatchCount: 1 },
      actual: { matchCount: 0 },
    }),
  ]);
});

test("an empty collection skips geometry evaluation", async () => {
  const report = await checkLayout({
    adapter: adapterFor([{ target: "cards", matches: [] }]),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.rules).toEqual({ total: 1, passed: 0, failed: 0, skipped: 1 });
  expect(report.findings.every(({ category }) => category !== "layout")).toBe(
    true,
  );
});

test("a hidden collection member reports its collection index and target element", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      {
        target: "cards",
        matches: [match(), match(rectangle, { hidden: true }), match()],
      },
    ]),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.findings[0]).toMatchObject({
    category: "element-visibility",
    code: "hidden-element",
    target: "cards",
    collectionIndex: 1,
  });
});

test("a zero-size collection member reports its collection index and target element", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      {
        target: "cards",
        matches: [match(), match({ ...rectangle, width: 0 }), match()],
      },
    ]),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.findings[0]).toMatchObject({
    category: "element-visibility",
    code: "zero-size-element",
    target: "cards",
    collectionIndex: 1,
  });
});

test("reports every unavailable collection member in collection order", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      {
        target: "cards",
        matches: [
          match(rectangle, { hidden: true }),
          match(),
          match({ ...rectangle, height: 0 }),
        ],
      },
    ]),
    rules: [equalWidths(collection("cards"))],
  });
  const findings = report.findings as Extract<
    CollectionFinding,
    { collectionIndex: number }
  >[];
  expect(findings.map((finding) => finding.collectionIndex)).toEqual([0, 2]);
});

test("a collection rule skips geometry evaluation when any member is unavailable", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      {
        target: "cards",
        matches: [
          match({ ...rectangle, width: 10 }),
          match({ ...rectangle, width: 20 }, { hidden: true }),
        ],
      },
    ]),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.rules.skipped).toBe(1);
  expect(report.findings.every(({ category }) => category !== "layout")).toBe(
    true,
  );
});

test("an unreferenced collection target is not resolved", async () => {
  let requested: unknown;
  const report = await checkLayout({
    adapter: adapterFor(
      [{ target: "cards", matches: [match()] }],
      (targets) => {
        requested = targets;
      },
    ),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.passed).toBe(true);
  expect(requested).toEqual([collection("cards")]);
});

test("a collection target reused by several rules is measured once per check", async () => {
  let measurements = 0;
  const report = await checkLayout({
    adapter: adapterFor(
      [
        { target: "cards", matches: [match(), match()] },
        {
          target: "container",
          matchCount: 1,
          hidden: false,
          rect: { x: -10, y: -10, width: 100, height: 100 },
        },
      ],
      () => {
        measurements += 1;
      },
    ),
    rules: [
      equalWidths(collection("cards")),
      everyInside(collection("cards"), "container"),
    ],
  });
  expect(report.rules.passed).toBe(2);
  expect(measurements).toBe(1);
});

test("a singular target continues to reject multiple matching elements", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      { target: "a", matchCount: 2 },
      {
        target: "b",
        matchCount: 1,
        hidden: false,
        rect: rectangle,
      },
    ]),
    rules: [sameWidth("a", "b")],
  });
  expect(report.findings[0]).toMatchObject({
    category: "element-resolution",
    code: "duplicate-element",
    target: "a",
    actual: { matchCount: 2 },
  });
});

test("a singular target never selects the first of multiple matching elements", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      { target: "a", matchCount: 2 },
      {
        target: "b",
        matchCount: 1,
        hidden: false,
        rect: rectangle,
      },
    ]),
    rules: [sameWidth("a", "b")],
  });
  expect(report.rules.skipped).toBe(1);
  expect(report.findings.some(({ category }) => category === "layout")).toBe(
    false,
  );
});

test("a rule can use a collection target and a singular target as distinct operands", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      { target: "cards", matches: [match(), match()] },
      {
        target: "container",
        matchCount: 1,
        hidden: false,
        rect: { x: -10, y: -10, width: 100, height: 100 },
      },
    ]),
    rules: [everyInside(collection("cards"), "container")],
  });
  expect(report.passed).toBe(true);
});

/**
 * @doc
 * Issue: Snapshot correlation collapses singular and collection requests that
 * use the same target name, even though their declarations are distinct.
 * Why it matters: A check cannot validate a repeated group while also reporting
 * that the same selector is ambiguous for a singular rule.
 */
test("the same target name can be measured as both a collection and a singular target", async () => {
  const report = await checkLayout({
    adapter: adapterFor([
      {
        target: "cards",
        matches: [match(), match()],
      },
      {
        target: "cards",
        matchCount: 2,
      },
      {
        target: "reference",
        matchCount: 1,
        hidden: false,
        rect: rectangle,
      },
    ]),
    rules: [equalWidths(collection("cards")), sameWidth("cards", "reference")],
  });

  expect(report.rules).toEqual({
    total: 2,
    passed: 1,
    failed: 0,
    skipped: 1,
  });
  expect(report.findings).toEqual([
    expect.objectContaining({
      category: "element-resolution",
      code: "duplicate-element",
      target: "cards",
      actual: { matchCount: 2 },
    }),
  ]);
});
