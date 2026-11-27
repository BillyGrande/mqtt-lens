# REVIEW.md

Rules for the reviewer agents. Source: `specs/process/guardrails.md`.

- Do three passes. Tag each finding: **Bugs**, **Security** (threat model T1-T20), or
  **Compliance** (matches the spec, the task and the DESIGN principles).
- Severity: "Reserve Important for findings that would break behavior, leak data or breach a
  policy." Style and naming are nits.
- "Report at most five nits per review; summarize the rest as a count."
- Exclude what CI already enforces (format, Credo, Sobelow rules) and generated files.
- Findings do not approve or block alone. The owner decides at H3.
