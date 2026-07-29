import { test } from "bun:test";

test("height accepts a target whose height equals the inclusive minimum", () => {});

test("height accepts a target whose height equals the inclusive maximum", () => {});

test("height accepts a target whose height falls between the minimum and maximum", () => {});

test("height rejects a target whose height falls below the minimum", () => {});

test("height rejects a target whose height exceeds the maximum", () => {});
