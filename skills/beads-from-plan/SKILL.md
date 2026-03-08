---
name: beads-from-plan
description: |
  Convert markdown implementation plans into beads tasks. Use when the user says "create tasks from plan", "plan to beads", "bd from plan", "break down plan", "create beads from markdown", or has a large markdown plan that needs to be decomposed into trackable tasks.
allowed-tools:
  - Bash(bd:*)
  - Bash(jq:*)
  - Bash(cat:*)
  - Bash(rm:*)
  - Read
  - Write
---

# Beads From Plan

Convert markdown implementation plans into structured beads tasks with full coverage guarantees.

| Mode | Triggers | Action |
|------|----------|--------|
| DECOMPOSE | "create tasks from plan", "plan to beads", "break down plan" | Analyze markdown -> JSON task plan -> create beads |
| VERIFY | "check plan coverage", "verify tasks" | Validate existing plan JSON against source markdown |

**Purpose:** Ensure every section of a plan becomes a trackable, dependency-ordered beads task with quality gates.

Execute autonomously. Never skip sections.

## Script Path

The `bd-from-plan` script is at `scripts/bd-from-plan` relative to this skill's base directory.
Use the base directory provided at skill activation to construct the full path:

```bash
# The base directory is shown as "Base directory for this skill: <path>" when the skill loads.
# Always use mktemp to avoid path collisions between concurrent runs.
# macOS mktemp doesn't support suffixes, so create then rename.
_tmp=$(mktemp /tmp/task-plan-XXXXXXXX)
PLAN_FILE="${_tmp}.json"
mv "$_tmp" "$PLAN_FILE"
<base_directory>/scripts/bd-from-plan "$PLAN_FILE"
```

---

# The Process

## Overview

```
Markdown Plan (2000+ lines)
        |
        v
   AI Analysis
   - Parse all headings (##, ###, ####)
   - Identify epics (top-level sections)
   - Identify tasks (sub-sections)
   - Map dependencies between tasks
   - Verify 100% section coverage
        |
        v
  JSON Task Plan (mktemp + rename to .json)
   - Structured epics and tasks
   - Dependency graph
   - Quality gates per task
   - Coverage report
        |
        v
  bd-from-plan script
   - Validates JSON schema
   - Rejects if unmapped sections exist
   - Topological sort by dependencies
   - Creates epics via bd create --type epic
   - Creates tasks via bd create --type task --parent
   - Adds dependencies via bd dep add
   - Reports summary
```

---

# Critical Rules

## 100% Coverage Guarantee (STRICT)

**Every content section in the markdown MUST map to at least one task.**

This is the most important rule. A plan section that doesn't become a task will be forgotten.

| Section Type | Action |
|-------------|--------|
| Implementation section | Map to a task |
| Overview/Introduction | Mark as `context_only` in coverage |
| Table of Contents | Mark as `context_only` |
| References/Links | Mark as `context_only` |
| Everything else | MUST become a task |

The script **rejects** plans with unmapped sections. Fix coverage before proceeding.

## Dependency Accuracy (STRICT)

**Dependencies must reflect real implementation order, not document order.**

- A task that uses a model depends on the task that creates it
- A task that writes tests depends on the task that creates the code
- A task that configures something depends on the task that installs it
- Document order (section 1 before section 2) is NOT a dependency

### Detecting Dependencies

Ask for each task:
1. "What must exist before I can start this?"
2. "What would break if I did this first?"

If the answer to both is "nothing" -> no dependencies.

### Circular Dependencies

The script detects and rejects circular dependencies. If you find a cycle:
- Break it by splitting one task into two
- The setup part has no dependency, the integration part depends on the other

## Atomic Task Decomposition (STRICT)

**Each task MUST be completable in a single focused session AND expressible as one commit.**

This is the second most important rule (after 100% coverage). Over-broad tasks cause:
- **Agent confusion** — too many concerns exhaust the context window mid-task
- **Poor commits** — impossible to create atomic commits from broad tasks
- **Tracking failure** — "50% done" tasks are invisible in beads
- **Review difficulty** — large diffs are harder to review than small, focused ones

### Rule 1: Single Commit Test

**If you can't describe the task's output in ONE commit message, split it.**

| Task Title | Commit Message | Result |
|-----------|---------------|--------|
| "Create User model" | `feat(User): create model with migration` | PASS |
| "Create config, migration, model, service" | Can't fit in one message | FAIL — split into 4 |

### Rule 2: One File Rule

