export type Alignment =
  | "left"
  | "right"
  | "top"
  | "bottom"
  | "centerX"
  | "centerY";

export type PixelRange = {
  minPx?: number;
  maxPx?: number;
};

export type ToleranceOptions = {
  tolerancePx?: number;
};

export type OrderingOptions = ToleranceOptions & {
  gap?: PixelRange;
};

export type OverlapOptions = {
  horizontal?: PixelRange;
  vertical?: PixelRange;
};

export type AlignRule = {
  kind: "align";
  subject: string;
  reference: string;
  alignment: Alignment;
  options?: ToleranceOptions;
};

export type OrderingRule = {
  kind: "above" | "below" | "leftOf" | "rightOf";
  subject: string;
  reference: string;
  options?: OrderingOptions;
};

export type OverlapRule = {
  kind: "overlap";
  subject: string;
  reference: string;
  options?: OverlapOptions;
};

export type NotOverlapRule = {
  kind: "notOverlap";
  subject: string;
  reference: string;
};

export type ToleranceRule = {
  kind: "inside" | "sameWidth" | "sameHeight" | "sameSize";
  subject: string;
  reference: string;
  options?: ToleranceOptions;
};

export type LayoutRule =
  | AlignRule
  | OrderingRule
  | OverlapRule
  | NotOverlapRule
  | ToleranceRule;

export type InvalidRuleCode =
  | "missing-field"
  | "invalid-type"
  | "invalid-value"
  | "unknown-field";

export type ElementResolutionCode = "missing-element" | "duplicate-element";
export type ElementVisibilityCode = "hidden-element" | "zero-size-element";
export type LayoutCode =
  | "alignment-mismatch"
  | "ordering-violation"
  | "gap-out-of-range"
  | "missing-overlap"
  | "overlap-out-of-range"
  | "containment-overflow"
  | "size-mismatch";

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue =
  | JsonPrimitive
  | JsonValue[]
  | { [key: string]: JsonValue | undefined };

export type InvalidRuleFinding = {
  category: "invalid-rule";
  code: InvalidRuleCode;
  ruleIndex: number;
  message: string;
  fieldPath: string;
  reason: string;
};

export type ElementFinding = {
  category: "element-resolution" | "element-visibility";
  code: ElementResolutionCode | ElementVisibilityCode;
  ruleIndex: number;
  message: string;
  subject: string;
  reference: string;
  operand: "subject" | "reference";
  testId: string;
  expected: { matchCount: number } | { visible: true; positiveSize: true };
  actual: { matchCount: number } | { hidden: boolean; width: number; height: number };
};

export type LayoutViolationFinding = {
  category: "layout";
  code: LayoutCode;
  ruleIndex: number;
  message: string;
  subject: string;
  reference: string;
  relationship: LayoutRule["kind"];
  expected: { [key: string]: JsonValue | undefined };
  actual: { [key: string]: JsonValue | undefined };
  measurements?: { [key: string]: JsonValue | undefined };
};

export type LayoutFinding =
  | InvalidRuleFinding
  | ElementFinding
  | LayoutViolationFinding;

export type LayoutReport = {
  passed: boolean;
  rules: {
    total: number;
    passed: number;
    failed: number;
    skipped: number;
  };
  findings: LayoutFinding[];
};
