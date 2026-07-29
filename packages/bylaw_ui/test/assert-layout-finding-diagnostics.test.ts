import { test } from "bun:test";

test("invalid-rule diagnostics identify the rule position, field path, and reason", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const report = {
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
    findings: [
      {
        category: "invalid-rule",
        code: "unknown-field",
        ruleIndex: 2,
        message: "legacy",
        fieldPath: "rules[2].surprise",
        reason: "is not supported",
      },
    ],
  };
  const message = new LayoutAssertionError(report).message;
  expect(message).toContain("rule 2");
  expect(message).toContain("field: rules[2].surprise");
  expect(message).toContain("reason: is not supported");
});

test("missing-element diagnostics identify the operand and report expected and actual match counts", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "element-resolution",
    code: "missing-element",
    ruleIndex: 0,
    message: "legacy",
    subject: "avatar",
    reference: "card",
    operand: "subject",
    testId: "avatar",
    expected: { matchCount: 1 },
    actual: { matchCount: 0 },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 0, skipped: 1 },
    findings: [finding],
  }).message;
  expect(message).toContain("missing element");
  expect(message).toContain('subject: "avatar"');
  expect(message).toContain("expected matches: 1");
  expect(message).toContain("actual matches: 0");
});

test("duplicate-element diagnostics identify the operand and report expected and actual match counts", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "element-resolution",
    code: "duplicate-element",
    ruleIndex: 0,
    message: "legacy",
    subject: "avatar",
    reference: "card",
    operand: "reference",
    testId: "card",
    expected: { matchCount: 1 },
    actual: { matchCount: 3 },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 0, skipped: 1 },
    findings: [finding],
  }).message;
  expect(message).toContain("duplicate element");
  expect(message).toContain('reference: "card"');
  expect(message).toContain("expected matches: 1");
  expect(message).toContain("actual matches: 3");
});

test("hidden-element diagnostics identify the operand, test ID, visibility, width, and height in CSS pixels", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "element-visibility",
    code: "hidden-element",
    ruleIndex: 0,
    message: "legacy",
    subject: "avatar",
    reference: "card",
    operand: "subject",
    testId: "avatar",
    expected: { visible: true, positiveSize: true },
    actual: { hidden: true, width: 96, height: 48 },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 0, skipped: 1 },
    findings: [finding],
  }).message;
  for (const text of [
    "hidden element",
    'subject: "avatar"',
    'test ID: "avatar"',
    "visible: false",
    "width: 96px",
    "height: 48px",
  ])
    expect(message).toContain(text);
});

test("zero-size-element diagnostics identify the operand, test ID, visibility, width, and height in CSS pixels", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const finding = {
    category: "element-visibility",
    code: "zero-size-element",
    ruleIndex: 0,
    message: "legacy",
    subject: "avatar",
    reference: "card",
    operand: "subject",
    testId: "avatar",
    expected: { visible: true, positiveSize: true },
    actual: { hidden: false, width: 0, height: 48 },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 0, skipped: 1 },
    findings: [finding],
  }).message;
  for (const text of [
    "zero-size element",
    'subject: "avatar"',
    'test ID: "avatar"',
    "visible: true",
    "width: 0px",
    "height: 48px",
  ])
    expect(message).toContain(text);
});

test("element diagnostics identify both subject and reference when both operands are unavailable", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const common = {
    category: "element-resolution",
    code: "missing-element",
    ruleIndex: 0,
    message: "legacy",
    subject: "avatar",
    reference: "card",
    expected: { matchCount: 1 },
    actual: { matchCount: 0 },
  };
  const findings = [
    { ...common, operand: "subject", testId: "avatar" },
    { ...common, operand: "reference", testId: "card" },
  ];
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 0, skipped: 1 },
    findings,
  }).message;
  expect(message).toContain('subject: "avatar"');
  expect(message).toContain('reference: "card"');
});

test("diagnostics safely quote test IDs containing whitespace, quotes, and line breaks", () => {
  const { expect } = require("bun:test");
  const { LayoutAssertionError } = require("bylaw-ui");
  const testId = 'avatar card "primary"\nmobile';
  const finding = {
    category: "element-resolution",
    code: "missing-element",
    ruleIndex: 0,
    message: "legacy",
    subject: testId,
    reference: "card",
    operand: "subject",
    testId,
    expected: { matchCount: 1 },
    actual: { matchCount: 0 },
  };
  const message = new LayoutAssertionError({
    passed: false,
    rules: { total: 1, passed: 0, failed: 0, skipped: 1 },
    findings: [finding],
  }).message;
  expect(message).toContain(JSON.stringify(testId));
  expect(message).not.toContain(testId);
});
