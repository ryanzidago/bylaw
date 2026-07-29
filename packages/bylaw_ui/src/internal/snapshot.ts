import type {
  RawCollectionMeasurement,
  RawElementMeasurement,
  RawMeasurementSnapshot,
  Rectangle,
} from "./adapter.js";

type UnknownRecord = Record<string, unknown>;

export class LayoutExecutionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LayoutExecutionError";
  }
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function malformed(message: string): never {
  throw new LayoutExecutionError(`Malformed layout measurement: ${message}`);
}

function finiteNumber(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    malformed(`${path} must be finite`);
  }

  return value;
}

function rectangle(value: unknown, path: string): Rectangle {
  if (!isRecord(value)) {
    malformed(`${path} must be an object`);
  }

  const rect = {
    x: finiteNumber(value.x, `${path}.x`),
    y: finiteNumber(value.y, `${path}.y`),
    width: finiteNumber(value.width, `${path}.width`),
    height: finiteNumber(value.height, `${path}.height`),
  };

  if (rect.width < 0 || rect.height < 0) {
    malformed(`${path} dimensions must be nonnegative`);
  }

  if (!Number.isFinite(rect.x + rect.width)) {
    malformed(`${path} derived right edge must be finite`);
  }

  if (!Number.isFinite(rect.y + rect.height)) {
    malformed(`${path} derived bottom edge must be finite`);
  }

  return rect;
}

function element(
  value: unknown,
  path: string,
  requested: Set<string>,
): RawElementMeasurement | RawCollectionMeasurement {
  if (!isRecord(value)) {
    malformed(`${path} must be an object`);
  }

  if (typeof value.testId !== "string" || !requested.has(value.testId)) {
    malformed(`${path}.testId does not correlate to a requested element`);
  }

  if ("matches" in value) {
    if (!Array.isArray(value.matches)) {
      malformed(`${path}.matches must be an array`);
    }
    return {
      testId: value.testId,
      count: value.matches.length,
      hidden: null,
      rect: null,
      matches: value.matches.map((match, index) => {
        if (!isRecord(match)) {
          malformed(`${path}.matches[${index}] must be an object`);
        }
        if (typeof match.hidden !== "boolean") {
          malformed(`${path}.matches[${index}].hidden must be boolean`);
        }
        return {
          hidden: match.hidden,
          rect: rectangle(match.rect, `${path}.matches[${index}].rect`),
        };
      }),
    };
  }

  if (
    typeof value.count !== "number" ||
    !Number.isSafeInteger(value.count) ||
    value.count < 0
  ) {
    malformed(`${path}.count must be a nonnegative safe integer`);
  }

  if (value.count === 1) {
    if (typeof value.hidden !== "boolean") {
      malformed(`${path}.hidden must be boolean for one match`);
    }

    return {
      testId: value.testId,
      count: value.count,
      hidden: value.hidden,
      rect: rectangle(value.rect, `${path}.rect`),
    };
  }

  if (value.hidden !== null || value.rect !== null) {
    malformed(`${path} unresolved measurements must not contain element state`);
  }

  return {
    testId: value.testId,
    count: value.count,
    hidden: null,
    rect: null,
  };
}

export function validateSnapshot(
  value: unknown,
  requestedTargets: readonly (
    string | import("../types.js").CollectionTarget
  )[],
): RawMeasurementSnapshot {
  if (
    !isRecord(value) ||
    !isRecord(value.viewport) ||
    !Array.isArray(value.elements)
  ) {
    malformed("snapshot must contain viewport and elements");
  }

  const viewport = {
    width: finiteNumber(value.viewport.width, "viewport.width"),
    height: finiteNumber(value.viewport.height, "viewport.height"),
  };

  if (viewport.width <= 0 || viewport.height <= 0) {
    malformed("viewport dimensions must be positive");
  }

  const requestedNames = requestedTargets.map((target) =>
    typeof target === "string" ? target : target.target,
  );
  const requested = new Set(requestedNames);
  const elements = value.elements.map((entry, index) =>
    element(entry, `elements[${index}]`, requested),
  );
  const expectedKeys = requestedTargets.map((target) =>
    typeof target === "string"
      ? `singular:${target}`
      : `collection:${target.target}`,
  );
  const measuredKeys = elements.map(
    (measurement) =>
      `${"matches" in measurement ? "collection" : "singular"}:${measurement.testId}`,
  );
  if (
    new Set(expectedKeys).size !== expectedKeys.length ||
    new Set(measuredKeys).size !== measuredKeys.length ||
    expectedKeys.length !== measuredKeys.length ||
    expectedKeys.some((key) => !measuredKeys.includes(key))
  ) {
    malformed("elements must correlate one-to-one with requested test IDs");
  }

  return { viewport, elements };
}
