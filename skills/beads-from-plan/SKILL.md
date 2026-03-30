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
# Create a plan directory with mktemp
PLAN_DIR=$(mktemp -d /tmp/task-plan-XXXXXXXX)
# Write _plan.json and epic-*.json files into PLAN_DIR (see steps below)
<base_directory>/scripts/bd-from-plan "$PLAN_DIR"
```

---

# The Process

## Overview

```
Markdown Plan (2000+ lines)
        |
        v
   AI Analysis (per-epic, parallelizable)
   - Parse all headings (##, ###, ####)
   - Identify epics (top-level sections)
   - Identify tasks (sub-sections)
   - Map dependencies between tasks
   - Verify 100% section coverage
        |
        v
  Plan Directory (mktemp -d)
   plan-dir/
     _plan.json           Global: prefix, workflow, coverage
     epic-auth.json       Epic + tasks (full details)
     epic-payment.json    Epic + tasks (full details)
        |
        v
  bd-from-plan script
   - Merges _plan.json + epic-*.json files
   - Validates structure and coverage
   - Rejects if unmapped sections exist
   - Detects circular dependencies
   - Topological sort by dependencies
   - Creates epics and tasks in order
   - Wires dependencies via bd dep add
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

### Dependency Format

The script uses **smart resolution** — both formats work transparently:

| Dependency Type | Format | Example |
|----------------|--------|---------|
| Same-epic | Just task ID | `"depends_on": ["create-model"]` |
| Cross-epic | `epicId-taskId` | `"depends_on": ["model-create-model"]` |

Resolution: tries exact match against all `epicId-taskId` first, then falls back to same-epic.

### Circular Dependencies

The script detects and rejects circular dependencies. If you find a cycle:
- Break it by splitting one task into two
- The setup part has no dependency, the integration part depends on the other

## Atomic Task Decomposition (STRICT)

**Each task MUST be completable by an AI agent in a single execution AND expressible as one commit.**

This is the second most important rule (after 100% coverage). These tasks are designed for AI agent execution (including parallel agents), not human sessions. Over-broad tasks cause:
- **Context rot** — accuracy drops 20-50% as agent context grows from 10K→100K tokens (Chroma research)
- **Success cliff** — SWE-bench: <15 min tasks = 70%+ success, 1+ hour = 23% success
- **Poor commits** — impossible to create atomic commits from broad tasks
- **Tracking failure** — "50% done" tasks are invisible in beads
- **Parallelism blocked** — coarse tasks can't be distributed across parallel agents

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

### Rule 3: Maximum 15 Minutes

**Implementation tasks MUST NOT exceed 15 minutes.**

Tasks are executed by AI agents, not humans. There is no minimum — a 1-minute task is perfectly valid. The goal is maximum atomicity for agent success and parallelization.

| Estimate | Action |
|----------|--------|
| 1–15 min | Ideal agent task — high success rate, parallelizable |
| 16–30 min | MUST split — agent accuracy degrades significantly |
| > 30 min | MUST split aggressively — this is multiple tasks disguised as one |

**Why 15 minutes?** Data-driven: METR shows Claude 50% success at ~50 min with non-linear degradation. SWE-bench shows <15 min tasks achieve 70%+ success. Setting the max at 15 minutes keeps each task well within the high-success zone.

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
  5. Time Check → "Is this ≤ 15 minutes?"
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

**AFTER** (6 atomic tasks):

```json
[
  {"id": "config",       "title": "Add parallel_dispatch config section",        "estimate_minutes": 5},
  {"id": "migration",    "title": "Create machine_locks migration",              "estimate_minutes": 5},
  {"id": "model",        "title": "Create MachineStateLock Eloquent model",      "estimate_minutes": 10},
  {"id": "lock-manager", "title": "Create MachineLockManager service",           "estimate_minutes": 15},
  {"id": "lock-handle",  "title": "Create MachineLockHandle value object",       "estimate_minutes": 10},
  {"id": "lock-ex",      "title": "Create LockTimeoutException class",           "estimate_minutes": 5}
]
```

Each task: one commit, one verb, one file, ≤ 15 min. Parallelizable where dependencies allow.

### Expected Task Counts

Use this as calibration — if your count is significantly below, you're under-decomposing. With 15-minute max, expect more tasks than traditional approaches:

| Plan Size | Expected Tasks |
|-----------|---------------|
| 100 lines | 12–25 tasks |
| 500 lines | 40–70 tasks |
| 1000 lines | 70–120 tasks |
| 2000 lines | 120–200 tasks |

### Splitting Heuristics Catalog

When a task fails an atomicity check, use these patterns to split it:

| Pattern in Title/Description | Split Into | Example |
|------------------------------|-----------|---------|
| "Create X with tests" | "Create X" + "Test X" | "Create UserModel" + "Test UserModel" |
| "Create X, Y, and Z" | One task per noun | "Create Config" + "Create Migration" + "Create Model" |
| "X and Y" (two verbs) | One task per verb | "Add config" + "Create migration" |
| "Implement X with Y handling" | Core + edge cases | "Implement service" + "Add error handling" |
| "Update X across A, B, C" | One task per target | "Update X in A" + "Update X in B" + "Update X in C" |
| "Create X (model + migration + factory)" | One task per file concern | "Create X model" + "Create X migration" + "Create X factory" |
| "Write docs for X" (multi-section) | One task per doc section | "Write X overview" + "Write X API reference" + "Write X examples" |
| Task with >3 acceptance criteria | Split by acceptance criterion | Each criterion becomes its own task |

**Anti-Patterns to Recognize:**

| Anti-Pattern | Why It's Bad | Fix |
|-------------|-------------|-----|
| "Infrastructure: config, migration, model, service" | 4+ files, 4+ concerns | Split into 4 tasks |
| "Implement feature end-to-end" | Crosses model/service/controller layers | One task per layer |
| "Write all unit tests for X" | Multiple test classes, multiple concerns | One task per test file |
| "Update documentation" (generic) | Multiple docs, multiple sections | One task per document |
| "Refactor X and add Y" | Refactor ≠ feature, different concerns | Separate refactor and feature tasks |

### Estimate Calibration Table

Use these reference estimates when assigning `estimate_minutes`. An AI agent completing each task type should fall within these ranges:

| Task Type | Typical Estimate | Notes |
|-----------|-----------------|-------|
| Config file (add/modify section) | 3–5 min | Single file, few lines |
| Migration (create table) | 3–5 min | Schema definition only |
| Eloquent/ORM model | 5–8 min | Fields, casts, relationships |
| Factory/Seeder | 3–5 min | Definition + basic states |
| Value Object / DTO | 5–8 min | Properties + construction |
| Exception class | 2–3 min | Minimal boilerplate |
| Service class (1–3 methods) | 10–15 min | Business logic, dependencies |
| Controller endpoint | 8–12 min | Request handling, validation |
| Middleware | 5–8 min | Single responsibility |
| Test file (3–5 test cases) | 8–12 min | Setup + assertions |
| Test file (1–2 test cases) | 3–5 min | Focused test |
| Documentation page | 8–12 min | Prose + code examples |
| Config/route registration | 2–3 min | One-liner additions |

**If your estimate exceeds 15 minutes, the task is too broad.** Split it using the heuristics above.

**If you're unsure about the estimate:** err on the side of smaller. A 5-minute task that takes 8 minutes is fine. A 15-minute task that takes 30 minutes means the task was under-decomposed.

### Post-Decomposition Self-Check (MANDATORY)

**After generating all epic JSON files, BEFORE running the script, perform this self-check:**

```
FOR each task in the plan:
  1. Write the commit message for this task
     → If you can't write ONE commit message, SPLIT
  2. Name the files this task will create/modify
     → If more than 2 files (excluding test), SPLIT
  3. State the single concern this task addresses
     → If you need "and" to describe it, SPLIT
  4. Verify estimate_minutes ≤ 15
     → If not, SPLIT using the calibration table
```

**Example self-check output (write this for each epic before saving):**

```
Epic: auth
  task auth-user-model
    commit: "feat(User): create model with migration"
    files: app/Models/User.php, database/migrations/create_users.php
    concern: User data model definition
    estimate: 8m ✓
  task auth-login-flow
    commit: "feat(auth): implement login endpoint with JWT"
    files: app/Http/Controllers/AuthController.php
    concern: Login request handling
    estimate: 12m ✓
```

If any task fails a check, split it and re-run the self-check on the sub-tasks.

### Two-Pass Decomposition (MANDATORY for plans > 500 lines)

**Pass 1: Rough Decomposition**
- Read the plan (delegate to subagent for large plans)
- Map sections to epics and rough tasks
- Don't worry about perfect atomicity yet
- Focus on 100% coverage and correct dependencies

**Pass 2: Atomicity Refinement**
- For each task from Pass 1, run ALL atomicity checks
- Apply the Splitting Heuristics Catalog for any violations
- Run the Post-Decomposition Self-Check
- Verify estimates using the Calibration Table
- Only write the JSON files AFTER Pass 2 is complete

**Why two passes?** Single-pass decomposition optimizes for coverage (getting every section mapped) at the expense of atomicity (making each task small enough). Two passes let you nail coverage first, then refine granularity.

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

Each task's `commit_strategy` determines HOW the agent commits after the quality gate passes.

| Strategy | Agent Action |
|----------|-------------|
| `agentic-commits` | Invoke the `/agentic-commits` skill — it splits changes into atomic one-file-per-commit hunks with structured messages |
| `conventional` | `git add` changed files + `git commit` with `type(scope): message` format |
| `manual` | Do NOT commit — leave changes staged for user to handle |

**Default:** `agentic-commits` for all code tasks. The workflow-level default applies unless a task overrides it.

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
    "checklist_note": "- [ ] Run quality gate: composer lint && composer test && composer larastan\n- [ ] Commit IMMEDIATELY after gate passes (do NOT batch with other tasks)\n- [ ] Commit using agentic-commits"
  }
}
```

The `checklist_note` is a human-readable summary of the workflow. The script appends it to every task's description as a checklist.

Individual tasks can override the workflow defaults via their own `quality_gate` and `commit_strategy` fields. If not overridden, the workflow defaults apply.

---

## Step 1: Read the Plan

**Delegate plan reading to keep the main agent's context clean.**

For large plans (500+ lines), use this approach:

1. **Extract headings first** — get the structural skeleton without reading content:
   ```bash
   grep -n '^#' plan.md
   ```

2. **Delegate full reading to a subagent** — spawn a single Agent (subagent_type: "general-purpose") with a clear prompt:
   - Read the full plan file
   - Extract epics, tasks, dependencies, and coverage mapping
   - Return a structured summary (not the raw content)

3. **For smaller plans (<500 lines)** — reading directly is fine, but prefer the Read tool over cat.

**Why?** Large plans (2000+ lines) consume 30-50K tokens of context. Delegating to a subagent keeps the main context free for JSON generation and validation. Chunked parallel reading was tested and rejected — cross-chunk dependency loss outweighs the speed gain.

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

## Step 5: Generate Plan Directory

Write the plan as a directory with separate files. This keeps each file small and recoverable.

```bash
PLAN_DIR=$(mktemp -d /tmp/task-plan-XXXXXXXX)
```

### Step 5a: Write `_plan.json` (global metadata)

```bash
cat > "$PLAN_DIR/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plans/feature-x.md",
  "prefix": "feat",
  "workflow": {
    "quality_gate": "composer lint && composer test && composer type",
    "commit_strategy": "agentic-commits",
    "checklist_note": "- [ ] Run quality gate: composer lint && composer test && composer type\n- [ ] Commit IMMEDIATELY after gate passes (do NOT batch with other tasks)\n- [ ] Commit using agentic-commits"
  },
  "coverage": {
    "total_sections": 12,
    "mapped_sections": 10,
    "unmapped": [],
    "context_only": ["# Feature X Plan", "## Overview"]
  }
}
EOF
```

### Step 5b: Write one `epic-{id}.json` per epic

Write each epic as a separate file. **Each file is small** (~1-3K tokens), minimizing AI output errors.

**Required fields per task:** `id`, `title`, `source_sections`, `estimate_minutes` (positive integer, max 15). The script rejects tasks missing any of these.

```bash
cat > "$PLAN_DIR/epic-auth.json" << 'EOF'
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
      "estimate_minutes": 10,
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
      "description": "POST /api/login accepts email+password, returns JWT.",
      "type": "feature",
      "priority": 1,
      "estimate_minutes": 15,
      "depends_on": ["user-model"],
      "source_sections": ["### 1.2 Login Flow", "#### 1.2.1 JWT Tokens"],
      "source_lines": "43-98",
      "acceptance": "Login endpoint returns valid JWT. Invalid credentials return 401.",
      "commit_strategy": "agentic-commits"
    }
  ]
}
EOF
```

**File naming convention:** `epic-{id}.json` where `{id}` matches the epic's `id` field. Files are read in alphabetical order.

## Step 6: Execute Plan

**Always use `--strict` to enforce atomicity.** Use `--dry-run` first to preview.

```bash
# Step 6a: Dry-run with strict atomicity enforcement
<base_directory>/scripts/bd-from-plan --strict --dry-run "$PLAN_DIR"

