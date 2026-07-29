import { test } from "bun:test";

test("continues resolving exact data-testid values without a registry", () => {});

test("uses a registered target before data-testid fallback for the same name", () => {});

test("does not fall back to data-testid when a registered target matches no elements", () => {});

test("does not fall back to data-testid when a registered target matches multiple elements", () => {});

test("falls back to exact data-testid addressing for an unregistered name", () => {});

test("supports registered and fallback targets in the same check", () => {});
