import { expect, test } from "bun:test";

import {
  checkLayout,
  createAdapter,
  sameSize,
  type Adapter,
  type AdapterImplementation,
  type CheckLayoutInput,
  type CollectionTargetResolution,
  type MeasurementSnapshot,
  type Rectangle,
  type SingularTargetResolution,
  type Viewport,
} from "bylaw-ui";

const snapshot: MeasurementSnapshot = {
  viewport: { width: 100, height: 100 },
  targets: [
    {
      target: "a",
      matchCount: 1,
      hidden: false,
      rect: { x: 0, y: 0, width: 10, height: 10 },
    },
    {
      target: "b",
      matchCount: 1,
      hidden: false,
      rect: { x: 20, y: 0, width: 10, height: 10 },
    },
  ],
};

test("the package root exports the public adapter factory", async () => {
  expect((await import("bylaw-ui")).createAdapter).toBeFunction();
});

test("the package root exports the opaque public adapter type", () => {
  const adapter: Adapter = createAdapter({ measure: async () => snapshot });
  expect(adapter).toBeDefined();
});

test("the package root exports the public adapter implementation type", () => {
  const implementation: AdapterImplementation = {
    measure: async () => snapshot,
  };
  expect(implementation.measure).toBeFunction();
});

test("the package root exports the public measurement snapshot type", () => {
  const value: MeasurementSnapshot = snapshot;
  expect(value.targets).toHaveLength(2);
});

test("the package root exports the public viewport type", () => {
  const viewport: Viewport = { width: 1280, height: 720 };
  expect(viewport.width).toBe(1280);
});

test("the package root exports the public rectangle type", () => {
  const rectangle: Rectangle = { x: 0, y: 0, width: 10, height: 20 };
  expect(rectangle.height).toBe(20);
});

test("the package root exports the public singular target resolution type", () => {
  const target: SingularTargetResolution = {
    target: "avatar",
    matchCount: 0,
  };
  expect(target.matchCount).toBe(0);
});

test("the package root exports the public collection target resolution type", () => {
  const target: CollectionTargetResolution = {
    target: "avatars",
    matches: [],
  };
  expect(target.matches).toEqual([]);
});

test("the public adapter factory accepts a minimal custom adapter", () => {
  expect(createAdapter({ measure: async () => snapshot })).toBeDefined();
});

test("the public adapter factory returns a reusable adapter", async () => {
  const adapter = createAdapter({ measure: async () => snapshot });
  expect((await checkLayout({ adapter, rules: [] })).passed).toBe(true);
  expect((await checkLayout({ adapter, rules: [] })).passed).toBe(true);
});

test("checkLayout accepts an adapter returned by the public adapter factory", async () => {
  const report = await checkLayout({
    adapter: createAdapter({ measure: async () => snapshot }),
    rules: [sameSize("a", "b")],
  });
  expect(report).toMatchObject({ passed: true, rules: { passed: 1 } });
});

test("the public CheckLayoutInput type accepts a factory-created adapter", () => {
  const input: CheckLayoutInput = {
    adapter: createAdapter({ measure: async () => snapshot }),
    rules: [sameSize("a", "b")],
  };
  expect(input.rules).toHaveLength(1);
});

test("a structurally similar object is not accepted as a supported adapter", () => {
  const similar = { measure: async () => snapshot };
  if (false) {
    // @ts-expect-error adapters must be created by createAdapter
    const input: CheckLayoutInput = { adapter: similar, rules: [] };
    expect(input).toBeDefined();
  }
  expect(checkLayout({ adapter: similar, rules: [] } as never)).rejects.toThrow(
    "unsupported adapter",
  );
});

test("ordinary structural typing cannot forge the internal adapter brand", () => {
  if (false) {
    // @ts-expect-error no public property can construct the opaque adapter type
    const adapter: Adapter = { measure: async () => snapshot };
    expect(adapter).toBeDefined();
  }
  expect(true).toBe(true);
});

test("a custom adapter can evaluate layout rules without loading Playwright", async () => {
  const root = await import("bylaw-ui");
  const adapter = createAdapter({ measure: async () => snapshot });
  const report = await checkLayout({
    adapter,
    rules: [sameSize("a", "b")],
  });
  expect(root).not.toHaveProperty("playwright");
  expect(report.passed).toBe(true);
});

test("the public adapter boundary adds no automatic relationship inference API", async () => {
  expect(await import("bylaw-ui")).not.toHaveProperty("inferRelationships");
});

test("the public adapter boundary adds no aesthetic evaluation API", async () => {
  expect(await import("bylaw-ui")).not.toHaveProperty("evaluateAesthetics");
});

test("the published package exposes the custom adapter boundary to an ESM TypeScript consumer", async () => {
  const declaration = await Bun.file(
    new URL("../dist/index.d.ts", import.meta.url),
  ).text();
  const javascript = await import("../dist/index.js");
  expect(declaration).toContain("createAdapter");
  expect(javascript.createAdapter).toBeFunction();
});
