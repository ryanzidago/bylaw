import { test } from "bun:test";

test("width produces a unary rule without a reference target", () => {});

test("height produces a unary rule without a reference target", () => {});

test("inViewport produces a unary rule without a reference target", () => {});

test("unary rules resolve and measure only their target", () => {});

test("a unary rule with a missing target is skipped with a missing-element finding", () => {});

test("a unary rule with a duplicated target is skipped with a duplicate-element finding", () => {});

test("a unary rule with a hidden target is skipped with a hidden-element finding", () => {});

test("a unary rule with a zero-width target is skipped with a zero-size-element finding", () => {});

test("a unary rule with a zero-height target is skipped with a zero-size-element finding", () => {});

test("a width finding reports the actual width and expected pixel range", () => {});

test("a height finding reports the actual height and expected pixel range", () => {});

test("an inViewport finding reports the actual target and viewport edges", () => {});

test("unary findings identify the subject without a reference target", () => {});

test("several failing unary rules produce distinct findings and accurate rule counts", () => {});

test("a width assertion error includes the actual width and expected pixel range", () => {});

test("a height assertion error includes the actual height and expected pixel range", () => {});

test("an inViewport assertion error includes the actual target and viewport edges", () => {});

test("an inViewport assertion error includes the expected viewport constraint", () => {});

test("the README documents unary geometry rules and when to prefer relative rules", () => {});
