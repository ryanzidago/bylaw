import { expect, test } from "bun:test";

import { checkLayout, LayoutAssertionError, sameSize } from "bylaw-ui";
import {
  createInternalAdapter,
  type RawMeasurementSnapshot,
} from "../src/internal/adapter";

function validSnapshot(): RawMeasurementSnapshot {
  return {
    viewport: { width: 100, height: 100 },
    elements: [
      {
        testId: "subject",
        count: 1,
        hidden: false,
        rect: { x: 0, y: 0, width: 10, height: 10 },
      },
      {
        testId: "reference",
        count: 1,
        hidden: false,
        rect: { x: 0, y: 0, width: 10, height: 10 },
      },
    ],
  };
}

function checkSnapshot(snapshot: unknown) {
  return checkLayout({
    adapter: createInternalAdapter(async () => snapshot),
    rules: [sameSize("subject", "reference")],
  });
}

for (const [name, mutate] of [
  ["rejects a non-finite rectangle coordinate", (snapshot: RawMeasurementSnapshot) => { snapshot.elements[0]!.rect!.x = Number.NaN; }],
  ["rejects a non-finite rectangle dimension", (snapshot: RawMeasurementSnapshot) => { snapshot.elements[0]!.rect!.width = Number.POSITIVE_INFINITY; }],
  ["rejects a negative rectangle width", (snapshot: RawMeasurementSnapshot) => { snapshot.elements[0]!.rect!.width = -1; }],
  ["rejects a negative rectangle height", (snapshot: RawMeasurementSnapshot) => { snapshot.elements[0]!.rect!.height = -1; }],
  ["rejects a non-finite viewport width", (snapshot: RawMeasurementSnapshot) => { snapshot.viewport.width = Number.NaN; }],
  ["rejects a non-finite viewport height", (snapshot: RawMeasurementSnapshot) => { snapshot.viewport.height = Number.POSITIVE_INFINITY; }],
  ["rejects a non-positive viewport width", (snapshot: RawMeasurementSnapshot) => { snapshot.viewport.width = 0; }],
  ["rejects a non-positive viewport height", (snapshot: RawMeasurementSnapshot) => { snapshot.viewport.height = -1; }],
  ["rejects finite rectangle values whose derived right edge is non-finite", (snapshot: RawMeasurementSnapshot) => { snapshot.elements[0]!.rect!.x = Number.MAX_VALUE; snapshot.elements[0]!.rect!.width = Number.MAX_VALUE; }],
  ["rejects finite rectangle values whose derived bottom edge is non-finite", (snapshot: RawMeasurementSnapshot) => { snapshot.elements[0]!.rect!.y = Number.MAX_VALUE; snapshot.elements[0]!.rect!.height = Number.MAX_VALUE; }],
] as const) {
  test(name, async () => {
    const snapshot = validSnapshot();
    mutate(snapshot);
    const error = await checkSnapshot(snapshot).catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(Error);
    expect(error).not.toBeInstanceOf(LayoutAssertionError);
    expect((error as Error).name).toBe("LayoutExecutionError");
  });
}

test("rejects a measurement that cannot be correlated to the requested element", async () => {
  const snapshot = validSnapshot();
  snapshot.elements[0]!.testId = "other";
  await expect(checkSnapshot(snapshot)).rejects.toThrow("correlate");
});

test("rejects an internally inconsistent measurement result", async () => {
  const snapshot = validSnapshot();
  snapshot.elements[0] = {
    testId: "subject",
    count: 0,
    hidden: false,
    rect: { x: 0, y: 0, width: 10, height: 10 },
  };
  await expect(checkSnapshot(snapshot)).rejects.toThrow("must not contain");
});

test("malformed integration output rejects as an execution failure", async () => {
  const error = await checkSnapshot({ nope: true }).catch((caught: unknown) => caught);
  expect(error).toBeInstanceOf(Error);
  expect((error as Error).name).toBe("LayoutExecutionError");
});

test("does not convert malformed adapter output into a layout finding", async () => {
  const error = await checkSnapshot(null).catch((caught: unknown) => caught);
  expect(error).not.toHaveProperty("findings");
});

for (const name of [
  "preserves an unexpected adapter rejection as an execution failure",
  "preserves a Playwright timeout as an execution failure",
  "preserves a detached-page failure as an execution failure",
]) {
  test(name, async () => {
    const original = new Error(name);
    const promise = checkLayout({
      adapter: createInternalAdapter(async () => {
        throw original;
      }),
      rules: [sameSize("subject", "reference")],
    });
    expect(await promise.catch((error: unknown) => error)).toBe(original);
  });
}

test("valid geometry never produces a non-finite diagnostic measurement", async () => {
  const snapshot = validSnapshot();
  snapshot.elements[0]!.rect = {
    x: Number.MAX_VALUE / 4,
    y: -Number.MAX_VALUE / 4,
    width: Number.MAX_VALUE / 4,
    height: Number.MAX_VALUE / 4,
  };
  const report = await checkSnapshot(snapshot);
  expect(JSON.stringify(report)).not.toMatch(/NaN|Infinity/);
});
