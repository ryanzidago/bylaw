import type { LayoutReport } from "./types.js";

export class LayoutAssertionError extends Error {
  readonly report: LayoutReport;

  constructor(report: LayoutReport) {
    const details = report.findings
      .map((finding) => {
        const operands =
          "subject" in finding
            ? ` [${JSON.stringify(finding.subject)}, ${JSON.stringify(finding.reference)}]`
            : "";
        return `- rule ${finding.ruleIndex}${operands}: ${finding.message}`;
      })
      .join("\n");

    super(
      `Layout assertion failed for ${report.rules.failed + report.rules.skipped} rule(s)${
        details.length > 0 ? `:\n${details}` : ""
      }`,
    );
    this.name = "LayoutAssertionError";
    this.report = report;
  }
}

export function assertLayout(report: LayoutReport): void {
  if (
    typeof report !== "object" ||
    report === null ||
    typeof report.passed !== "boolean"
  ) {
    throw new TypeError("assertLayout expects a LayoutReport");
  }

  if (!report.passed) {
    throw new LayoutAssertionError(report);
  }
}
