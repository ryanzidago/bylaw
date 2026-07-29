import { test } from "bun:test";

test("a public helper rejects an empty collection target name", () => {});

test("a public helper rejects a runtime-invalid collection target declaration", () => {});

test("a caller-constructed collection rule reports a missing collection operand", () => {});

test("a containment collection rule reports a missing singular container operand", () => {});

test("collection containment rejects a negative tolerance", () => {});

test("collection equal-width rejects a negative tolerance", () => {});

test("collection tolerances reject non-finite values", () => {});

test("collection vertical ordering rejects an empty gap range", () => {});

test("collection vertical ordering rejects a minimum greater than its maximum", () => {});

test("collection vertical ordering rejects negative gap bounds", () => {});

test("collection vertical ordering rejects non-finite gap bounds", () => {});

test("collection rules report unknown fields as invalid", () => {});

test("collection rule helpers reject unsupported option fields", () => {});

test("an invalid collection rule does not resolve targets or evaluate geometry", () => {});