**Each new file creation = separate task.**

If a task creates 3 new files, it should be 3 tasks.

| Files Created | Tasks | Why |
|--------------|-------|-----|
| `Model.php` | 1 task | Single file |
| `Model.php` + `ModelTest.php` | 1 task | Code + its test = one concern |
| `Model.php` + `Migration.php` + `Factory.php` | 3 tasks | Different concerns |
| `Service.php` + `ServiceInterface.php` | 1 task | Compile-time dependency |

**Exception:** A source file + its direct test file = one task (they share one concern).

### Rule 3: Maximum 45 Minutes

**Implementation tasks MUST NOT exceed 45 minutes.**

| Estimate | Action |
|----------|--------|
| ≤ 15 min | Consider merging with a directly related task |
| 15–45 min | Perfect granularity |
| 46–90 min | MUST split — too broad for one focused session |
| > 90 min | MUST split aggressively — this is multiple tasks disguised as one |

### Rule 4: Verb-Object Test

**A good task title has ONE verb and ONE object.**

| Title | Analysis | Result |
|-------|----------|--------|
| "Create MachineStateLock model" | create + model | PASS |
| "Add config and create migration" | add + config, create + migration | FAIL — 2 tasks |
| "Implement service with exception handling" | implement + service (exception is part of it) | PASS |

**Red flag words:** "and", "+", commas separating nouns. These usually indicate multiple concerns jammed into one task.

### Rule 5: Count the Files

**If a task implies creating or modifying >2 files, it's too broad.**

Count the files mentioned or implied in the description. Source + test = 1 logical file.

### Rule 6: Acceptance Criteria Count

**If acceptance criteria lists >3 distinct checkpoints, the task combines multiple concerns.**

| Acceptance | Criteria | Result |
|-----------|----------|--------|
| "Model exists. Migration runs." | 2 | PASS |
| "Manager acquires. Handle releases. Stale healed. Migration publishable." | 4 | FAIL — split |

### Rule 7: Noun Count in Title

**Count the distinct nouns (objects being created/modified) in the title. More than 2 = split.**

| Title | Nouns | Result |
|-------|-------|--------|
| "Create MachineLockManager service" | 1 (MachineLockManager) | PASS |
| "Lock infrastructure: config, migration, model, service, exception" | 5 | FAIL — 5 tasks |

### Recursive Decomposition Algorithm

After initial task identification, the agent MUST run this loop:

```
FOR each task:
  1. Single Commit Test → "Can I write ONE commit message for this?"
  2. Verb-Object Test → "Does the title have ONE verb + ONE object?"
  3. Noun Count → "How many distinct things am I creating?"
  4. File Count → "How many files will this create/modify?"
  5. Time Check → "Is this ≤ 45 minutes?"
  6. Acceptance Count → "Are there ≤ 3 acceptance criteria?"

  IF any check fails:
    → Split the task along the failing dimension
    → Re-run ALL checks on each sub-task

  REPEAT until every task passes every check.
```

### Decomposition Example

**BEFORE** (1 broad task, 120 min):

```json
{
  "id": "lock",
  "title": "Lock infrastructure: config, migration, model, service, exception",
  "estimate_minutes": 120,
  "acceptance": "MachineLockManager acquires/blocks/times out. MachineLockHandle releases/extends. Stale locks self-healed. Migration publishable."
}
```

Failures: Single Commit ❌, Verb-Object ❌, Noun Count ❌ (5), File Count ❌ (5+), Time ❌ (120m), Acceptance ❌ (4+)

**AFTER** (5 atomic tasks):

```json
[
  {"id": "config",       "title": "Add parallel_dispatch config section",              "estimate_minutes": 15},
  {"id": "migration",    "title": "Create machine_locks migration",                    "estimate_minutes": 15},
  {"id": "model",        "title": "Create MachineStateLock Eloquent model",            "estimate_minutes": 15},
  {"id": "lock-manager", "title": "Create MachineLockManager service",                 "estimate_minutes": 30},
  {"id": "lock-handle",  "title": "Create MachineLockHandle and timeout exception",    "estimate_minutes": 20}
]
```

Each task: one commit, one verb, one file (or tightly coupled pair), ≤ 30 min.

### Expected Task Counts

Use this as calibration — if your count is significantly below, you're under-decomposing:

| Plan Size | Expected Tasks |
|-----------|---------------|
| 100 lines | 8–15 tasks |
| 500 lines | 25–40 tasks |
| 1000 lines | 45–70 tasks |
| 2000 lines | 80–120 tasks |

