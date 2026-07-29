import { test } from "bun:test";

test("alignment diagnostics identify the rule, subject, reference, and aligned edge", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "alignment-mismatch", ruleIndex: 3, message: "legacy", subject: "avatar", reference: "card", relationship: "align", expected: { alignment: "left", tolerancePx: 0 }, actual: { subjectCoordinate: 12, referenceCoordinate: 10, differencePx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 4, passed: 3, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["rule 3", "align failed", 'subject: "avatar"', 'reference: "card"', "alignment: left"]) expect(m).toContain(s);
});

test("alignment diagnostics report both measured coordinates in CSS pixels", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "alignment-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "align", expected: { alignment: "left", tolerancePx: 0 }, actual: { subjectCoordinate: 12.5, referenceCoordinate: 10.25, differencePx: 2.25 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("subject coordinate: 12.5px"); expect(m).toContain("reference coordinate: 10.25px");
});

test("alignment diagnostics report the absolute difference, allowed tolerance, and excess", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "alignment-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "align", expected: { alignment: "left", tolerancePx: 1 }, actual: { subjectCoordinate: 12, referenceCoordinate: 10, differencePx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["difference: 2px", "allowed tolerance: 1px", "exceeds tolerance by: 1px"]) expect(m).toContain(s);
});

test("tolerance diagnostics report zero pixels when tolerance is omitted", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "size-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "sameWidth", expected: { tolerancePx: 0 }, actual: { subjectWidthPx: 8, referenceWidthPx: 10, widthDifferencePx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("allowed tolerance: 0px");
});

test("ordering diagnostics identify the directional relationship and both operands", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  for (const relationship of ["above", "below", "leftOf", "rightOf"]) {
    const f = { category: "layout", code: "ordering-violation", ruleIndex: 0, message: "legacy", subject: "avatar", reference: "card", relationship, expected: { tolerancePx: 0 }, actual: { signedGapPx: -2, boundaryCrossingPx: 2 } };
    const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
    for (const s of [`${relationship} failed`, 'subject: "avatar"', 'reference: "card"']) expect(m).toContain(s);
  }
});

test("ordering violation diagnostics report the signed gap and boundary crossing in CSS pixels", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "ordering-violation", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { tolerancePx: 0 }, actual: { signedGapPx: -2, boundaryCrossingPx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("signed gap: -2px"); expect(m).toContain("boundary crossing: 2px");
});

test("ordering violation diagnostics report the allowed tolerance and excess boundary crossing", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "ordering-violation", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { tolerancePx: 1 }, actual: { signedGapPx: -2, boundaryCrossingPx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("allowed tolerance: 1px"); expect(m).toContain("exceeds tolerance by: 1px");
});

test("bounded gap diagnostics report the measured gap and both allowed endpoints", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "gap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { gap: { minPx: 4, maxPx: 8 } }, actual: { signedGapPx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("measured gap: 2px"); expect(m).toContain("allowed gap: 4px–8px");
});

test("bounded gap diagnostics report distance below the minimum endpoint", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "gap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { gap: { minPx: 4, maxPx: 8 } }, actual: { signedGapPx: 2 } };
  expect(new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message).toContain("below minimum by: 2px");
});

test("bounded gap diagnostics report distance above the maximum endpoint", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "gap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { gap: { minPx: 4, maxPx: 8 } }, actual: { signedGapPx: 10 } };
  expect(new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message).toContain("above maximum by: 2px");
});

test("minimum-only gap diagnostics report how far the measurement is below the minimum", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "gap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { gap: { minPx: 4 } }, actual: { signedGapPx: 1.5 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("allowed gap: at least 4px"); expect(m).toContain("below minimum by: 2.5px");
});

test("maximum-only gap diagnostics report how far the measurement exceeds the maximum", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "gap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { gap: { maxPx: 8 } }, actual: { signedGapPx: 10.5 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("allowed gap: at most 8px"); expect(m).toContain("above maximum by: 2.5px");
});

