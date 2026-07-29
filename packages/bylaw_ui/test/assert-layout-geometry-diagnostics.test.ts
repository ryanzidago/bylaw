import { test } from "bun:test";

test("alignment diagnostics identify the rule, subject, reference, and aligned edge", () => {
});

test("alignment diagnostics report both measured coordinates in CSS pixels", () => {
});

test("alignment diagnostics report the absolute difference, allowed tolerance, and excess", () => {
});

test("ordering diagnostics identify the directional relationship and both operands", () => {
});

test("ordering violation diagnostics report the signed gap and boundary crossing in CSS pixels", () => {
});

test("ordering violation diagnostics report the allowed tolerance and excess boundary crossing", () => {
});

test("bounded gap diagnostics report the measured gap and both allowed endpoints", () => {
});

test("minimum-only gap diagnostics report how far the measurement is below the minimum", () => {
});

test("maximum-only gap diagnostics report how far the measurement exceeds the maximum", () => {
});

test("missing overlap diagnostics report horizontal and vertical overlap depths including zeroes", () => {
});

test("constrained overlap diagnostics report measured depths and each configured range", () => {
});

test("constrained overlap diagnostics report the distance from every violated range boundary", () => {
});

test("notOverlap diagnostics report positive overlap depths on both axes", () => {
});

test("containment diagnostics report overflow on all four sides including zeroes", () => {
});

test("containment diagnostics report intersection depths when positive intersection is missing", () => {
});

test("containment diagnostics report the allowed tolerance, maximum overflow, and excess", () => {
});

test("sameWidth diagnostics report subject width, reference width, and absolute difference", () => {
});

test("sameHeight diagnostics report subject height, reference height, and absolute difference", () => {
});

test("sameSize diagnostics report subject and reference measurements for both dimensions", () => {
});

test("size diagnostics report the allowed tolerance and excess for every failing dimension", () => {
});

test("geometry diagnostics preserve fractional CSS-pixel measurements without unnecessary trailing zeroes", () => {
});

test("geometry diagnostics render negative zero as zero pixels", () => {
});