# Step 6b: If dry-run passes, create tasks
<base_directory>/scripts/bd-from-plan --strict "$PLAN_DIR"
```

The script will:
1. Validate the JSON (structure + required fields including `estimate_minutes`)
2. Check atomicity (in strict mode: violations = errors)
3. Check coverage (fail if unmapped sections)
4. Detect circular dependencies (fail if cycles)
5. Create epics in order
6. Create tasks in topological order (with progress logging)
7. Wire up dependencies
8. Show parallelism analysis (levels, critical path, speedup potential)
9. Verify task counts (expected vs created — fail if mismatch)
10. Print summary with `bd ready` output

## Step 7: Verify

```bash
bd ready --pretty          # See what's ready to work on
bd graph                   # Visualize dependency graph
bd epic status             # Check epic completion status
```

---

# MODE 2: VERIFY

Validate an existing plan JSON against its source markdown.

## Step 1: Load Plan Directory

```bash
# Read the global metadata
cat "$PLAN_DIR/_plan.json" | jq .

# Read the source markdown
SOURCE=$(cat "$PLAN_DIR/_plan.json" | jq -r '.source')

# List all epic files
ls "$PLAN_DIR"/epic-*.json
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
<base_directory>/scripts/bd-from-plan --dry-run "$PLAN_DIR"
```

This validates everything and shows what WOULD be created without actually creating anything.

---

# Strict Mode

Use `--strict` to enforce atomicity as errors (not just warnings). **Recommended for production plans.**

```bash
<base_directory>/scripts/bd-from-plan --strict "$PLAN_DIR"
# or combined with dry-run:
<base_directory>/scripts/bd-from-plan --strict --dry-run "$PLAN_DIR"
```

In strict mode, any atomicity violation (estimate > 15m, conjunctions in title, >3 acceptance criteria, etc.) **blocks plan creation**. Fix all violations before proceeding.

---

# Validate Mode

Check plan quality without creating anything and without needing `bd` initialized:

```bash
<base_directory>/scripts/bd-from-plan --validate "$PLAN_DIR"
```

Validates: structure, atomicity, coverage, circular dependencies. Reports pass/fail. Also shows plan statistics and parallelism analysis.

---

# Stats Mode

View plan statistics without creating anything:

```bash
<base_directory>/scripts/bd-from-plan --stats "$PLAN_DIR"
```

Shows: task/epic counts, estimate min/avg/max, per-epic breakdown, parallelism levels, critical path, speedup potential, and plan size heuristic.

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
4. WORK    →  implement the task
5. GATE    →  run quality gate command        # Must pass before commit
6. VERIFY  →  completion verification        # Confirm ALL acceptance criteria met
7. COMMIT  →  commit using commit_strategy   # IMMEDIATELY after gate passes
8. CLOSE   →  bd close <id> --reason="..."   # Mark complete with evidence
9. NEXT    →  bd ready --pretty              # What's next?
```