## Quality Gates

The quality gate is a **single executable command** that combines all quality checks for the project. The agent discovers available commands from the project (composer.json, package.json, Makefile, CI config) and combines them with `&&`.

Examples:
```
# PHP/Laravel project
composer lint && composer test && composer larastan

# Node.js project
npm run lint && npm run test && npm run typecheck

# Python project
ruff check . && pytest && mypy .

# Documentation-only tasks (no gate)
(leave quality_gate empty)
```

The agent MUST verify the quality gate command runs successfully before including it in the plan.

## Commit Strategy

Reference `agentic-commits` for atomic commit discipline. Each task completion should result in well-structured commits. Set `commit_strategy` per task:

| Strategy | When |
|----------|------|
| `agentic-commits` | Default for all code tasks |
| `conventional` | Simple config changes, docs |
| `manual` | Complex merges, manual intervention needed |

---

# MODE 1: DECOMPOSE

## Step 0: Ask User Preferences (MANDATORY)

**Before reading the plan, ask the user two questions.** Do NOT skip this step.

### Question 1: Quality Gate Command

Ask: "What quality check commands should run after each task?"

**Discovery approach:** First, try to discover existing quality commands from the project:
- Check `composer.json` scripts (e.g., `lint`, `test`, `larastan`, `infection`)
- Check `package.json` scripts (e.g., `lint`, `test`, `typecheck`)
- Check `Makefile` targets
- Check CI config (`.github/workflows/`, `.gitlab-ci.yml`)

Present discovered commands to the user, or ask them to specify:
```
I found these quality commands in your project:
  - composer lint
  - composer test
  - composer larastan

Should I combine all of these as the quality gate, or do you want to customize?
```

The quality gate is a **single executable command** — combine multiple checks with `&&`:
```
composer lint && composer test && composer larastan
```

### Step 0.5: Verify Quality Gate Command (MANDATORY)

**Before generating the JSON plan, RUN the quality gate command** to verify it works:

```bash
# Run the combined command
composer lint && composer test && composer larastan
```

If the command fails:
- Ask the user to fix the issue or adjust the command
- Do NOT proceed with JSON generation until the command succeeds
- This prevents writing a broken command into every task

### Question 2: Commit Strategy

Ask: "How should completed tasks be committed?"

Present options:
```
Commit Strategy options:
  [1] agentic-commits — atomic, one-file-per-commit, structured format (recommended)
  [2] conventional — conventional commit messages (feat:, fix:, etc.)
  [3] manual — no auto-commit, handle manually
```

### Store in JSON

Record the user's choices in the `workflow` field of the JSON plan:

```json
{
  "workflow": {
    "quality_gate": "composer lint && composer test && composer larastan",
    "commit_strategy": "agentic-commits",
    "checklist_note": "- [ ] Run quality gate: composer lint && composer test && composer larastan\n- [ ] Commit using agentic-commits"
  }
}
```

The `checklist_note` is a human-readable summary of the workflow. The script appends it to every task's description as a checklist.

Individual tasks can override the workflow defaults via their own `quality_gate` and `commit_strategy` fields. If not overridden, the workflow defaults apply.

---

## Step 1: Read the Plan

Read the entire markdown file. Do NOT skip sections or skim.

```bash
# Count total lines
wc -l plan.md

# Read the file
# Use the Read tool, not cat
```

## Step 2: Extract Structure

Parse all headings and build a section tree:

```
# Title                          -> context_only
## 1. Authentication             -> epic: auth
### 1.1 User Model               -> task: auth-user-model
### 1.2 Login Flow                -> task: auth-login-flow
#### 1.2.1 JWT Tokens             -> task: auth-jwt-tokens
### 1.3 Password Reset            -> task: auth-password-reset
## 2. Authorization               -> epic: authz
### 2.1 Role System               -> task: authz-roles
...
```

**Rules for section-to-task mapping:**
- `#` (h1) = Plan title -> `context_only`
- `##` (h2) = Epic candidates
- `###` (h3) = Task candidates
- `####` (h4) = Sub-task candidates (merge into parent task or create separate task)

## Step 3: Identify Dependencies

For each task, scan the plan for:
- "requires X", "depends on X", "after X"
- References to entities created in other tasks
- Logical ordering (create before use, define before implement)

Build a dependency list per task.

## Step 4: Build Coverage Map

Create a table mapping EVERY heading to a task or `context_only`:

