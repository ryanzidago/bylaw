import { test } from "bun:test";

test("a custom adapter returns normalized viewport-relative rectangle coordinates", () => {});

test("a custom adapter can report a missing singular target", () => {});

test("a custom adapter can report an ambiguous singular target", () => {});

test("a custom adapter can return every member of a resolved collection", () => {});

test("a valid adapter result correlates one-to-one with every requested target", () => {});

test("adapter failures preserve the original error identity", () => {});

test("rejects a snapshot without viewport data before rule evaluation", () => {});

test("rejects nonpositive viewport dimensions before rule evaluation", () => {});

test("rejects a rectangle with a nonfinite coordinate before rule evaluation", () => {});

test("rejects a rectangle with negative dimensions before rule evaluation", () => {});

test("rejects a rectangle with a nonfinite derived edge before rule evaluation", () => {});

test("rejects a resolved singular target without element state before rule evaluation", () => {});

test("rejects an unresolved singular target with element state before rule evaluation", () => {});

test("rejects a collection containing malformed element state before rule evaluation", () => {});

test("rejects adapter results that omit a requested target before rule evaluation", () => {});

test("rejects adapter results that duplicate a requested target before rule evaluation", () => {});

test("rejects adapter results for an unrequested target before rule evaluation", () => {});

test("malformed adapter results fail with an actionable measurement path", () => {});

test("malformed adapter results do not produce layout findings", () => {});
