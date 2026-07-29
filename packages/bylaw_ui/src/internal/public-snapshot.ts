import type {
  CollectionTargetResolution,
  MeasurementSnapshot,
  Rectangle,
  SingularTargetResolution,
} from "../adapter.js";
import type {
  RawElementMeasurement,
  RawMeasurementSnapshot,
} from "./adapter.js";

type UnknownRecord = Record<string, unknown>;

export class MeasurementValidationError extends Error {
  constructor(message: string) {
    super(`Malformed adapter measurement: ${message}`);
    this.name = "MeasurementValidationError";
  }
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function malformed(message: string): never {
  throw new MeasurementValidationError(message);
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

function resolvedElement(
  value: UnknownRecord,
  path: string,
): { hidden: boolean; rect: Rectangle } {
  if (typeof value.hidden !== "boolean") {
    malformed(`${path}.hidden must be boolean`);
  }

  return {
    hidden: value.hidden,
    rect: rectangle(value.rect, `${path}.rect`),
  };
}

function singularTarget(
  value: UnknownRecord,
  path: string,
): SingularTargetResolution {
  if (
    typeof value.matchCount !== "number" ||
    !Number.isSafeInteger(value.matchCount) ||
    value.matchCount < 0
  ) {
    malformed(`${path}.matchCount must be a nonnegative safe integer`);
  }

  const matchCount = value.matchCount;

  if (matchCount === 1) {
    const element = resolvedElement(value, path);

    return {
      target: value.target as string,
      matchCount: 1 as const,
      hidden: element.hidden,
      rect: element.rect,
    };
  }

  if ("hidden" in value || "rect" in value) {
    malformed(`${path} unresolved targets must not contain element state`);
  }

  return {
    target: value.target as string,
    matchCount,
  };
}

function collectionTarget(
  value: UnknownRecord,
  path: string,
): CollectionTargetResolution {
  if (!Array.isArray(value.matches)) {
    malformed(`${path}.matches must be an array`);
  }

  return {
    target: value.target as string,
    matches: value.matches.map((match, index) => {
      const matchPath = `${path}.matches[${index}]`;

      if (!isRecord(match)) {
        malformed(`${matchPath} must be an object`);
      }

      return resolvedElement(match, matchPath);
    }),
  };
}

function targetResolution(
  value: unknown,
  path: string,
  requested: Set<string>,
): SingularTargetResolution | CollectionTargetResolution {
  if (!isRecord(value)) {
    malformed(`${path} must be an object`);
  }

  if (typeof value.target !== "string") {
    malformed(`${path}.target must be a string`);
  }

  if (!requested.has(value.target)) {
    malformed(`${path}.target does not correlate to a requested target`);
  }

  const hasMatchCount = "matchCount" in value;
  const hasMatches = "matches" in value;

  if (hasMatchCount === hasMatches) {
    malformed(`${path} must be either a singular or collection result`);
  }

  return hasMatchCount
    ? singularTarget(value, path)
    : collectionTarget(value, path);
}

function rawTarget(
  resolution: SingularTargetResolution | CollectionTargetResolution,
): RawElementMeasurement {
  if ("matchCount" in resolution) {
    if (resolution.matchCount === 1) {
      if (resolution.hidden === undefined || resolution.rect === undefined) {
        throw new Error("Validated resolved targets must contain element state");
      }

      return {
        testId: resolution.target,
        count: 1,
        hidden: resolution.hidden,
        rect: resolution.rect,
      };
    }

    return {
      testId: resolution.target,
      count: resolution.matchCount,
      hidden: null,
      rect: null,
    };
  }

  if (resolution.matches.length === 1) {
    return {
      testId: resolution.target,
      count: 1,
      hidden: resolution.matches[0]!.hidden,
      rect: resolution.matches[0]!.rect,
    };
  }

  return {
    testId: resolution.target,
    count: resolution.matches.length,
    hidden: null,
    rect: null,
  };
}

export function validatePublicSnapshot(
  value: unknown,
  requestedTargets: readonly string[],
): RawMeasurementSnapshot {
  if (!isRecord(value)) {
    malformed("snapshot must be an object");
  }

  if (!isRecord(value.viewport)) {
    malformed("viewport must be an object");
  }

  if (!Array.isArray(value.targets)) {
    malformed("targets must be an array");
  }

  const viewport = {
    width: finiteNumber(value.viewport.width, "viewport.width"),
    height: finiteNumber(value.viewport.height, "viewport.height"),
  };

  if (viewport.width <= 0 || viewport.height <= 0) {
    malformed("viewport dimensions must be positive");
  }

  const requested = new Set(requestedTargets);
  const targets = value.targets.map((entry, index) =>
    targetResolution(entry, `targets[${index}]`, requested),
  );
  const measured = new Set(targets.map(({ target }) => target));

  if (
    measured.size !== targets.length ||
    measured.size !== requested.size ||
    [...requested].some((target) => !measured.has(target))
  ) {
    malformed("targets must correlate one-to-one with requested targets");
  }

  const snapshot: MeasurementSnapshot = { viewport, targets };

  return {
    viewport: snapshot.viewport,
    elements: snapshot.targets.map(rawTarget),
  };
}
