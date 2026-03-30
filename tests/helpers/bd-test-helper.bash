#!/bin/bash
# Shared test helper for bd-from-plan tests
# Provides isolated beads environment and common setup functions

# Path to the script under test
SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../skills/beads-from-plan/scripts" && pwd)"
BD_FROM_PLAN="${SCRIPT_DIR}/bd-from-plan"

# --- Git & Beads Environment Isolation ---

setup_git_env() {
    # Prevent interference from system/global git config
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
    export GIT_AUTHOR_NAME="Test"
    export GIT_AUTHOR_EMAIL="test@test.com"
    export GIT_COMMITTER_NAME="Test"
    export GIT_COMMITTER_EMAIL="test@test.com"

    git config --global init.defaultBranch master
    git config --global advice.detachedHead false

    # Wrap bd to always use --no-daemon in tests (prevents zombie daemon processes)
    bd() {
        command bd --no-daemon "$@"
    }
    export -f bd
}

# --- Repo Setup ---

# Create a fresh git repo with beads initialized
# Sets $REPO as the working directory
init_repo() {
    REPO="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "$REPO"
    cd "$REPO"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "initial" > README.md
    git add README.md
    git commit --quiet -m "initial commit"

    # Initialize beads (--no-daemon prevents zombie daemon processes in tests)
    bd init --no-daemon --quiet 2>/dev/null || bd init --no-daemon 2>/dev/null || true

    # Capture the beads prefix for assertions
    BD_PREFIX=$(bd config list 2>/dev/null | grep 'issue_prefix' | awk '{print $3}')
}

# Create a template repo once per file (in setup_file), then copy per test.
# Much faster than init_repo for tests that mutate state.
# Call in setup_file, then use init_repo_from_template in per-test setup.
init_template_repo() {
    # Use BATS_FILE_TMPDIR for git config (BATS_TEST_TMPDIR unavailable in setup_file)
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="${BATS_FILE_TMPDIR}/gitconfig"
    export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@test.com"
    export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@test.com"
    git config --global init.defaultBranch master
    git config --global advice.detachedHead false
    bd() { command bd --no-daemon "$@"; }; export -f bd

    TEMPLATE_REPO="${BATS_FILE_TMPDIR}/template"
    mkdir -p "$TEMPLATE_REPO"
    cd "$TEMPLATE_REPO"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "initial" > README.md
    git add README.md
    git commit --quiet -m "initial commit"

    bd init --no-daemon --quiet 2>/dev/null || bd init --no-daemon 2>/dev/null || true
    BD_PREFIX=$(bd config list 2>/dev/null | grep 'issue_prefix' | awk '{print $3}')

    export TEMPLATE_REPO BD_PREFIX
}

# Copy template repo for a fresh per-test instance (much faster than init_repo)
init_repo_from_template() {
    REPO="${BATS_TEST_TMPDIR}/repo"
    cp -a "$TEMPLATE_REPO" "$REPO"
    cd "$REPO"
}

# Create a shared repo once per file for non-mutating tests (dry-run, validate, stats).
# Call in setup_file. Tests share the same REPO — do NOT mutate bd state.
init_shared_repo() {
    # Use BATS_FILE_TMPDIR for git config (BATS_TEST_TMPDIR unavailable in setup_file)
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="${BATS_FILE_TMPDIR}/gitconfig"
    export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@test.com"
    export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@test.com"
    git config --global init.defaultBranch master
    git config --global advice.detachedHead false
    bd() { command bd --no-daemon "$@"; }; export -f bd

    REPO="${BATS_FILE_TMPDIR}/shared-repo"
    mkdir -p "$REPO"
    cd "$REPO"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "initial" > README.md
    git add README.md
    git commit --quiet -m "initial commit"

    bd init --no-daemon --quiet 2>/dev/null || bd init --no-daemon 2>/dev/null || true
    BD_PREFIX=$(bd config list 2>/dev/null | grep 'issue_prefix' | awk '{print $3}')

    export REPO BD_PREFIX
}

# Stop the bd daemon spawned by init_repo
# Must be called in each test file's teardown() to prevent zombie daemons
teardown_repo() {
    if [ -n "${REPO:-}" ] && [ -d "${REPO}/.beads" ]; then
        bd daemons stop "$REPO" 2>/dev/null || true
    fi
}

