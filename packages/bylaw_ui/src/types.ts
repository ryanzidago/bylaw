export type Alignment =
  "left" | "right" | "top" | "bottom" | "centerX" | "centerY";

export type PixelRange = {
  minPx?: number;
  maxPx?: number;
};

export type ToleranceOptions = {
  tolerancePx?: number;
};

export type CollectionTarget = {
  kind: "collection";
  target: string;
};

export type CollectionOrderingOptions = {
  gap?: PixelRange;
};

export type EveryInsideRule = {
  kind: "everyInside";
  collection: CollectionTarget;
  container: string;
  options?: ToleranceOptions;
};

export type EqualWidthsRule = {
  kind: "equalWidths";
  collection: CollectionTarget;
  options?: ToleranceOptions;
};

export type VerticallyOrderedRule = {
  kind: "verticallyOrdered";
  collection: CollectionTarget;
  options?: CollectionOrderingOptions;
};

export type PairwiseNotOverlapRule = {
  kind: "pairwiseNotOverlap";
  collection: CollectionTarget;
};

export type CollectionRule =
  | EveryInsideRule
  | EqualWidthsRule
  | VerticallyOrderedRule
  | PairwiseNotOverlapRule;

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
  | UnaryGeometryRule
  | CollectionRule;

export type InvalidRuleCode =
  "missing-field" | "invalid-type" | "invalid-value" | "unknown-field";

export type ElementResolutionCode =
  "missing-element" | "duplicate-element" | "empty-collection";
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
  | "viewport-overflow"
  | "collection-containment-overflow"
  | "collection-width-mismatch"
  | "collection-ordering-violation"
  | "collection-gap-out-of-range"
  | "collection-overlap";

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue =
  JsonPrimitive | JsonValue[] | { [key: string]: JsonValue | undefined };

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
  target?: string;
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
  "dimension-out-of-range" | "viewport-overflow" | `collection-${string}`
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
  BinaryLayoutViolationFinding | UnaryLayoutViolationFinding;

type CollectionMember = {
  target: string;
  collectionIndex: number;
};

export type CollectionFinding =
  | {
      category: "element-resolution";
      code: "empty-collection";
      ruleIndex: number;
      message: string;
      target: string;
      operand: "collection";
      expected: { minMatchCount: number };
      actual: { matchCount: number };
    }
  | {
      category: "element-visibility";
      code: ElementVisibilityCode;
      ruleIndex: number;
      message: string;
      target: string;
      collectionIndex: number;
      operand: "collection";
      expected: { visible: true; positiveSize: true };
      actual: { [key: string]: JsonValue | undefined };
    }
  | {
      category: "layout";
      code: "collection-containment-overflow";
      ruleIndex: number;
      message: string;
      relationship: "everyInside";
      target: string;
      collectionIndex: number;
      expected: { [key: string]: JsonValue | undefined };
      actual: { [key: string]: JsonValue | undefined };
    }
  | {
      category: "layout";
      code: "collection-width-mismatch";
      ruleIndex: number;
      message: string;
      relationship: "equalWidths";
      target: string;
      collectionIndex: number;
      expected: { [key: string]: JsonValue | undefined };
      actual: { [key: string]: JsonValue | undefined };
    }
  | {
      category: "layout";
      code: "collection-ordering-violation" | "collection-gap-out-of-range";
      ruleIndex: number;
      message: string;
      relationship: "verticallyOrdered";
      subject: CollectionMember;
      reference: CollectionMember;
      expected: { [key: string]: JsonValue | undefined };
      actual: { [key: string]: JsonValue | undefined };
    }
  | {
      category: "layout";
      code: "collection-overlap";
      ruleIndex: number;
      message: string;
      relationship: "pairwiseNotOverlap";
      subject: CollectionMember;
      reference: CollectionMember;
      expected: { [key: string]: JsonValue | undefined };
      actual: { [key: string]: JsonValue | undefined };
    };

export type LayoutFinding =
  | InvalidRuleFinding
  | ElementFinding
  | LayoutViolationFinding
  | CollectionFinding;

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