```
| Section | Mapped To | Status |
|---------|-----------|--------|
| # Plan Title | - | context_only |
| ## Overview | - | context_only |
| ## 1. Auth | epic:auth | mapped |
| ### 1.1 User Model | task:auth-user-model | mapped |
| ### 1.2 Login Flow | task:auth-login-flow | mapped |
| ## Appendix | - | context_only |
```

**If ANY section is unmapped and not context_only -> STOP and fix.**

## Step 5: Generate JSON Plan

Write the JSON plan following the schema at `schemas/task-plan.schema.json`.

```bash
_tmp=$(mktemp /tmp/task-plan-XXXXXXXX)
PLAN_FILE="${_tmp}.json"
mv "$_tmp" "$PLAN_FILE"
cat > "$PLAN_FILE" << 'PLAN_EOF'
{
  "version": 1,
  "source": "docs/plans/feature-x.md",
  "prefix": "feat",
  "workflow": {
    "quality_gate": "composer lint && composer test && composer type",
    "commit_strategy": "agentic-commits",
    "checklist_note": "- [ ] Run quality gate: composer lint && composer test && composer type\n- [ ] Commit using agentic-commits\n- [ ] Close this task when done: bd close <task-id>"
  },
  "epics": [
    {
      "id": "auth",
      "title": "Authentication System",
      "description": "Implement user authentication with JWT tokens and password reset",
      "priority": 1,
      "labels": ["auth", "security"],
      "source_sections": ["## 1. Authentication"],
      "tasks": [
        {
          "id": "user-model",
          "title": "Create User model and migration",
          "description": "Define User model with email, password_hash, timestamps. Create migration with proper indexes.",
          "type": "feature",
          "priority": 1,
          "estimate_minutes": 45,
          "labels": ["model"],
          "depends_on": [],
          "source_sections": ["### 1.1 User Model"],
          "source_lines": "15-42",
          "acceptance": "User model exists with migration. Factory and seeder work. PHPStan passes.",
          "commit_strategy": "agentic-commits"
        },
        {
          "id": "login-flow",
          "title": "Implement login endpoint with JWT",
          "description": "POST /api/login accepts email+password, returns JWT. Validates credentials against User model.",
          "type": "feature",
          "priority": 1,
          "estimate_minutes": 90,
          "depends_on": ["user-model"],
          "source_sections": ["### 1.2 Login Flow", "#### 1.2.1 JWT Tokens"],
          "source_lines": "43-98",
          "acceptance": "Login endpoint returns valid JWT. Invalid credentials return 401. Tests pass.",
          "commit_strategy": "agentic-commits"
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 12,
    "mapped_sections": 10,
    "unmapped": [],
    "context_only": ["# Feature X Plan", "## Overview"]
  }
}
PLAN_EOF
```

## Step 6: Execute Plan

```bash
<base_directory>/scripts/bd-from-plan "$PLAN_FILE"
```

The script will:
1. Validate the JSON
2. Check coverage (fail if unmapped sections)
3. Detect circular dependencies (fail if cycles)
4. Create epics in order
5. Create tasks in topological order
6. Wire up dependencies
7. Print summary with `bd ready` output

## Step 7: Verify

```bash
bd ready --pretty          # See what's ready to work on
bd graph                   # Visualize dependency graph
bd epic status             # Check epic completion status
```

---

# MODE 2: VERIFY

Validate an existing plan JSON against its source markdown.

## Step 1: Load Both Files

```bash
# Read the plan JSON
cat "$PLAN_FILE" | jq .

# Read the source markdown
# Extract the source path from the plan
SOURCE=$(cat "$PLAN_FILE" | jq -r '.source')
```

## Step 2: Extract Markdown Headings

```bash
grep -n '^#' "$SOURCE" | head -50
```

## Step 3: Cross-Reference

For each heading in the markdown:
- Check if it appears in any task's `source_sections`
- Check if it appears in `coverage.context_only`
- If neither -> report as unmapped

## Step 4: Report

```
Coverage Report:
  Total sections: 12
  Mapped to tasks: 10
  Context only: 2
  Unmapped: 0

  Status: PASS
```

---

# ID Naming Convention

IDs follow a hierarchical pattern:

```
prefix-epicId-taskId
```

| Component | Format | Example |
|-----------|--------|---------|
| prefix | lowercase alpha | `feat`, `auth`, `fix` |
| epicId | kebab-case | `auth`, `data-layer`, `ui` |
| taskId | kebab-case | `user-model`, `login-flow` |
| Full ID | prefix-epic-task | `feat-auth-user-model` |

