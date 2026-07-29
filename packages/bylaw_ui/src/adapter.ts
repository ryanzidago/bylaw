export type Rectangle = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type Viewport = {
  width: number;
  height: number;
};

type ResolvedElement = {
  hidden: boolean;
  rect: Rectangle;
};

type ResolvedSingularTarget = ResolvedElement & {
  target: string;
  matchCount: 1;
};

type UnresolvedSingularTarget = {
  target: string;
  matchCount: number;
  hidden?: never;
  rect?: never;
};

export type SingularTargetResolution =
  ResolvedSingularTarget | UnresolvedSingularTarget;

export type CollectionTargetResolution = {
  target: string;
  matches: ResolvedElement[];
};

export type MeasurementSnapshot = {
  viewport: Viewport;
  targets: Array<SingularTargetResolution | CollectionTargetResolution>;
};

export type AdapterImplementation = {
  measure: (
    targets: readonly string[],
  ) => MeasurementSnapshot | Promise<MeasurementSnapshot>;
};

declare const adapterTypeBrand: unique symbol;

export type Adapter = {
  readonly [adapterTypeBrand]: true;
  measure(targets: readonly string[]): Promise<unknown>;
};

const adapters = new WeakSet<object>();

export function createAdapter(implementation: AdapterImplementation): Adapter;
export function createAdapter(implementation?: unknown): Adapter;
export function createAdapter(implementation?: unknown): Adapter {
  if (
    typeof implementation !== "object" ||
    implementation === null ||
    Array.isArray(implementation)
  ) {
    throw new TypeError(
      "createAdapter expects an adapter implementation object",
    );
  }

  if (
    !("measure" in implementation) ||
    typeof implementation.measure !== "function"
  ) {
    throw new TypeError(
      "createAdapter implementation.measure must be a function",
    );
  }

  const measure = implementation.measure.bind(implementation) as (
    targets: readonly string[],
  ) => unknown;
  const adapter = Object.freeze({
    measure: async (targets: readonly string[]) =>
      measure(Object.freeze([...targets])),
  });
  adapters.add(adapter);

  return adapter as Adapter;
}

export function isAdapter(value: unknown): value is Adapter {
  return (
    typeof value === "object" &&
    value !== null &&
    adapters.has(value) &&
    "measure" in value &&
    typeof value.measure === "function"
  );
}
