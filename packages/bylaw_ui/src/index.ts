export { assertLayout, LayoutAssertionError } from "./assert-layout.js";
export { checkLayout } from "./check-layout.js";
export { createAdapter } from "./adapter.js";
export { MeasurementValidationError } from "./internal/public-snapshot.js";
import {
  collection as collectionRuleTarget,
  equalWidths as equalWidthsRule,
  everyInside as everyInsideRule,
  pairwiseNotOverlap as pairwiseNotOverlapRule,
  verticallyOrdered as verticallyOrderedRule,
} from "./rules.js";
import type {
  CollectionOrderingOptions,
  EqualWidthsRule,
  EveryInsideRule,
  PairwiseNotOverlapRule,
  ToleranceOptions,
  VerticallyOrderedRule,
} from "./types.js";

export type CollectionTarget = {
  kind: "collection";
  target: string;
};

export function collection(target: string): CollectionTarget {
  return collectionRuleTarget(target);
}

export function everyInside(
  target: CollectionTarget,
  container: string,
  options?: ToleranceOptions,
): EveryInsideRule {
  return everyInsideRule(target, container, options);
}

export function equalWidths(
  target: CollectionTarget,
  options?: ToleranceOptions,
): EqualWidthsRule {
  return equalWidthsRule(target, options);
}

export function verticallyOrdered(
  target: CollectionTarget,
  options?: CollectionOrderingOptions,
): VerticallyOrderedRule {
  return verticallyOrderedRule(target, options);
}

export function pairwiseNotOverlap(
  target: CollectionTarget,
): PairwiseNotOverlapRule {
  return pairwiseNotOverlapRule(target);
}

export type {
  Adapter,
  AdapterImplementation,
  CollectionTargetResolution,
  MeasurementSnapshot,
  Rectangle,
  SingularTargetResolution,
  Viewport,
} from "./adapter.js";
export type { CheckLayoutInput } from "./check-layout.js";
export {
  above,
  align,
  below,
  height,
  inViewport,
  inside,
  leftOf,
  notOverlap,
  overlap,
  rightOf,
  sameHeight,
  sameSize,
  sameWidth,
  width,
} from "./rules.js";
export type {
  Alignment,
  AlignRule,
  CollectionFinding,
  CollectionOrderingOptions,
  CollectionRule,
  EqualWidthsRule,
  ElementFinding,
  HeightRule,
  InViewportRule,
  InvalidRuleFinding,
  LayoutFinding,
  LayoutReport,
  LayoutRule,
  LayoutViolationFinding,
  NotOverlapRule,
  OrderingOptions,
  OrderingRule,
  OverlapOptions,
  OverlapRule,
  PixelRange,
  ToleranceOptions,
  ToleranceRule,
  EveryInsideRule,
  PairwiseNotOverlapRule,
  VerticallyOrderedRule,
  UnaryGeometryRule,
  WidthRule,
} from "./types.js";