### Completion Verification (Step 6 — MANDATORY)

**After the quality gate passes but BEFORE committing, verify the full scope was implemented.**

This step prevents the most common failure mode: quality gate passes (code compiles, tests pass) but the task's full scope was not implemented.

```
VERIFY checklist (run mentally for each task):
  1. Re-read acceptance criteria:  bd show <id>
  2. For each criterion, find the evidence:
     - "Model exists" → file path + class name
     - "Tests pass" → test file path + test count
     - "Docs updated" → file path + section
  3. Count check: if spec says "5 test cases", count them
  4. Write the closure reason BEFORE closing — it must address each criterion
```

**If any criterion is not met, do NOT commit. Go back to step 4 (WORK).**

The closure reason in step 8 should read like a checklist receipt:
```bash
bd close <id> --reason="Model at app/Models/Lock.php (12 fields). Migration 2024_01_create runs. Factory generates valid instances. 3/3 acceptance criteria met."
```

### Commit After Every Task (STRICT)

**Each task MUST be committed IMMEDIATELY after its quality gate passes.** Do NOT batch commits.

| Pattern | Result |
|---------|--------|
| Task 1 done → commit → Task 2 done → commit → Task 3 done → commit | CORRECT |
| Task 1 done → Task 2 done → Task 3 done → commit all | WRONG |