teardown_template_repo() {
    if [ -n "${TEMPLATE_REPO:-}" ] && [ -d "${TEMPLATE_REPO}/.beads" ]; then
        bd daemons stop "$TEMPLATE_REPO" 2>/dev/null || true
    fi
}

# --- Plan Fixtures (directory-based) ---
# Each fixture creates a plan directory with _plan.json + epic-*.json files.
# Returns the plan directory path.

# Create a minimal valid plan with one epic and one task
create_minimal_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "test",
  "coverage": {
    "total_sections": 3,
    "mapped_sections": 2,
    "unmapped": [],
    "context_only": ["# Plan Title"]
  }
}
EOF

    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core Feature",
  "source_sections": ["## 1. Core"],
  "tasks": [
    {
      "id": "setup",
      "title": "Initial setup",
      "source_sections": ["### 1.1 Setup"],
      "type": "task",
      "priority": 2,
      "estimate_minutes": 5
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with two epics and dependencies
create_dependency_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "dep",
  "coverage": {
    "total_sections": 7,
    "mapped_sections": 6,
    "unmapped": [],
    "context_only": ["# Auth Plan"]
  }
}
EOF

    cat > "$plan_dir/epic-model.json" << 'EOF'
{
  "id": "model",
  "title": "Data Models",
  "source_sections": ["## 1. Models"],
  "tasks": [
    {
      "id": "user",
      "title": "Create User model",
      "source_sections": ["### 1.1 User Model"],
      "type": "feature",
      "priority": 1,
      "estimate_minutes": 10,
      "depends_on": []
    },
    {
      "id": "token",
      "title": "Create Token model",
      "source_sections": ["### 1.2 Token Model"],
      "type": "feature",
      "priority": 1,
      "estimate_minutes": 10,
      "depends_on": ["user"]
    }
  ]
}
EOF

    cat > "$plan_dir/epic-api.json" << 'EOF'
{
  "id": "api",
  "title": "API Endpoints",
  "source_sections": ["## 2. API"],
  "tasks": [
    {
      "id": "login",
      "title": "Login endpoint",
      "source_sections": ["### 2.1 Login"],
      "type": "feature",
      "priority": 2,
      "estimate_minutes": 15,
      "depends_on": ["model-user", "model-token"]
    },
    {
      "id": "logout",
      "title": "Logout endpoint",
      "source_sections": ["### 2.2 Logout"],
      "type": "feature",
      "priority": 2,
      "estimate_minutes": 10,
      "depends_on": ["login"]
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with quality gates and estimates
create_full_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/full-plan.md",
  "prefix": "full",
  "workflow": {
    "quality_gate": "composer lint && composer test && composer type",
    "commit_strategy": "agentic-commits",
    "checklist_note": "- [ ] Run quality gate: composer lint && composer test && composer type\n- [ ] Commit IMMEDIATELY after gate passes (do NOT batch with other tasks)\n- [ ] Commit using agentic-commits"
  },
  "coverage": {
    "total_sections": 5,
    "mapped_sections": 3,
    "unmapped": [],
    "context_only": ["# Full Plan", "## Overview"]
  }
}
EOF

    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core Implementation",
  "description": "Main feature implementation",
  "priority": 1,
  "labels": ["core", "v1"],
  "source_sections": ["## 1. Core"],
  "tasks": [
    {
      "id": "model",
      "title": "Create data model",
      "description": "Define the main data model with proper fields and indexes",
      "type": "feature",
      "priority": 1,
      "estimate_minutes": 10,
      "labels": ["model"],
      "depends_on": [],
      "source_sections": ["### 1.1 Data Model"],
      "source_lines": "10-25",
      "acceptance": "Model created with migration and factory",
      "commit_strategy": "agentic-commits"
    },
    {
      "id": "service",
      "title": "Implement service layer",
      "description": "Service class with business logic",
      "type": "feature",
      "priority": 1,
      "estimate_minutes": 15,
      "depends_on": ["model"],
      "source_sections": ["### 1.2 Service Layer"],
      "source_lines": "26-55",
      "acceptance": "Service methods work with tests passing",
      "quality_gate": "composer lint && composer test",
      "commit_strategy": "agentic-commits"
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with unmapped sections (should fail validation)
create_unmapped_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "bad",
  "coverage": {
    "total_sections": 5,
    "mapped_sections": 2,
    "unmapped": ["### 1.2 Configuration", "### 1.3 Testing"],
    "context_only": ["# Title"]
  }
}
EOF

    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core Feature",
  "source_sections": ["## 1. Core"],
  "tasks": [
    {
      "id": "setup",
      "title": "Initial setup",
      "source_sections": ["### 1.1 Setup"],
      "estimate_minutes": 5
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with circular dependencies (should fail)
create_circular_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "cyc",
  "coverage": {
    "total_sections": 4,
    "mapped_sections": 3,
    "unmapped": [],
    "context_only": ["# Title"]
  }
}
EOF

    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core",
  "source_sections": ["## 1. Core"],
  "tasks": [
    {
      "id": "a",
      "title": "Task A",
      "source_sections": ["### 1.1 A"],
      "estimate_minutes": 5,
      "depends_on": ["b"]
    },
    {
      "id": "b",
      "title": "Task B",
      "source_sections": ["### 1.2 B"],
      "estimate_minutes": 5,
      "depends_on": ["a"]
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with 3-node circular dependency A->B->C->A (should fail)
create_3node_circular_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "cyc3",
  "coverage": {
    "total_sections": 5,
    "mapped_sections": 4,
    "unmapped": [],
    "context_only": ["# Title"]
  }
}
EOF

    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core",
  "source_sections": ["## 1. Core"],
  "tasks": [
    {
      "id": "a",
      "title": "Task A",
      "source_sections": ["### 1.1 A"],
      "estimate_minutes": 5,
      "depends_on": ["c"]
    },
    {
      "id": "b",
      "title": "Task B",
      "source_sections": ["### 1.2 B"],
      "estimate_minutes": 5,
      "depends_on": ["a"]
    },
    {
      "id": "c",
      "title": "Task C",
      "source_sections": ["### 1.3 C"],
      "estimate_minutes": 5,
      "depends_on": ["b"]
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with duplicate IDs (should fail)
create_duplicate_id_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "dup",
  "coverage": {
    "total_sections": 4,
    "mapped_sections": 3,
    "unmapped": [],
    "context_only": ["# Title"]
  }
}
EOF

    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core",
  "source_sections": ["## 1. Core"],
  "tasks": [
    {
      "id": "setup",
      "title": "First setup",
      "source_sections": ["### 1.1 Setup"],
      "estimate_minutes": 5
    },
    {
      "id": "setup",
      "title": "Second setup",
      "source_sections": ["### 1.2 Setup"],
      "estimate_minutes": 5
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with atomicity violations (should warn)
create_atomicity_warning_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    # Generate a long description (> 300 chars)
    local long_desc
    long_desc=$(printf 'x%.0s' $(seq 1 350))

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "atom",
  "coverage": {
    "total_sections": 5,
    "mapped_sections": 4,
    "unmapped": [],
    "context_only": ["# Title"]
  }
}
EOF

    cat > "$plan_dir/epic-core.json" << EOF
{
  "id": "core",
  "title": "Core",
  "source_sections": ["## 1. Core"],
  "tasks": [
    {
      "id": "too-big",
      "title": "Create config and migration and model",
      "description": "${long_desc}",
      "estimate_minutes": 90,
      "source_sections": ["### 1.1 A", "### 1.2 B", "### 1.3 C"]
    }
  ]
}
EOF
    echo "$plan_dir"
}

# Create a plan with many tasks per epic (15+ to test large plan handling)
create_large_plan() {
    local plan_dir="${1:-${BATS_TEST_TMPDIR}/plan}"
    mkdir -p "$plan_dir"

    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/large-plan.md",
  "prefix": "lg",
  "coverage": {
    "total_sections": 22,
    "mapped_sections": 20,
    "unmapped": [],
    "context_only": ["# Large Plan", "## Overview"]
  }
}
EOF

    # Epic with 15 tasks
    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core Components",
  "source_sections": ["## 1. Core"],
  "tasks": [
    {"id": "t01", "title": "Create model A", "source_sections": ["### 1.01"], "type": "task", "priority": 1, "estimate_minutes": 10},
    {"id": "t02", "title": "Create model B", "source_sections": ["### 1.02"], "type": "task", "priority": 1, "estimate_minutes": 10, "depends_on": ["t01"]},
    {"id": "t03", "title": "Create model C", "source_sections": ["### 1.03"], "type": "task", "priority": 1, "estimate_minutes": 10, "depends_on": ["t01"]},
    {"id": "t04", "title": "Create service D", "source_sections": ["### 1.04"], "type": "task", "priority": 2, "estimate_minutes": 15, "depends_on": ["t02", "t03"]},
    {"id": "t05", "title": "Create service E", "source_sections": ["### 1.05"], "type": "task", "priority": 2, "estimate_minutes": 15, "depends_on": ["t02"]},
    {"id": "t06", "title": "Create handler F", "source_sections": ["### 1.06"], "type": "task", "priority": 2, "estimate_minutes": 10, "depends_on": ["t04"]},
    {"id": "t07", "title": "Create handler G", "source_sections": ["### 1.07"], "type": "task", "priority": 2, "estimate_minutes": 10, "depends_on": ["t04"]},
    {"id": "t08", "title": "Create controller H", "source_sections": ["### 1.08"], "type": "task", "priority": 2, "estimate_minutes": 15, "depends_on": ["t06", "t07"]},
    {"id": "t09", "title": "Create middleware I", "source_sections": ["### 1.09"], "type": "task", "priority": 2, "estimate_minutes": 10},
    {"id": "t10", "title": "Create config J", "source_sections": ["### 1.10"], "type": "task", "priority": 3, "estimate_minutes": 5},
    {"id": "t11", "title": "Create migration K", "source_sections": ["### 1.11"], "type": "task", "priority": 1, "estimate_minutes": 5, "depends_on": ["t10"]},
    {"id": "t12", "title": "Create factory L", "source_sections": ["### 1.12"], "type": "task", "priority": 2, "estimate_minutes": 5, "depends_on": ["t11"]},
    {"id": "t13", "title": "Create seeder M", "source_sections": ["### 1.13"], "type": "task", "priority": 3, "estimate_minutes": 5, "depends_on": ["t12"]},
    {"id": "t14", "title": "Create test N", "source_sections": ["### 1.14"], "type": "task", "priority": 2, "estimate_minutes": 10, "depends_on": ["t08"]},
    {"id": "t15", "title": "Create test O", "source_sections": ["### 1.15"], "type": "task", "priority": 2, "estimate_minutes": 10, "depends_on": ["t05"]}
  ]
}
EOF

    # Second epic with 5 tasks and cross-epic dependencies
    cat > "$plan_dir/epic-docs.json" << 'EOF'
{
  "id": "docs",
  "title": "Documentation",
  "source_sections": ["## 2. Docs"],
  "tasks": [
    {"id": "readme", "title": "Write README", "source_sections": ["### 2.1"], "type": "chore", "priority": 3, "estimate_minutes": 10, "depends_on": ["core-t08"]},
    {"id": "api-docs", "title": "Write API docs", "source_sections": ["### 2.2"], "type": "chore", "priority": 3, "estimate_minutes": 10, "depends_on": ["core-t08"]},
    {"id": "changelog", "title": "Update changelog", "source_sections": ["### 2.3"], "type": "chore", "priority": 3, "estimate_minutes": 5},
    {"id": "config-docs", "title": "Document config options", "source_sections": ["### 2.4"], "type": "chore", "priority": 3, "estimate_minutes": 10, "depends_on": ["core-t10"]},
    {"id": "migration-guide", "title": "Write migration guide", "source_sections": ["### 2.5"], "type": "chore", "priority": 3, "estimate_minutes": 10, "depends_on": ["core-t11"]}
  ]
}
EOF
    echo "$plan_dir"
}

# --- Assertion Helpers ---

# Assert the output contains a string
assert_output_contains() {
    local expected="$1"
    if [[ "$output" != *"$expected"* ]]; then
        echo "Expected output to contain: $expected"
        echo "Actual output:"
        echo "$output"
        return 1
    fi
}

# Assert the output does NOT contain a string
assert_output_not_contains() {
    local unexpected="$1"
    if [[ "$output" == *"$unexpected"* ]]; then
        echo "Expected output to NOT contain: $unexpected"
        echo "Actual output:"
        echo "$output"
        return 1
    fi
}

# Assert stderr contains a string
assert_stderr_contains() {
    local expected="$1"
    if [[ "${stderr:-}" != *"$expected"* ]]; then
        echo "Expected stderr to contain: $expected"
        echo "Actual stderr:"
        echo "${stderr:-}"
        return 1
    fi
}