test("missing overlap diagnostics report horizontal and vertical overlap depths including zeroes", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "missing-overlap", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "overlap", expected: { overlap: true }, actual: { horizontalPx: 0, verticalPx: 10 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("horizontal overlap: 0px"); expect(m).toContain("vertical overlap: 10px");
});

test("missing overlap diagnostics state that positive overlap is required on both axes", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "missing-overlap", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "overlap", expected: { overlap: true }, actual: { horizontalPx: 0, verticalPx: 10 } };
  expect(new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message).toContain("required overlap: positive on both axes");
});

test("constrained overlap diagnostics report measured depths and each configured range", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "overlap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "overlap", expected: { horizontal: { minPx: 4, maxPx: 8 }, vertical: { minPx: 6, maxPx: 10 } }, actual: { horizontalPx: 2, verticalPx: 12 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["horizontal overlap: 2px", "allowed horizontal overlap: 4px–8px", "vertical overlap: 12px", "allowed vertical overlap: 6px–10px"]) expect(m).toContain(s);
});

test("constrained overlap diagnostics report the distance from every violated range boundary", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "overlap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "overlap", expected: { horizontal: { minPx: 4, maxPx: 8 }, vertical: { minPx: 6, maxPx: 10 } }, actual: { horizontalPx: 2, verticalPx: 12 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("horizontal below minimum by: 2px"); expect(m).toContain("vertical above maximum by: 2px");
});

test("minimum-only overlap diagnostics report how far the depth is below the minimum", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "overlap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "overlap", expected: { horizontal: { minPx: 4 } }, actual: { horizontalPx: 2, verticalPx: 10 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("allowed horizontal overlap: at least 4px"); expect(m).toContain("horizontal below minimum by: 2px");
});

test("maximum-only overlap diagnostics report how far the depth exceeds the maximum", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "overlap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "overlap", expected: { horizontal: { maxPx: 6 } }, actual: { horizontalPx: 8, verticalPx: 10 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("allowed horizontal overlap: at most 6px"); expect(m).toContain("horizontal above maximum by: 2px");
});

test("overlap diagnostics do not report a range violation for a valid axis", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "overlap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "overlap", expected: { horizontal: { minPx: 4, maxPx: 8 }, vertical: { minPx: 6, maxPx: 10 } }, actual: { horizontalPx: 2, verticalPx: 8 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("horizontal below minimum by: 2px"); expect(m).not.toContain("vertical below minimum"); expect(m).not.toContain("vertical above maximum");
});

test("notOverlap diagnostics report positive overlap depths on both axes", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "overlap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "notOverlap", expected: { overlap: false }, actual: { horizontalPx: 5, verticalPx: 10 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("horizontal overlap: 5px"); expect(m).toContain("vertical overlap: 10px");
});

test("notOverlap diagnostics state that positive overlap is prohibited", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "overlap-out-of-range", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "notOverlap", expected: { overlap: false }, actual: { horizontalPx: 5, verticalPx: 10 } };
  expect(new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message).toContain("allowed overlap: none");
});

test("containment diagnostics report overflow on all four sides including zeroes", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "containment-overflow", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "inside", expected: { tolerancePx: 0, positiveIntersection: true }, actual: { leftPx: 2, rightPx: 0, topPx: 3, bottomPx: 0, horizontalPx: 8, verticalPx: 7 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["left overflow: 2px", "right overflow: 0px", "top overflow: 3px", "bottom overflow: 0px"]) expect(m).toContain(s);
});

test("containment diagnostics report intersection depths when positive intersection is missing", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "containment-overflow", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "inside", expected: { tolerancePx: 0, positiveIntersection: true }, actual: { leftPx: 0, rightPx: 15, topPx: 0, bottomPx: 0, horizontalPx: 0, verticalPx: 5 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["horizontal intersection: 0px", "vertical intersection: 5px", "required intersection: positive on both axes"]) expect(m).toContain(s);
});

