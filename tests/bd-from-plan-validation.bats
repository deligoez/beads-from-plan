#!/usr/bin/env bats
# Tests for bd-from-plan JSON validation

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

teardown() {
    teardown_repo
}

# --- Valid Plans ---

@test "validates minimal valid plan" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "validates plan with dependencies" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "validates full plan with all fields" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

# --- Invalid JSON ---

@test "rejects invalid JSON" {
    echo "not json" > "${REPO}/bad.json"
    run "$BD_FROM_PLAN" --dry-run "${REPO}/bad.json"
    [ "$status" -ne 0 ]
    assert_output_contains "invalid JSON"
}

@test "rejects empty JSON object" {
    echo '{}' > "${REPO}/empty.json"
    run "$BD_FROM_PLAN" --dry-run "${REPO}/empty.json"
    [ "$status" -ne 0 ]
    assert_output_contains "missing"
}

@test "rejects plan with empty epics array" {
    cat > "${REPO}/empty-epics.json" << 'EOF'
{
  "epics": [],
  "coverage": {"total_sections": 0, "mapped_sections": 0, "unmapped": []}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/empty-epics.json"
    [ "$status" -ne 0 ]
    assert_output_contains "no epics"
}

# --- Missing Required Fields ---

@test "rejects epic without id" {
    cat > "${REPO}/no-id.json" << 'EOF'
{
  "epics": [{"title": "Test", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/no-id.json"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty id"
}

@test "rejects epic without title" {
    cat > "${REPO}/no-title.json" << 'EOF'
{
  "epics": [{"id": "core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/no-title.json"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty title"
}

@test "rejects epic without source_sections" {
    cat > "${REPO}/no-sections.json" << 'EOF'
{
  "epics": [{"id": "core", "title": "Core", "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/no-sections.json"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty source_sections"
}

@test "rejects epic without tasks" {
    cat > "${REPO}/no-tasks.json" << 'EOF'
{
  "epics": [{"id": "core", "title": "Core", "source_sections": ["## 1"]}],
  "coverage": {"total_sections": 2, "mapped_sections": 1, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/no-tasks.json"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty tasks"
}

@test "rejects task without source_sections" {
    cat > "${REPO}/task-no-sections.json" << 'EOF'
{
  "epics": [{"id": "core", "title": "Core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A"}]}],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/task-no-sections.json"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty source_sections"
}

# --- Coverage Validation ---

@test "rejects plan with unmapped sections" {
    local plan_file
    plan_file=$(create_unmapped_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -ne 0 ]
    assert_output_contains "unmapped sections found"
    assert_output_contains "### 1.2 Configuration"
    assert_output_contains "### 1.3 Testing"
}

@test "rejects coverage where mapped exceeds total" {
    cat > "${REPO}/bad-coverage.json" << 'EOF'
{
  "epics": [{"id": "core", "title": "Core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}],
  "coverage": {"total_sections": 2, "mapped_sections": 5, "unmapped": []}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/bad-coverage.json"
    [ "$status" -ne 0 ]
    assert_output_contains "exceeds total_sections"
}

# --- Missing coverage object ---

@test "rejects plan without coverage" {
    cat > "${REPO}/no-coverage.json" << 'EOF'
{
  "epics": [{"id": "core", "title": "Core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}]
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/no-coverage.json"
    [ "$status" -ne 0 ]
    assert_output_contains "missing coverage"
}

# --- File Not Found ---

@test "rejects missing plan file" {
    run "$BD_FROM_PLAN" --dry-run "/tmp/nonexistent-plan-12345.json"
    [ "$status" -ne 0 ]
    assert_output_contains "not found"
}

# --- No Arguments ---

@test "shows usage when no arguments" {
    run "$BD_FROM_PLAN"
    [ "$status" -ne 0 ]
    assert_output_contains "usage"
}

# --- Help Flag ---

@test "shows help with -h" {
    run "$BD_FROM_PLAN" -h
    [ "$status" -eq 0 ]
    assert_output_contains "Usage"
    assert_output_contains "dry-run"
}

@test "shows help with --help" {
    run "$BD_FROM_PLAN" --help
    [ "$status" -eq 0 ]
    assert_output_contains "Usage"
}
