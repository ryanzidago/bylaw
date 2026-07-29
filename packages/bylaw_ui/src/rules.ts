import type {
  Alignment,
  AlignRule,
  CollectionOrderingOptions,
  CollectionTarget,
  EqualWidthsRule,
  EveryInsideRule,
  HeightRule,
  InViewportRule,
  LayoutRule,
  NotOverlapRule,
  OrderingOptions,
  OrderingRule,
  OverlapOptions,
  OverlapRule,
  PixelRange,
  ToleranceOptions,
  ToleranceRule,
  WidthRule,
  PairwiseNotOverlapRule,
  VerticallyOrderedRule,
} from "./types.js";
import { validateRule } from "./internal/validation.js";

function checked<T extends LayoutRule>(rule: T): T {
  const findings = validateRule(rule, 0);

  if (findings.length > 0) {
    throw new TypeError(
      findings
        .map(({ fieldPath, reason }) => `${fieldPath}: ${reason}`)
        .join("; "),
    );
  }

  return rule;
}

function copyToleranceOptions(
  options: ToleranceOptions | undefined,
): ToleranceOptions | undefined {
  return options === undefined ? undefined : { ...options };
}

function copyOrderingOptions(
  options: OrderingOptions | undefined,
): OrderingOptions | undefined {
  return options === undefined
    ? undefined
    : {
        ...options,
        ...(options.gap === undefined ? {} : { gap: { ...options.gap } }),
      };
}

function copyOverlapOptions(
  options: OverlapOptions | undefined,
): OverlapOptions | undefined {
  return options === undefined
    ? undefined
    : {
        ...(options.horizontal === undefined
          ? {}
          : { horizontal: { ...options.horizontal } }),
        ...(options.vertical === undefined
          ? {}
          : { vertical: { ...options.vertical } }),
      };
}

function withOptions<T extends LayoutRule>(
  rule: Omit<T, "options">,
  options: T extends { options?: infer O } ? O | undefined : never,
): T {
  return (options === undefined ? rule : { ...rule, options }) as T;
}

export function align(
  subject: string,
  reference: string,
  alignment: Alignment,
  options?: ToleranceOptions,
): AlignRule {
  return checked(
    withOptions<AlignRule>(
      { kind: "align", subject, reference, alignment },
      copyToleranceOptions(options),
    ),
  );
}

function orderingRule(
  kind: OrderingRule["kind"],
  subject: string,
  reference: string,
  options?: OrderingOptions,
): OrderingRule {
  return checked(
    withOptions<OrderingRule>(
      { kind, subject, reference },
      copyOrderingOptions(options),
    ),
  );
}

export function above(
  subject: string,
  reference: string,
  options?: OrderingOptions,
): OrderingRule {
  return orderingRule("above", subject, reference, options);
}

export function below(
  subject: string,
  reference: string,
  options?: OrderingOptions,
): OrderingRule {
  return orderingRule("below", subject, reference, options);
}

export function leftOf(
  subject: string,
  reference: string,
  options?: OrderingOptions,
): OrderingRule {
  return orderingRule("leftOf", subject, reference, options);
}

export function rightOf(
  subject: string,
  reference: string,
  options?: OrderingOptions,
): OrderingRule {
  return orderingRule("rightOf", subject, reference, options);
}

export function overlap(
  subject: string,
  reference: string,
  options?: OverlapOptions,
): OverlapRule {
  return checked(
    withOptions<OverlapRule>(
      { kind: "overlap", subject, reference },
      copyOverlapOptions(options),
    ),
  );
}

export function notOverlap(subject: string, reference: string): NotOverlapRule {
  if (arguments.length > 2) {
    throw new TypeError("options: is not supported by notOverlap");
  }

  return checked({ kind: "notOverlap", subject, reference });
}

function toleranceRule(
  kind: ToleranceRule["kind"],
  subject: string,
  reference: string,
  options?: ToleranceOptions,
): ToleranceRule {
  return checked(
    withOptions<ToleranceRule>(
      { kind, subject, reference },
      copyToleranceOptions(options),
    ),
  );
}

export function inside(
  subject: string,
  reference: string,
  options?: ToleranceOptions,
): ToleranceRule {
  return toleranceRule("inside", subject, reference, options);
}

export function sameWidth(
  subject: string,
  reference: string,
  options?: ToleranceOptions,
): ToleranceRule {
  return toleranceRule("sameWidth", subject, reference, options);
}

export function sameHeight(
  subject: string,
  reference: string,
  options?: ToleranceOptions,
): ToleranceRule {
  return toleranceRule("sameHeight", subject, reference, options);
}

export function sameSize(
  subject: string,
  reference: string,
  options?: ToleranceOptions,
): ToleranceRule {
  return toleranceRule("sameSize", subject, reference, options);
}

function unaryRangeRule(
  kind: "width" | "height",
  target: string,
  range: PixelRange,
): WidthRule | HeightRule {
  return checked({ kind, target, range: { ...range } });
}

export function width(target: string, range: PixelRange): WidthRule {
  return unaryRangeRule("width", target, range) as WidthRule;
}

export function height(target: string, range: PixelRange): HeightRule {
  return unaryRangeRule("height", target, range) as HeightRule;
}

export function inViewport(target: string): InViewportRule {
  return checked({ kind: "inViewport", target });
}

export function collection(target: string): CollectionTarget {
  const declaration = { kind: "collection" as const, target };
  const findings = validateRule(
    { kind: "equalWidths", collection: declaration },
    0,
  );
  const targetFinding = findings.find(({ fieldPath }) =>
    fieldPath.startsWith("collection"),
  );
  if (targetFinding) {
    throw new TypeError(`${targetFinding.fieldPath}: ${targetFinding.reason}`);
  }
  return declaration;
}

function copyCollection(target: CollectionTarget): CollectionTarget {
  return { ...target };
}

export function everyInside(
  target: CollectionTarget,
  container: string,
  options?: ToleranceOptions,
): EveryInsideRule {
  return checked(
    withOptions<EveryInsideRule>(
      {
        kind: "everyInside",
        collection: copyCollection(target),
        container,
      },
      copyToleranceOptions(options),
    ),
  );
}

export function equalWidths(
  target: CollectionTarget,
  options?: ToleranceOptions,
): EqualWidthsRule {
  return checked(
    withOptions<EqualWidthsRule>(
      { kind: "equalWidths", collection: copyCollection(target) },
      copyToleranceOptions(options),
    ),
  );
}

export function verticallyOrdered(
  target: CollectionTarget,
  options?: CollectionOrderingOptions,
): VerticallyOrderedRule {
  return checked(
    withOptions<VerticallyOrderedRule>(
      { kind: "verticallyOrdered", collection: copyCollection(target) },
      options === undefined
        ? undefined
        : {
            ...(options.gap === undefined ? {} : { gap: { ...options.gap } }),
          },
    ),
  );
}

export function pairwiseNotOverlap(
  target: CollectionTarget,
): PairwiseNotOverlapRule {
  if (arguments.length > 1) {
    throw new TypeError("options: is not supported by pairwiseNotOverlap");
  }
  return checked({
    kind: "pairwiseNotOverlap",
    collection: copyCollection(target),
  });
}