test("containment diagnostics report the allowed tolerance, maximum overflow, and excess", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "containment-overflow", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "inside", expected: { tolerancePx: 1, positiveIntersection: true }, actual: { leftPx: 2, rightPx: 0, topPx: 0, bottomPx: 0, horizontalPx: 8, verticalPx: 10 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["allowed tolerance: 1px", "maximum overflow: 2px", "exceeds tolerance by: 1px"]) expect(m).toContain(s);
});

test("containment diagnostics do not report excess for edges within tolerance", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "containment-overflow", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "inside", expected: { tolerancePx: 1, positiveIntersection: true }, actual: { leftPx: 2, rightPx: 1, topPx: 0, bottomPx: 0, horizontalPx: 8, verticalPx: 10 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("left exceeds tolerance by: 1px"); expect(m).not.toContain("right exceeds tolerance");
});

test("sameWidth diagnostics report subject width, reference width, and absolute difference", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "size-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "sameWidth", expected: { tolerancePx: 0 }, actual: { subjectWidthPx: 1038, referenceWidthPx: 1040, widthDifferencePx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["subject width: 1038px", "reference width: 1040px", "difference: 2px"]) expect(m).toContain(s);
});

test("sameHeight diagnostics report subject height, reference height, and absolute difference", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "size-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "sameHeight", expected: { tolerancePx: 0 }, actual: { subjectHeightPx: 718, referenceHeightPx: 720, heightDifferencePx: 2 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["subject height: 718px", "reference height: 720px", "difference: 2px"]) expect(m).toContain(s);
});

test("sameSize diagnostics report subject and reference measurements for both dimensions", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "size-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "sameSize", expected: { tolerancePx: 0 }, actual: { subjectWidthPx: 98, referenceWidthPx: 100, widthDifferencePx: 2, subjectHeightPx: 47, referenceHeightPx: 50, heightDifferencePx: 3 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["subject width: 98px", "reference width: 100px", "width difference: 2px", "subject height: 47px", "reference height: 50px", "height difference: 3px"]) expect(m).toContain(s);
});

test("size diagnostics report the allowed tolerance and excess for every failing dimension", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "size-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "sameSize", expected: { tolerancePx: 1 }, actual: { subjectWidthPx: 98, referenceWidthPx: 100, widthDifferencePx: 2, subjectHeightPx: 47, referenceHeightPx: 50, heightDifferencePx: 3 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["allowed tolerance: 1px", "width exceeds tolerance by: 1px", "height exceeds tolerance by: 2px"]) expect(m).toContain(s);
});

test("sameSize diagnostics do not report excess for a dimension within tolerance", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "size-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "sameSize", expected: { tolerancePx: 1 }, actual: { subjectWidthPx: 98, referenceWidthPx: 100, widthDifferencePx: 2, subjectHeightPx: 49, referenceHeightPx: 50, heightDifferencePx: 1 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("width exceeds tolerance by: 1px"); expect(m).not.toContain("height exceeds tolerance");
});

test("geometry diagnostics preserve fractional CSS-pixel measurements without unnecessary trailing zeroes", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "size-mismatch", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "sameWidth", expected: { tolerancePx: 0.25 }, actual: { subjectWidthPx: 98.5, referenceWidthPx: 100, widthDifferencePx: 1.5 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  for (const s of ["98.5px", "100px", "1.5px", "0.25px", "1.25px"]) expect(m).toContain(s);
  expect(m).not.toContain("100.0px");
});

test("geometry diagnostics render negative zero as zero pixels", () => {
  const { expect } = require("bun:test"); const { LayoutAssertionError } = require("bylaw-ui");
  const f = { category: "layout", code: "ordering-violation", ruleIndex: 0, message: "legacy", subject: "a", reference: "b", relationship: "leftOf", expected: { tolerancePx: 0 }, actual: { signedGapPx: -0, boundaryCrossingPx: 0 } };
  const m = new LayoutAssertionError({ passed: false, rules: { total: 1, passed: 0, failed: 1, skipped: 0 }, findings: [f] }).message;
  expect(m).toContain("signed gap: 0px"); expect(m).not.toContain("-0px");
});

