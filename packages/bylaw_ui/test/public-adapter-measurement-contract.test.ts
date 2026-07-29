import { expect, test } from "bun:test";

import {
  checkLayout,
  createAdapter,
  inViewport,
  sameSize,
  width,
  type MeasurementSnapshot,
} from "bylaw-ui";

function resolved(
  target: string,
  rect = { x: 0, y: 0, width: 10, height: 10 },
) {
  return { target, matchCount: 1 as const, hidden: false, rect };
}

function validSnapshot(): MeasurementSnapshot {
  return {
    viewport: { width: 100, height: 100 },
    targets: [resolved("subject"), resolved("reference")],
  };
}

function checkSnapshot(value: unknown) {
  return checkLayout({
    adapter: createAdapter({ measure: async () => value }),
    rules: [sameSize("subject", "reference")],
  });
}

async function measurementError(value: unknown): Promise<Error> {
  return (await checkSnapshot(value).catch((error: unknown) => error)) as Error;
}

test("a custom adapter returns normalized viewport-relative rectangle coordinates", async () => {
  const report = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [resolved("dialog", { x: 80, y: 90, width: 30, height: 20 })],
      }),
    }),
    rules: [inViewport("dialog")],
  });
  expect(report.findings[0]).toMatchObject({
    code: "viewport-overflow",
    actual: { target: { leftPx: 80, topPx: 90, rightPx: 110, bottomPx: 110 } },
  });
});

test("normalized rectangles use fractional CSS pixels", async () => {
  const report = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100.5, height: 100.5 },
        targets: [
          resolved("panel", { x: 0.25, y: 0.5, width: 10.75, height: 20.5 }),
        ],
      }),
    }),
    rules: [width("panel", { minPx: 10.5, maxPx: 11 })],
  });
  expect(report.passed).toBe(true);
});

test("normalized rectangles allow negative viewport-relative coordinates", async () => {
  const report = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [resolved("menu", { x: -8, y: -4, width: 20, height: 20 })],
      }),
    }),
    rules: [inViewport("menu")],
  });
  expect(report.findings[0]).toMatchObject({ code: "viewport-overflow" });
});

test("normalized rectangles use axis-aligned border-box bounds", async () => {
  const report = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [resolved("card", { x: 4, y: 8, width: 30, height: 12 })],
      }),
    }),
    rules: [width("card", { minPx: 30, maxPx: 30 })],
  });
  expect(report.passed).toBe(true);
});

test("normalized rectangles allow zero dimensions for visibility evaluation", async () => {
  const report = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [resolved("collapsed", { x: 0, y: 0, width: 0, height: 10 })],
      }),
    }),
    rules: [width("collapsed", { minPx: 0 })],
  });
  expect(report.findings[0]).toMatchObject({
    category: "element-visibility",
    code: "zero-size-element",
  });
});

test("normalized viewport dimensions use positive finite CSS pixels", async () => {
  expect((await checkSnapshot(validSnapshot())).passed).toBe(true);
});

test("a custom adapter can report a missing singular target", async () => {
  const report = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [{ target: "missing", matchCount: 0 }],
      }),
    }),
    rules: [width("missing", { minPx: 1 })],
  });
  expect(report.findings[0]).toMatchObject({
    code: "missing-element",
    actual: { matchCount: 0 },
  });
});

test("a custom adapter can report an ambiguous singular target", async () => {
  const report = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [{ target: "duplicate", matchCount: 3 }],
      }),
    }),
    rules: [width("duplicate", { minPx: 1 })],
  });
  expect(report.findings[0]).toMatchObject({
    code: "duplicate-element",
    actual: { matchCount: 3 },
  });
});

test("a custom adapter can return every member of a resolved collection", () => {
  const snapshot: MeasurementSnapshot = {
    viewport: { width: 100, height: 100 },
    targets: [
      {
        target: "cards",
        matches: [
          { hidden: false, rect: { x: 0, y: 0, width: 10, height: 10 } },
          { hidden: false, rect: { x: 0, y: 20, width: 10, height: 10 } },
        ],
      },
    ],
  };
  expect(snapshot.targets[0]).toHaveProperty("matches", expect.any(Array));
});

test("a valid adapter result correlates one-to-one with every requested target", async () => {
  const report = await checkSnapshot(validSnapshot());
  expect(report.passed).toBe(true);
});

test("adapter failures preserve the original error identity", async () => {
  const original = new Error("CDP session closed");
  const promise = checkLayout({
    adapter: createAdapter({ measure: () => Promise.reject(original) }),
    rules: [width("panel", { minPx: 1 })],
  });
  expect(await promise.catch((error: unknown) => error)).toBe(original);
});

test("a synchronously thrown adapter failure preserves the original error identity", async () => {
  const original = new Error("WebDriver failed");
  const adapter = createAdapter({
    measure() {
      throw original;
    },
  });
  const promise = checkLayout({
    adapter,
    rules: [width("panel", { minPx: 1 })],
  });
  expect(await promise.catch((error: unknown) => error)).toBe(original);
});