**Why?** Batching commits defeats the purpose of atomic tasks:
- Impossible to revert a single task
- `bd close` with no matching commit breaks traceability
- Parallel agents can't see each other's progress
- Context loss mid-session loses all uncommitted work

The commit strategy (from `workflow.commit_strategy` or task-level override) determines the format.
For `agentic-commits`: use the `/agentic-commits` skill to split changes into atomic, one-file-per-commit hunks.

### Task Closure Rules (STRICT)

**A task is either DONE or OPEN. There is no middle ground.**

These rules prevent silent task loss — the #1 failure mode in large plan execution.

#### Rule 1: No "Deferred" Closures

**NEVER close a task with "deferred", "will be done later", or "to be handled in another task".**

| Closure Reason | Allowed? | What To Do Instead |
|---------------|----------|-------------------|
| "Implemented with tests passing" | YES | Genuine completion |
| "Deferred — will be done later" | NO | Leave the task OPEN |
| "Will be handled during merge" | NO | Leave OPEN, add note |
| "Skipped — not needed" | ONLY if acceptance criteria are provably N/A | Add proof to reason |

If a task can't be completed now, leave it open. Use `bd update <id> --notes="Blocked by X"` to explain.

#### Rule 2: No "Covered By Existing" Without Proof

**To close a task as "covered by existing code/tests", you MUST provide grep proof.**