/**
 * @doc
 * Issue: Subtracting a fractional tolerance from a measured difference can
 * expose JavaScript floating-point artifacts in the rendered excess.
 * Why it matters: Assertion diagnostics should report readable CSS-pixel
 * measurements instead of values such as 0.19999999999999998px.
 */
test("fractional tolerance excesses render without floating-point artifacts", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "layout",
    code: "size-mismatch",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "sameWidth",
    expected: { tolerancePx: 0.1 },
    actual: {
      subjectWidthPx: 99.7,
      referenceWidthPx: 100,
      widthDifferencePx: 0.3,
    },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  }).message;

  expect(message).toContain("exceeds tolerance by: 0.2px");
});

/**
 * @doc
 * Issue: Subtracting fractional range bounds from measured geometry can expose
 * JavaScript floating-point artifacts in the rendered violation amount.
 * Why it matters: Range diagnostics should remain readable and actionable for
 * ordinary fractional CSS-pixel constraints.
 */
test("fractional range violations render without floating-point artifacts", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "layout",
    code: "gap-out-of-range",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "leftOf",
    expected: { gap: { maxPx: 0.6 }, tolerancePx: 0 },
    actual: { signedGapPx: 0.7, boundaryCrossingPx: 0 },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  }).message;

  expect(message).toContain("above maximum by: 0.1px");
});

/**
 * @doc
 * Issue: Formatting every pixel value to 15 significant digits changes exact
 * integer measurements before rendering them.
 * Why it matters: The diagnostic can report a different measured geometry than
 * the structured report, sending callers toward the wrong layout value.
 */
test("geometry diagnostics preserve exact integer measurements", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "layout",
    code: "size-mismatch",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "sameWidth",
    expected: { tolerancePx: 0 },
    actual: {
      subjectWidthPx: 1_000_000_000_000_001,
      referenceWidthPx: 1_000_000_000_000_003,
      widthDifferencePx: 2,
    },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  }).message;

  expect(message).toContain("subject width: 1000000000000001px");
  expect(message).toContain("reference width: 1000000000000003px");
});

/**
 * @doc
 * Issue: Formatting every pixel value to 15 significant digits rounds raw
 * fractional measurements even when they contain no arithmetic artifact.
 * Why it matters: Diagnostics should preserve caller-supplied measurements and
 * normalize only artifacts introduced while calculating violation amounts.
 */
test("geometry diagnostics preserve raw fractional measurements", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "layout",
    code: "size-mismatch",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "sameWidth",
    expected: { tolerancePx: 0 },
    actual: {
      subjectWidthPx: 0.1234567890123456,
      referenceWidthPx: 1,
      widthDifferencePx: 0.8765432109876544,
    },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  }).message;

  expect(message).toContain("subject width: 0.1234567890123456px");
});

/**
 * @doc
 * Issue: Formatting calculated violation amounts to 15 significant digits
 * changes exact integer results.
 * Why it matters: A diagnostic can disagree with its measured difference even
 * when subtracting the tolerance introduces no floating-point artifact.
 */
test("geometry diagnostics preserve exact calculated violation amounts", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const exactDifference = Number.MAX_SAFE_INTEGER;
  const finding = {
    category: "layout",
    code: "size-mismatch",
    ruleIndex: 0,
    message: "legacy",
    subject: "a",
    reference: "b",
    relationship: "sameWidth",
    expected: { tolerancePx: 0 },
    actual: {
      subjectWidthPx: exactDifference,
      referenceWidthPx: 0,
      widthDifferencePx: exactDifference,
    },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [finding],
  }).message;

  expect(message).toContain(
    "exceeds tolerance by: 9007199254740991px",
  );
});
