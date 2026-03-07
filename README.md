# beads-from-plan

Claude Code skill that converts markdown implementation plans into structured [beads](https://github.com/steveyegge/beads) tasks with dependency tracking, coverage guarantees, and quality gates.

## The Problem

Large implementation plans (2000+ lines) get lost between sessions. Tasks are forgotten, dependencies are missed, and there's no way to verify that the entire plan has been addressed.

## The Solution

```
Markdown Plan (2000+ lines)
        |
   AI Analysis (Claude Code skill)
        |
   JSON Task Plan (schema-validated)
        |
   bd-from-plan script
        |
   Beads epics + tasks + dependencies
```

The AI reads your plan, maps every section to a task, and produces a JSON plan. The script validates coverage (rejects if any section is unmapped), detects circular dependencies, and creates beads in topological order.

## Key Features

- **100% Coverage Guarantee** — Every plan section must map to a task or be explicitly marked as context-only
- **Dependency Tracking** — Cross-epic and intra-epic dependencies with cycle detection
- **Atomicity Enforcement** — Warns when tasks exceed 120 minutes, span too many sections, or have overly broad scope
- **Quality Gates** — Per-task lint/test/type-check requirements
- **Dry Run** — Preview everything before creating
- **Idempotent** — Re-running skips existing issues

## Installation

```bash
# As a Claude Code plugin
/plugin marketplace add https://github.com/deligoez/beads-from-plan.git
/plugin install beads-from-plan
```

### Requirements

- [beads CLI](https://github.com/steveyegge/beads) (`bd`)
- [jq](https://jqlang.github.io/jq/)

## Usage

### With Claude Code (recommended)

Tell Claude: "Create beads tasks from docs/plans/my-plan.md"

Claude will:
1. Read the entire plan
2. Map sections to epics and tasks
3. Identify dependencies
4. Verify 100% coverage
5. Generate and execute the JSON plan

### Manual Script Usage

```bash
# Dry run (preview)
bd-from-plan --dry-run plan.json

# Create tasks
bd-from-plan plan.json

# From stdin
cat plan.json | bd-from-plan --stdin
```

## JSON Plan Schema

See [schemas/task-plan.schema.json](skills/beads-from-plan/schemas/task-plan.schema.json) for the full schema.

```json
{
  "version": 1,
  "source": "docs/plans/feature.md",
  "prefix": "feat",
  "epics": [
    {
      "id": "auth",
      "title": "Authentication",
      "source_sections": ["## 1. Authentication"],
      "tasks": [
        {
          "id": "user-model",
          "title": "Create User model",
          "depends_on": [],
          "source_sections": ["### 1.1 User Model"],
          "quality_gate": {"lint": true, "test": true},
          "commit_strategy": "agentic-commits"
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 8,
    "mapped_sections": 6,
    "unmapped": [],
    "context_only": ["# Title", "## Overview"]
  }
}
```

## Testing

```bash
# Run all tests (requires bats-core)
bats tests/

# Run specific test file
bats tests/bd-from-plan-validation.bats
bats tests/bd-from-plan-dependencies.bats
bats tests/bd-from-plan-dry-run.bats
bats tests/bd-from-plan-atomicity.bats
bats tests/bd-from-plan-execution.bats
bats tests/bd-from-plan-input.bats
```

## Related

- [agentic-commits](https://github.com/deligoez/agentic-commits) — Atomic commit format for AI agents (referenced as commit strategy)
- [beads](https://github.com/steveyegge/beads) — Git-backed issue tracker for AI agents

## License

MIT
