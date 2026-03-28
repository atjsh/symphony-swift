# Agent Workflow

This repository is being re-architected toward the single-package
layout described in `SPEC.md`. Until the code fully catches up, treat the rules
below as the required target contract for migration work.

## Required order of work

1. Define or update the relevant interfaces, subject mappings, types, and test cases first.
2. Write failing tests before implementation for new behavior.
3. Implement only after the tests and type boundaries make the change explicit.
4. Run the targeted validations for the touched area before asking for integration.

## Swift CLI policy

- Use quiet mode for all commands by default.

## Commit policy

- Keep commit topics small and green.

## Implementation defaults

- Prefer explicit over clever.
- Flag and remove repetition aggressively.
- Add tests for edge cases rather than relying on manual verification alone.
- Keep abstractions shallow unless duplication or coupling clearly justifies a new layer.
