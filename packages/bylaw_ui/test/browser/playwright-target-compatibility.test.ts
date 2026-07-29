import { test } from "bun:test";

test("continues resolving exact data-testid values without a registry", () => {});

test("uses a registered target before data-testid fallback for the same name", () => {});

test("falls back to exact data-testid addressing for an unregistered name", () => {});

test("supports registered and fallback targets in the same check", () => {});
