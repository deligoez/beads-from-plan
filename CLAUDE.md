# CLAUDE.md

## Project

Claude Code skill that converts markdown plans into beads tasks.

## Structure

```
.claude-plugin/          Plugin metadata
skills/beads-from-plan/  Skill definition
  SKILL.md               Main skill (AI reads this)
  schemas/               JSON schema for task plans
  scripts/               bd-from-plan bash script
  reference/             Plan format and examples
tests/                   BATS test suite
```

## Development

- Tests: `bats tests/`
- Dependencies: `jq`, `bd` (beads CLI), `bats-core`
- Script: `skills/beads-from-plan/scripts/bd-from-plan`

## Testing

All tests use BATS with isolated git+beads environments per test.
Test files follow the pattern `tests/bd-from-plan-{area}.bats`.