test("an asynchronously rejected adapter failure preserves the original error identity", async () => {
  const original = new Error("MCP connection lost");
  const adapter = createAdapter({
    measure: async () => {
      throw original;
    },
  });
  const promise = checkLayout({
    adapter,
    rules: [width("panel", { minPx: 1 })],
  });
  expect(await promise.catch((error: unknown) => error)).toBe(original);
});

test("a measurement validation failure is distinct from an adapter platform failure", async () => {
  const platform = new Error("platform failed");
  const invalid = await measurementError(null);
  const adapter = createAdapter({
    measure: async () => {
      throw platform;
    },
  });
  const caught = await checkLayout({
    adapter,
    rules: [width("panel", { minPx: 1 })],
  }).catch((error: unknown) => error);
  expect(invalid.name).toBe("MeasurementValidationError");
  expect(caught).toBe(platform);
});

for (const [name, mutate] of [
  ["rejects a nonobject snapshot before rule evaluation", () => null],
  [
    "rejects a snapshot without viewport data before rule evaluation",
    () => ({ targets: validSnapshot().targets }),
  ],
  [
    "rejects a snapshot without target results before rule evaluation",
    () => ({ viewport: validSnapshot().viewport }),
  ],
  [
    "rejects a nonarray target result collection before rule evaluation",
    () => ({ ...validSnapshot(), targets: {} }),
  ],
  [
    "rejects nonpositive viewport dimensions before rule evaluation",
    () => ({ ...validSnapshot(), viewport: { width: 0, height: 100 } }),
  ],
  [
    "rejects nonfinite viewport dimensions before rule evaluation",
    () => ({
      ...validSnapshot(),
      viewport: { width: Number.NaN, height: 100 },
    }),
  ],
  [
    "rejects a nonobject target result before rule evaluation",
    () => ({ ...validSnapshot(), targets: [null, validSnapshot().targets[1]] }),
  ],
  [
    "rejects a target result with a nonstring identifier before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { ...validSnapshot().targets[0], target: 4 },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a target result with a negative match count before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { target: "subject", matchCount: -1 },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a target result with a fractional match count before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { target: "subject", matchCount: 1.5 },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a target result with an unsafe match count before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { target: "subject", matchCount: Number.MAX_SAFE_INTEGER + 1 },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a rectangle with a nonfinite coordinate before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        resolved("subject", { x: Number.NaN, y: 0, width: 10, height: 10 }),
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a nonobject rectangle before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { ...resolved("subject"), rect: null },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a rectangle with negative dimensions before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        resolved("subject", { x: 0, y: 0, width: -1, height: 10 }),
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a rectangle with a nonfinite derived edge before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        resolved("subject", {
          x: Number.MAX_VALUE,
          y: 0,
          width: Number.MAX_VALUE,
          height: 10,
        }),
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a resolved singular target without element state before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { target: "subject", matchCount: 1 },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects an unresolved singular target with element state before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { ...resolved("subject"), matchCount: 0 },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a resolved singular target with a nonboolean hidden state before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { ...resolved("subject"), hidden: "no" },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects a collection containing malformed element state before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        { target: "subject", matches: [{ hidden: false, rect: null }] },
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects adapter results that omit a requested target before rule evaluation",
    () => ({ ...validSnapshot(), targets: [validSnapshot().targets[0]] }),
  ],
  [
    "rejects adapter results that duplicate a requested target before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [
        validSnapshot().targets[0],
        validSnapshot().targets[0],
        validSnapshot().targets[1],
      ],
    }),
  ],
  [
    "rejects adapter results for an unrequested target before rule evaluation",
    () => ({
      ...validSnapshot(),
      targets: [validSnapshot().targets[0], resolved("other")],
    }),
  ],
] as const) {
  test(name, async () => {
    const error = await measurementError(mutate());
    expect(error).toBeInstanceOf(Error);
    expect(error.name).toBe("MeasurementValidationError");
  });
}

test("malformed adapter results fail with an actionable measurement path", async () => {
  const value = validSnapshot() as unknown as {
    viewport: { width: number; height: number };
    targets: Array<Record<string, unknown>>;
  };
  value.targets[0]!.rect = { x: 0, y: 0, width: Number.NaN, height: 10 };
  expect((await measurementError(value)).message).toContain(
    "targets[0].rect.width",
  );
});

test("malformed adapter results do not produce layout findings", async () => {
  expect(await measurementError(null)).not.toHaveProperty("findings");
});

test("malformed adapter results do not partially evaluate otherwise valid rules", async () => {
  const error = await checkLayout({
    adapter: createAdapter({
      measure: async () => ({
        viewport: { width: 100, height: 100 },
        targets: [
          resolved("valid"),
          resolved("invalid", { x: 0, y: 0, width: -1, height: 10 }),
        ],
      }),
    }),
    rules: [width("valid", { minPx: 100 }), width("invalid", { minPx: 1 })],
  }).catch((caught: unknown) => caught);
  expect(error).toBeInstanceOf(Error);
  expect(error).not.toHaveProperty("findings");
});
