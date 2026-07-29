import { test } from "bun:test";

test("a passing report still produces no assertion error or diagnostic output", () => {
});

test("each failure renders the rule before measurements, constraints, and violation amounts", () => {
});

test("multiple failures preserve the order of findings in the original report", () => {
});

test("multiple failures use stable separators that keep each diagnostic readable", () => {
});

test("a realistic broken page renders actionable alignment, gap, overlap, containment, and size diagnostics together", () => {
});

test("constructing diagnostic output does not mutate the supplied report", () => {
});

test("the assertion error retains the exact original report object", () => {
});

test("structured expected data remains available after diagnostic rendering", () => {
});

test("structured actual data retains existing derived measurements after diagnostic rendering", () => {
});

test("structured actual data includes the raw subject and reference measurements used by diagnostics", () => {
});