The script combines these automatically:
- Epic ID: `{prefix}-{epicId}` -> `feat-auth`
- Task ID: `{prefix}-{epicId}-{taskId}` -> `feat-auth-user-model`

Keep IDs short but descriptive. Avoid abbreviations that aren't obvious.

---

# Dry Run

Always do a dry run first for large plans:

```bash
<base_directory>/scripts/bd-from-plan --dry-run "$PLAN_FILE"
```

This validates everything and shows what WOULD be created without actually creating anything.

---

# Error Recovery

| Error | Action |
|-------|--------|
| Unmapped sections | Add missing tasks or mark as context_only |
| Circular dependency | Split the cycle-causing task |
| Duplicate IDs | Rename conflicting task IDs |
| bd create fails | Check bd is initialized (`bd info`), check prefix |
| Partial creation | Script tracks created IDs, re-run skips existing |

---

# bd CLI Reference

**CRITICAL: NEVER use `bd edit`** — it opens `$EDITOR` which blocks the agent. Use `bd update` with flags instead.

## Priority Format

Priorities are **integers 0–4**, never strings. Using "high" or "medium" will error.

| Value | Meaning |
|-------|---------|
| 0 | Critical |
| 1 | High |
| 2 | Medium (default) |
| 3 | Low |
| 4 | Backlog |

## Task Lifecycle

After tasks are created, the agent works through them using this cycle:

```
1. FIND    →  bd ready --pretty              # What can I work on?
2. READ    →  bd show <id>                   # Understand the task
3. CLAIM   →  bd update <id> --claim         # Atomic claim (fails if taken)
4. WORK    →  (implement, test, commit)
5. CLOSE   →  bd close <id> --reason="..."   # Mark complete
6. NEXT    →  bd ready --pretty              # What's next?
```

### Finding Work

```bash
bd ready --pretty             # Tasks with all deps satisfied (no blockers)
bd list --status=open         # All open tasks
bd blocked                    # Tasks waiting on dependencies
bd search "query"             # Full-text search across all tasks
```

### Claiming and Working

```bash
bd update <id> --claim                    # Atomic claim — fails if already claimed
bd update <id> --status=in_progress       # Manual status change
bd update <id> --notes="progress update"  # Add notes during work
```

### Completing

```bash
bd close <id> --reason="Implemented with tests. All passing."
bd close <id1> <id2> <id3>               # Batch close (more efficient)
```

### Issue Management

```bash
bd create "Title" --type=task --priority=2
bd create "Title" --type=bug --parent=<epic-id>
bd update <id> --title="New title"        # NEVER use bd edit
bd update <id> --add-label=foo
bd update <id> --defer="+2d"              # Hide from ready until date
bd rename <old-id> <new-id>               # Change issue ID
```

### Dependencies

```bash
bd dep add <issue> <depends-on>           # issue depends on depends-on
bd dep tree <id>                          # Text dependency tree
bd graph <id> --compact                   # Visual dependency graph
```

### Epics and Hierarchy

```bash
bd epic status                            # Epic completion percentages
bd children <id>                          # List epic's children
```

### Session End Protocol

Before ending a session:
1. `bd close` all completed tasks
2. Check `bd ready --pretty` — report what's next
3. `bd sync --from-main` if on an ephemeral branch

## Issue Types

`task` | `bug` | `feature` | `epic` | `chore`

## Issue Statuses

| Status | Meaning |
|--------|---------|
| `open` | Not started |
| `in_progress` | Being worked on |
| `blocked` | Waiting on dependency |
| `deferred` | Hidden until defer date |
| `closed` | Completed |

---

# Quick Reference

| Command | Purpose |
|---------|---------|
| `bd-from-plan plan.json` | Create tasks from plan |
| `bd-from-plan --dry-run plan.json` | Preview without creating |
| `bd-from-plan --stdin < plan.json` | Read plan from stdin |
| `bd ready --pretty` | Show next available tasks |
| `bd show <id>` | Task details |
| `bd update <id> --claim` | Claim a task before working |
| `bd close <id> --reason="..."` | Complete a task |
| `bd graph` | Dependency visualization |
| `bd dep tree <id>` | Show task dependency tree |
| `bd epic status` | Epic completion overview |
| `bd blocked` | Tasks waiting on dependencies |
| `bd search "query"` | Full-text search |
