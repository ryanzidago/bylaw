import { expect, test } from "bun:test";

import {
  checkLayout,
  createAdapter,
  sameSize,
  width,
  type MeasurementSnapshot,
} from "bylaw-ui";

function snapshot(targets: readonly string[]): MeasurementSnapshot {
  return {
    viewport: { width: 1280, height: 720 },
    targets: targets.map((target) => ({
      target,
      matchCount: 1,
      hidden: false,
      rect: { x: 0, y: 0, width: 10, height: 10 },
    })),
  };
}

test("the public adapter factory rejects a missing implementation", () => {
  expect(() => createAdapter()).toThrow(TypeError);
});

test("the public adapter factory rejects null", () => {
  expect(() => createAdapter(null)).toThrow(TypeError);
});

test("the public adapter factory rejects an array", () => {
  expect(() => createAdapter([])).toThrow(TypeError);
});

test("the public adapter factory rejects an implementation without measure", () => {
  expect(() => createAdapter({})).toThrow(TypeError);
});

test("the public adapter factory rejects a nonfunction measure property", () => {
  expect(() => createAdapter({ measure: "snapshot" })).toThrow(TypeError);
});

test("the public adapter factory reports the invalid measure property in its error", () => {
  expect(() => createAdapter({ measure: 42 })).toThrow(
    expect.objectContaining({
      name: "TypeError",
      message: expect.stringContaining("measure"),
    }),
  );
});

test("the public adapter factory does not invoke measure during construction", () => {
  let calls = 0;
  createAdapter({
    measure: async () => {
      calls += 1;
      return snapshot([]);
    },
  });
  expect(calls).toBe(0);
});

test("a factory-created adapter invokes the consumer measure function", async () => {
  let calls = 0;
  const adapter = createAdapter({
    measure: async (targets) => {
      calls += 1;
      return snapshot(targets);
    },
  });
  await checkLayout({ adapter, rules: [width("sidebar", { minPx: 1 })] });
  expect(calls).toBe(1);
});

test("a factory-created adapter passes every unique referenced target to measure", async () => {
  let received: readonly string[] = [];
  const adapter = createAdapter({
    measure: async (targets) => {
      received = targets;
      return snapshot(targets);
    },
  });
  await checkLayout({
    adapter,
    rules: [
      sameSize("avatar", "card"),
      sameSize("avatar", "dialog"),
      width("card", { minPx: 1 }),
    ],
  });
  expect(received).toEqual(["avatar", "card", "dialog"]);
});

test("a factory-created adapter invokes measure once for one layout check", async () => {
  let calls = 0;
  const adapter = createAdapter({
    measure: async (targets) => {
      calls += 1;
      return snapshot(targets);
    },
  });
  await checkLayout({
    adapter,
    rules: [sameSize("a", "b"), sameSize("a", "b")],
  });
  expect(calls).toBe(1);
});

/**
 * @doc Issue: The adapter receives the engine's mutable target inventory, so a
 * consumer can change the request that snapshot validation uses while measuring.
 * Why it matters: An accidental mutation can bypass one-to-one correlation checks
 * and surface an internal invariant error instead of a valid layout result.
 */
test("a factory-created adapter receives an immutable target inventory", async () => {
  let receivedTargets: readonly string[] = [];
  const adapter = createAdapter({
    measure: async (targets) => {
      receivedTargets = targets;
      return snapshot(targets);
    },
  });

  await checkLayout({ adapter, rules: [width("sidebar", { minPx: 1 })] });

  expect(Object.isFrozen(receivedTargets)).toBe(true);
});

test("a factory-created adapter cannot have its validated measure function replaced", () => {
  const adapter = createAdapter({ measure: async () => snapshot([]) });
  expect(() => {
    Object.assign(adapter, { measure: async () => ({ invalid: true }) });
  }).toThrow(TypeError);
});

test("a factory-created adapter does not expose the internal brand as a public property", () => {
  const adapter = createAdapter({ measure: async () => snapshot([]) });
  expect(Object.keys(adapter)).not.toContain(expect.stringContaining("brand"));
  expect(Object.getOwnPropertySymbols(adapter)).toEqual([]);
});

test("a public adapter cannot be created by copying enumerable properties from a valid adapter", () => {
  const adapter = createAdapter({ measure: async () => snapshot([]) });
  const copy = { ...adapter };
  expect(checkLayout({ adapter: copy, rules: [] } as never)).rejects.toThrow(
    "unsupported adapter",
  );
});
