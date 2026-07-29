import { test } from "bun:test";

test("passes when collection members are vertically ordered", () => {});

test("passes when every adjacent gap is inside the allowed range", () => {});

test("passes when adjacent gaps equal the allowed range boundaries", () => {});

test("passes with a minimum-only adjacent gap range", () => {});

test("passes with a maximum-only adjacent gap range", () => {});

test("passes when adjacent members touch and zero gap is allowed", () => {});

test("passes vertical ordering when a collection contains one member", () => {});

test("evaluates vertical ordering between adjacent collection members only", () => {});

test("uses collection order instead of sorting members by coordinates", () => {});

test("fails when two adjacent collection members are out of vertical order", () => {});

test("fails when an adjacent gap is smaller than the allowed minimum", () => {});

test("fails when an adjacent gap is larger than the allowed maximum", () => {});

test("distinguishes an out-of-order pair from an ordered pair with an invalid gap", () => {});

test("reports every adjacent pair whose vertical ordering fails", () => {});

test("reports every adjacent pair whose gap is outside the allowed range", () => {});

test("preserves fractional gaps between collection members", () => {});