Before closing with this reason:
1. Read the task's acceptance criteria or spec test case list
2. For EACH required item, `grep` the codebase to find it
3. Include the grep results in the closure reason

```bash
# WRONG: "Covered by existing tests in FooTest"
bd close <id> --reason="Covered by existing tests in FooTest"

# RIGHT: Verify first, then close with evidence
grep -l "testMethodName" tests/  # Find actual test
bd close <id> --reason="All 5 test cases found in tests/FooTest.php: testA (L42), testB (L58), testC (L74), testD (L90), testE (L106)"
```

#### Rule 3: Quality Gate Green ≠ Task Complete

**A passing quality gate means the code is correct, NOT that the task's full scope was implemented.**

Before closing any task:
1. Re-read the task description and acceptance criteria (`bd show <id>`)
2. Compare the spec's requirements against what was actually implemented
3. If the task specifies N test cases, verify N test cases exist (not just that tests pass)

| Scenario | Quality Gate | Task Complete? |
|----------|-------------|---------------|
| 5/5 test cases written, all pass | GREEN | YES |
| 3/5 test cases written, all pass | GREEN | NO — 2 missing |
| All code written, no tests yet | RED or GREEN | NO — tests required |

#### Rule 4: Documentation Tasks Require Content Verification

**To close a documentation task, the target file MUST contain the documented content.**

Before closing a docs task:
1. Read the target file
2. Verify the required content sections are present
3. Include file path and line count in closure reason

```bash
# WRONG: "Documentation defined in spec — will be written during merge"
# RIGHT: Verify the file, then close
wc -l docs/typed-contracts.md  # "142 docs/typed-contracts.md"
bd close <id> --reason="docs/typed-contracts.md written (142 lines), covers all 8 sections from spec"
```

#### Rule 5: Acceptance Criteria Validation

**If a task has acceptance criteria, the closure reason MUST address each criterion.**

```bash
# Task acceptance: "Model exists. Migration runs. Factory works."
# WRONG: bd close <id> --reason="Done"
# RIGHT: bd close <id> --reason="Model at app/Models/Foo.php. Migration 2024_01_create_foo runs clean. Factory generates valid instances (tested)."
```

#### Closure Checklist (apply to EVERY task)

```
BEFORE running `bd close <id>`:
  1. Re-read: bd show <id>  — read description + acceptance criteria
  2. Verify scope: Does the implementation match the FULL spec, not just "enough to pass CI"?
  3. Count items: If spec lists N items (test cases, docs sections, endpoints), verify N items exist
  4. Check acceptance: Can you address each acceptance criterion with evidence?
  5. Write reason: Closure reason must explain WHY criteria are met, not just "done"
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
| `bd-from-plan plan-dir/` | Create tasks from plan directory |
| `bd-from-plan --dry-run plan-dir/` | Preview without creating |
| `bd-from-plan --strict plan-dir/` | Create with atomicity enforcement (recommended) |
| `bd-from-plan --validate plan-dir/` | Check-only: validate structure, atomicity, coverage |
| `bd-from-plan --stats plan-dir/` | Show plan statistics and parallelism analysis |
| `bd ready --pretty` | Show next available tasks |
| `bd show <id>` | Task details |
| `bd update <id> --claim` | Claim a task before working |
| `bd close <id> --reason="..."` | Complete a task |
| `bd graph` | Dependency visualization |
| `bd dep tree <id>` | Show task dependency tree |
| `bd epic status` | Epic completion overview |
| `bd blocked` | Tasks waiting on dependencies |
| `bd search "query"` | Full-text search |
