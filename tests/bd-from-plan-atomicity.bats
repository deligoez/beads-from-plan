#!/usr/bin/env bats
# Tests for atomicity validation warnings

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

# --- Atomicity Warnings ---

@test "warns when task estimate exceeds 120 minutes" {
    cat > "${REPO}/big-task.json" << 'EOF'
{
  "prefix": "big",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "huge",
      "title": "Huge task",
      "source_sections": ["### 1.1"],
      "estimate_minutes": 240
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/big-task.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "exceeds 120m"
    assert_output_contains "split this task"
}

@test "warns when task maps to more than 3 sections" {
    cat > "${REPO}/multi-section.json" << 'EOF'
{
  "prefix": "ms",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "wide",
      "title": "Wide task",
      "source_sections": ["### 1.1", "### 1.2", "### 1.3", "### 1.4"]
    }]
  }],
  "coverage": {"total_sections": 6, "mapped_sections": 5, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/multi-section.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "4 sections"
    assert_output_contains "multiple concerns"
}

@test "warns when task description exceeds 500 chars" {
    local long_desc
    long_desc=$(printf 'x%.0s' $(seq 1 550))
    cat > "${REPO}/long-desc.json" << EOF
{
  "prefix": "ld",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "verbose",
      "title": "Verbose task",
      "description": "${long_desc}",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/long-desc.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "scope may be too broad"
}

@test "all three atomicity warnings fire together" {
    local plan_file
    plan_file=$(create_atomicity_warning_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY WARNINGS"
    assert_output_contains "exceeds 120m"
    assert_output_contains "4 sections"
    assert_output_contains "scope may be too broad"
}

@test "no atomicity warnings for well-sized tasks" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
}

@test "atomicity warnings are non-fatal (plan still processes)" {
    cat > "${REPO}/atom-nonfatal.json" << 'EOF'
{
  "prefix": "nf",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "big",
      "title": "Big task",
      "source_sections": ["### 1.1"],
      "estimate_minutes": 300
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/atom-nonfatal.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    # But plan still processes
    assert_output_contains "DRY RUN COMPLETE"
}
