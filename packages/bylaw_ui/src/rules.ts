import type {
  Alignment,
  AlignRule,
  LayoutRule,
  NotOverlapRule,
  OrderingOptions,
  OrderingRule,
  OverlapOptions,
  OverlapRule,
  ToleranceOptions,
  ToleranceRule,
} from "./types";
import { validateRule } from "./internal/validation";

function checked<T extends LayoutRule>(rule: T): T {
  const findings = validateRule(rule, 0);

  if (findings.length > 0) {
    throw new TypeError(
      findings.map(({ fieldPath, reason }) => `${fieldPath}: ${reason}`).join("; "),
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
