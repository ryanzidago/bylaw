import { test } from "bun:test";

test("reports a missing unary target as invalid", () => {});

test("reports an empty unary target as invalid", () => {});

test("reports a non-string unary target as invalid at runtime", () => {});

test("reports a reference field on a unary rule as unknown", () => {});

test("reports a missing width range as invalid", () => {});

test("reports a missing height range as invalid", () => {});

test("reports an empty width range as invalid", () => {});

test("reports an empty height range as invalid", () => {});

test("reports a negative unary range bound as invalid", () => {});

test("reports a NaN unary range bound as invalid", () => {});

test("reports an infinite unary range bound as invalid", () => {});

test("reports a nonnumeric unary range bound as invalid at runtime", () => {});

test("reports a unary range minimum greater than its maximum as invalid", () => {});

test("reports a non-object unary range as invalid at runtime", () => {});

test("reports unknown unary rule fields as invalid", () => {});

test("reports every invalid field on a unary rule rather than stopping at the first", () => {});

test("public unary helpers throw synchronously for invalid runtime ranges", () => {});

test("public unary helpers throw synchronously for invalid runtime targets", () => {});
