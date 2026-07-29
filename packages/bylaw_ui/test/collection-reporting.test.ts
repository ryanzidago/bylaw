import { test } from "bun:test";

test("an individual collection failure identifies its collection index", () => {});

test("collection indexes are zero-based and follow adapter element order", () => {});

test("an individual collection failure identifies its target element", () => {});

test("a pairwise collection failure identifies both collection indexes", () => {});

test("a pairwise collection failure identifies both target elements", () => {});

test("an empty collection finding reports expected and actual member counts", () => {});

test("an individual collection finding exposes a stable category code and relationship", () => {});

test("a containment finding includes member and container rectangles with directional overflow", () => {});

test("an equal-width finding includes compared members and measured width difference", () => {});

test("a vertical-ordering finding includes adjacent member rectangles and signed gap", () => {});

test("a pairwise non-overlap finding includes both member rectangles and overlap depths", () => {});

test("collection reports remain JSON-serializable without adapter browser or DOM objects", () => {});

test("collection findings follow rule order", () => {});

test("individual collection findings follow collection order", () => {});

test("pairwise collection findings follow deterministic pair order", () => {});

test("pairwise collection findings use ascending lexicographic index order", () => {});

test("repeated evaluation produces findings in the same order", () => {});

test("a failed collection rule contributes one failed rule to the report summary", () => {});

test("a passing collection rule contributes one passed rule to the report summary", () => {});

test("an unresolved collection rule contributes one skipped rule to the report summary", () => {});

test("several findings from one collection rule count that rule only once", () => {});

test("mixed collection rules produce accurate passed failed and skipped counts", () => {});
