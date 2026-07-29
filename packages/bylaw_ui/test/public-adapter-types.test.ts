import { expect, test } from "bun:test";

import type {
  AdapterImplementation,
  CollectionTargetResolution,
  MeasurementSnapshot,
  MeasurementValidationError,
  Rectangle,
  SingularTargetResolution,
} from "bylaw-ui";

test("a resolved singular target type requires exactly one match", () => {
  const target: SingularTargetResolution = {
    target: "avatar",
    matchCount: 1,
    hidden: false,
    rect: { x: 0, y: 0, width: 40, height: 40 },
  };
  expect(target.matchCount).toBe(1);
});

test("a resolved singular target type requires visibility state and a rectangle", () => {
  const target: SingularTargetResolution = {
    target: "avatar",
    matchCount: 1,
    hidden: true,
    rect: { x: 4, y: 8, width: 40, height: 40 },
  };
  expect(target).toMatchObject({ hidden: true, rect: { width: 40 } });
});

test("a missing target type requires zero matches and no element state", () => {
  const target: SingularTargetResolution = {
    target: "missing",
    matchCount: 0,
  };
  expect(target).toEqual({ target: "missing", matchCount: 0 });
});

test("an ambiguous singular target type requires multiple matches and no element state", () => {
  const target: SingularTargetResolution = {
    target: "duplicate",
    matchCount: 2,
  };
  expect(target.matchCount).toBe(2);
});

test("target resolution types reject contradictory count and element state at compile time", () => {
  const target: SingularTargetResolution = {
    target: "missing",
    matchCount: 0,
    // @ts-expect-error unresolved targets cannot contain element state
    hidden: false,
    rect: { x: 0, y: 0, width: 10, height: 10 },
  };
  expect(target).toBeDefined();
});

test("a resolved collection type preserves every measured member", () => {
  const target: CollectionTargetResolution = {
    target: "card",
    matches: [
      { hidden: false, rect: { x: 0, y: 0, width: 80, height: 20 } },
      { hidden: false, rect: { x: 0, y: 24, width: 80, height: 20 } },
    ],
  };
  expect(target.matches).toHaveLength(2);
});

test("a collection member type requires visibility state and a rectangle", () => {
  const target: CollectionTargetResolution = {
    target: "card",
    matches: [{ hidden: true, rect: { x: 0, y: 0, width: 0, height: 0 } }],
  };
  expect(target.matches[0]).toEqual({
    hidden: true,
    rect: { x: 0, y: 0, width: 0, height: 0 },
  });
});

test("an empty collection type is distinct from a missing singular target", () => {
  const collection: CollectionTargetResolution = {
    target: "cards",
    matches: [],
  };
  const singular: SingularTargetResolution = {
    target: "card",
    matchCount: 0,
  };
  expect(collection).toHaveProperty("matches");
  expect(singular).toHaveProperty("matchCount", 0);
});

test("the measurement snapshot type requires viewport data", () => {
  // @ts-expect-error snapshots require a viewport
  const snapshot: MeasurementSnapshot = { targets: [] };
  expect(snapshot).toBeDefined();
});

test("the measurement snapshot type contains target resolution results", () => {
  const snapshot: MeasurementSnapshot = {
    viewport: { width: 1280, height: 720 },
    targets: [{ target: "dialog", matchCount: 0 }],
  };
  expect(snapshot.targets).toHaveLength(1);
});

test("the rectangle type uses x y width and height coordinates", () => {
  const rectangle: Rectangle = { x: 1.25, y: -2.5, width: 30.5, height: 40 };
  expect(rectangle).toEqual({ x: 1.25, y: -2.5, width: 30.5, height: 40 });
});

test("the adapter implementation receives readonly requested targets", () => {
  const implementation: AdapterImplementation = {
    async measure(targets) {
      if (false) {
        // @ts-expect-error requested targets are readonly
        targets.push("other");
      }
      return { viewport: { width: 1, height: 1 }, targets: [] };
    },
  };
  expect(implementation.measure).toBeFunction();
});

test("the adapter implementation return type matches the documented measurement lifecycle", () => {
  const implementation: AdapterImplementation = {
    measure: async (targets): Promise<MeasurementSnapshot> => ({
      viewport: { width: 1440, height: 900 },
      targets: targets.map((target) => ({ target, matchCount: 0 })),
    }),
  };
  expect(implementation.measure(["missing"])).resolves.toMatchObject({
    viewport: { width: 1440, height: 900 },
  });
});

test("the public measurement validation error type can be distinguished from layout assertion failures", () => {
  function isMeasurementFailure(
    error: Error,
  ): error is MeasurementValidationError {
    return error.name === "MeasurementValidationError";
  }
  expect(isMeasurementFailure).toBeFunction();
});
