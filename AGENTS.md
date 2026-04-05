# Workflow

1. Define or update the relevant interfaces, subject mappings, types, and test cases first.
2. Write failing tests before implementation for new behavior.
3. Implement only after the tests and type boundaries make the change explicit.
4. Run the targeted validations for the touched area before asking for integration.

# Rules

- Prefer explicit over clever.
- Flag and remove repetition aggressively.
- Add tests for edge cases rather than relying on manual verification alone.
- Keep abstractions shallow unless duplication or coupling clearly justifies a new layer.
- Type safety matters. Don't use `any` or `try!`, `unwrap!`, etc. without a clear plan for handling errors or edge cases.
- Code coverage matters, and we enforce 100% coverage in CI. Before commit, measure coverage, harden, then verify, and if only coverage has been 100%, then do git commit.
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
