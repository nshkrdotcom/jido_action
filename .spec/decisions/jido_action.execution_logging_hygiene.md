---
id: jido_action.execution_logging_hygiene
status: accepted
date: 2026-04-02
affects:
  - jido_action.action
  - jido_action.exec
  - jido_action.package
  - jido_action.tools
---

# Centralize execution logging hygiene

## Context

Execution, action utility, and built-in tool code all emit runtime logs, but the branch
work showed the behavior had drifted in three ways:

- log calls mixed direct `Logger` usage with package helpers
- inspected runtime values could be eager or overly noisy in failure and telemetry paths
- routine execution traces were too chatty unless callers explicitly wanted debug output

Those concerns now span the shared action utilities, execution engine, package-level
execution surface, and built-in tools, so the logging rule needs one durable home instead
of branch-local rationale.

## Decision

The package will treat runtime logging hygiene as a cross-cutting policy:

- package-internal action, execution, and tool helpers should route logging through
  `Jido.Action.Log` when they need shared level comparison, deferred message evaluation,
  or bounded inspection
- execution telemetry should sanitize inspected values before logging them
- routine execution start and success traces should require explicit debug-level opt-in
  through `:log_level`, while invalid configuration and failure paths keep warning or
  error visibility
- built-in tool runtimes that spawn supervised work should clean up timeout and mailbox
  residue so logging and supervision stay aligned with execution-policy expectations

## Consequences

- Current truth for action utilities, execution, package-level execution defaults, and
  built-in tools should stay aligned when logging behavior changes.
- Future logging changes that only affect one local message do not need an ADR update.
- Future changes that alter the shared logging policy or move ownership again should
  update this ADR alongside the affected subject specs.
