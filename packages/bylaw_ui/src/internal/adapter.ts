export type Rectangle = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type RawElementMeasurement = {
  testId: string;
  count: number;
  hidden: boolean | null;
  rect: Rectangle | null;
};

export type RawMeasurementSnapshot = {
  viewport: {
    width: number;
    height: number;
  };
  elements: RawElementMeasurement[];
};

const adapterBrand = Symbol.for("bylaw-ui.internal.adapter");

export type InternalAdapter = {
  readonly [adapterBrand]: true;
  measure(testIds: readonly string[]): Promise<unknown>;
};

export function createInternalAdapter(
  measure: (testIds: readonly string[]) => Promise<unknown>,
): InternalAdapter {
  return Object.freeze({
    [adapterBrand]: true as const,
    measure,
  });
}

export function isInternalAdapter(value: unknown): value is InternalAdapter {
  return (
    typeof value === "object" &&
    value !== null &&
    adapterBrand in value &&
    value[adapterBrand] === true &&
    "measure" in value &&
    typeof value.measure === "function"
  );
}
