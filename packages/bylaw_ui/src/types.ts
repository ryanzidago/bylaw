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

export type WidthRule = {
  kind: "width";
  target: string;
  range: PixelRange;
};

export type HeightRule = {
  kind: "height";
  target: string;
  range: PixelRange;
};

export type InViewportRule = {
  kind: "inViewport";
  target: string;
};

export type UnaryGeometryRule = WidthRule | HeightRule | InViewportRule;

export type LayoutRule =
  | AlignRule
  | OrderingRule
  | OverlapRule
  | NotOverlapRule
  | ToleranceRule
  | UnaryGeometryRule;

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
  | "size-mismatch"
  | "dimension-out-of-range"
  | "viewport-overflow";

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

type BinaryElementFindingIdentity = {
  ruleIndex: number;
  message: string;
  subject: string;
  reference: string;
  operand: "subject" | "reference";
  testId: string;
};

type UnaryElementFindingIdentity = {
  ruleIndex: number;
  message: string;
  target: string;
  operand: "target";
  testId: string;
};

type ResolutionFinding = {
  category: "element-resolution";
  code: ElementResolutionCode;
  expected: { matchCount: number };
  actual: { matchCount: number };
};

type BinaryVisibilityFinding =
  | {
      category: "element-visibility";
      code: "hidden-element";
      expected: { visible: true; positiveSize: true };
      actual: { hidden: true; width: number; height: number };
    }
  | {
      category: "element-visibility";
      code: "zero-size-element";
      expected: { visible: true; positiveSize: true };
      actual: { hidden: false; width: number; height: number };
    };

type UnaryVisibilityFinding =
  | {
      category: "element-visibility";
      code: "hidden-element";
      expected: { visible: true; positiveSize: true };
      actual: { hidden: true };
    }
  | {
      category: "element-visibility";
      code: "zero-size-element";
      expected: { visible: true; positiveSize: true };
      actual: { hidden: false; width: number; height: number };
    };

export type BinaryElementFinding = BinaryElementFindingIdentity &
  (ResolutionFinding | BinaryVisibilityFinding);

export type UnaryElementFinding = UnaryElementFindingIdentity &
  (ResolutionFinding | UnaryVisibilityFinding);

export type ElementFinding = BinaryElementFinding | UnaryElementFinding;

type BinaryLayoutCode = Exclude<
  LayoutCode,
  "dimension-out-of-range" | "viewport-overflow"
>;

export type BinaryLayoutViolationFinding = {
  category: "layout";
  code: BinaryLayoutCode;
  ruleIndex: number;
  message: string;
  subject: string;
  reference: string;
  relationship: Exclude<LayoutRule, UnaryGeometryRule>["kind"];
  expected: { [key: string]: JsonValue | undefined };
  actual: { [key: string]: JsonValue | undefined };
};

export type WidthLayoutViolationFinding = {
  category: "layout";
  code: "dimension-out-of-range";
  ruleIndex: number;
  message: string;
  target: string;
  relationship: "width";
  expected: { range: PixelRange };
  actual: { widthPx: number };
};

export type HeightLayoutViolationFinding = {
  category: "layout";
  code: "dimension-out-of-range";
  ruleIndex: number;
  message: string;
  target: string;
  relationship: "height";
  expected: { range: PixelRange };
  actual: { heightPx: number };
};

type ViewportEdges = {
  leftPx: number;
  topPx: number;
  rightPx: number;
  bottomPx: number;
};

export type ViewportLayoutViolationFinding = {
  category: "layout";
  code: "viewport-overflow";
  ruleIndex: number;
  message: string;
  target: string;
  relationship: "inViewport";
  expected: { viewport: ViewportEdges };
  actual: { target: ViewportEdges };
};

export type UnaryLayoutViolationFinding =
  | WidthLayoutViolationFinding
  | HeightLayoutViolationFinding
  | ViewportLayoutViolationFinding;

export type LayoutViolationFinding =
  | BinaryLayoutViolationFinding
  | UnaryLayoutViolationFinding;

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
