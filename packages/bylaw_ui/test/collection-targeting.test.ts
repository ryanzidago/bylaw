import { test } from "bun:test";

test("a collection target resolves every matching element", () => {});

test("a collection target preserves adapter element order", () => {});

test("a collection target accepts exactly one matching element", () => {});

test("an empty collection reports a resolution finding", () => {});

test("an empty collection skips geometry evaluation", () => {});

test("a hidden collection member reports its collection index and target element", () => {});

test("a zero-size collection member reports its collection index and target element", () => {});

test("reports every unavailable collection member in collection order", () => {});

test("a collection rule skips geometry evaluation when any member is unavailable", () => {});

test("an unreferenced collection target is not resolved", () => {});

test("a collection target reused by several rules is measured once per check", () => {});

test("a singular target continues to reject multiple matching elements", () => {});

test("a singular target never selects the first of multiple matching elements", () => {});

test("a rule can use a collection target and a singular target as distinct operands", () => {});
