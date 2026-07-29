import { test } from "bun:test";

test("height accepts a target whose height equals the inclusive minimum", () => {});

test("height accepts a target whose height equals the inclusive maximum", () => {});

test("height accepts a target whose height falls between the minimum and maximum", () => {});

test("height rejects a target whose height falls below the minimum", () => {});

test("height rejects a target whose height exceeds the maximum", () => {});

test("height accepts a target whose height equals an exact fixed range", () => {});

test("height accepts a target above a minimum-only range", () => {});

test("height rejects a target below a minimum-only range", () => {});

test("height accepts a target below a maximum-only range", () => {});

test("height rejects a target above a maximum-only range", () => {});

test("height preserves fractional CSS-pixel measurements and bounds", () => {});

test("height ignores the target width and viewport-relative position", () => {});
