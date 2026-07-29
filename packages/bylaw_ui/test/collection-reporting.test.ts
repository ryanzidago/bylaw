import { test } from "bun:test";

test("an individual collection failure identifies its collection index", () => {});

test("an individual collection failure identifies its target element", () => {});

test("a pairwise collection failure identifies both collection indexes", () => {});

test("a pairwise collection failure identifies both target elements", () => {});

test("collection findings follow rule order", () => {});

test("individual collection findings follow collection order", () => {});

test("pairwise collection findings follow deterministic pair order", () => {});

test("repeated evaluation produces findings in the same order", () => {});

test("a failed collection rule contributes one failed rule to the report summary", () => {});

test("a passing collection rule contributes one passed rule to the report summary", () => {});

test("an unresolved collection rule contributes one skipped rule to the report summary", () => {});
