import { test } from "bun:test";

test("the package root exports the supported collection target declaration", () => {});

test("the package root exports every collection geometry rule helper", () => {});

test("the public API distinguishes collection targets from singular targets", () => {});

test("singular and collection target declarations are not interchangeable at compile time", () => {});

test("collection target intent is explicit in the public rule representation", () => {});

test("public collection rule helpers return rules accepted by checkLayout", () => {});

test("caller-constructed collection rules remain valid after a JSON round trip", () => {});

test("collection rules and findings expose supported public types", () => {});

test("collection rule helpers do not mutate supplied targets or options", () => {});

test("an ESM TypeScript consumer can use collection rules from the packed package", () => {});

test("published declarations preserve the distinction between singular and collection targets", () => {});

test("a packed Playwright consumer can evaluate collection rules over repeated elements", () => {});
