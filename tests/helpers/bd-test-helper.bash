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

    # Initialize beads
    bd init --quiet 2>/dev/null || bd init 2>/dev/null || true

    # Capture the beads prefix for assertions
    BD_PREFIX=$(bd config list 2>/dev/null | grep 'issue_prefix' | awk '{print $3}')
}

# --- Plan Fixtures ---

# Create a minimal valid plan with one epic and one task
create_minimal_plan() {
    local plan_file="${1:-${REPO}/plan.json}"
    cat > "$plan_file" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "test",
  "epics": [
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
          "priority": 2
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 3,
    "mapped_sections": 2,
    "unmapped": [],
    "context_only": ["# Plan Title"]
  }
}
EOF
    echo "$plan_file"
}

# Create a plan with two epics and dependencies
create_dependency_plan() {
    local plan_file="${1:-${REPO}/plan.json}"
    cat > "$plan_file" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "dep",
  "epics": [
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
          "depends_on": []
        },
        {
          "id": "token",
          "title": "Create Token model",
          "source_sections": ["### 1.2 Token Model"],
          "type": "feature",
          "priority": 1,
          "depends_on": ["user"]
        }
      ]
    },
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
          "depends_on": ["model-user", "model-token"]
        },
        {
          "id": "logout",
          "title": "Logout endpoint",
          "source_sections": ["### 2.2 Logout"],
          "type": "feature",
          "priority": 2,
          "depends_on": ["login"]
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 7,
    "mapped_sections": 6,
    "unmapped": [],
    "context_only": ["# Auth Plan"]
  }
}
EOF
    echo "$plan_file"
}

# Create a plan with quality gates and estimates
create_full_plan() {
    local plan_file="${1:-${REPO}/plan.json}"
    cat > "$plan_file" << 'EOF'
{
  "version": 1,
  "source": "docs/full-plan.md",
  "prefix": "full",
  "epics": [
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
          "estimate_minutes": 45,
          "labels": ["model"],
          "depends_on": [],
          "source_sections": ["### 1.1 Data Model"],
          "source_lines": "10-25",
          "acceptance": "Model created with migration and factory",
          "quality_gate": {
            "lint": true,
            "test": true,
            "type_check": true
          },
          "commit_strategy": "agentic-commits"
        },
        {
          "id": "service",
          "title": "Implement service layer",
          "description": "Service class with business logic",
          "type": "feature",
          "priority": 1,
          "estimate_minutes": 90,
          "depends_on": ["model"],
          "source_sections": ["### 1.2 Service Layer"],
          "source_lines": "26-55",
          "acceptance": "Service methods work with tests passing",
          "quality_gate": {
            "lint": true,
            "test": true
          },
          "commit_strategy": "agentic-commits"
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 5,
    "mapped_sections": 3,
    "unmapped": [],
    "context_only": ["# Full Plan", "## Overview"]
  }
}
EOF
    echo "$plan_file"
}

# Create a plan with unmapped sections (should fail validation)
create_unmapped_plan() {
    local plan_file="${1:-${REPO}/plan.json}"
    cat > "$plan_file" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "bad",
  "epics": [
    {
      "id": "core",
      "title": "Core Feature",
      "source_sections": ["## 1. Core"],
      "tasks": [
        {
          "id": "setup",
          "title": "Initial setup",
          "source_sections": ["### 1.1 Setup"]
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 5,
    "mapped_sections": 2,
    "unmapped": ["### 1.2 Configuration", "### 1.3 Testing"],
    "context_only": ["# Title"]
  }
}
EOF
    echo "$plan_file"
}

# Create a plan with circular dependencies (should fail)
create_circular_plan() {
    local plan_file="${1:-${REPO}/plan.json}"
    cat > "$plan_file" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "cyc",
  "epics": [
    {
      "id": "core",
      "title": "Core",
      "source_sections": ["## 1. Core"],
      "tasks": [
        {
          "id": "a",
          "title": "Task A",
          "source_sections": ["### 1.1 A"],
          "depends_on": ["b"]
        },
        {
          "id": "b",
          "title": "Task B",
          "source_sections": ["### 1.2 B"],
          "depends_on": ["a"]
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 4,
    "mapped_sections": 3,
    "unmapped": [],
    "context_only": ["# Title"]
  }
}
EOF
    echo "$plan_file"
}

# Create a plan with duplicate IDs (should fail)
create_duplicate_id_plan() {
    local plan_file="${1:-${REPO}/plan.json}"
    cat > "$plan_file" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "dup",
  "epics": [
    {
      "id": "core",
      "title": "Core",
      "source_sections": ["## 1. Core"],
      "tasks": [
        {
          "id": "setup",
          "title": "First setup",
          "source_sections": ["### 1.1 Setup"]
        },
        {
          "id": "setup",
          "title": "Second setup",
          "source_sections": ["### 1.2 Setup"]
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 4,
    "mapped_sections": 3,
    "unmapped": [],
    "context_only": ["# Title"]
  }
}
EOF
    echo "$plan_file"
}

# Create a plan with atomicity violations (should warn)
create_atomicity_warning_plan() {
    local plan_file="${1:-${REPO}/plan.json}"
    # Generate a long description (> 500 chars)
    local long_desc
    long_desc=$(printf 'x%.0s' $(seq 1 550))
    cat > "$plan_file" << EOF
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "atom",
  "epics": [
    {
      "id": "core",
      "title": "Core",
      "source_sections": ["## 1. Core"],
      "tasks": [
        {
          "id": "too-big",
          "title": "Overly large task",
          "description": "${long_desc}",
          "estimate_minutes": 180,
          "source_sections": ["### 1.1 A", "### 1.2 B", "### 1.3 C", "### 1.4 D"]
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 6,
    "mapped_sections": 5,
    "unmapped": [],
    "context_only": ["# Title"]
  }
}
EOF
    echo "$plan_file"
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
