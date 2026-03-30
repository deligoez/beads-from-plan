#!/usr/bin/env bats
# Tests for bd-from-plan JSON validation

load 'helpers/bd-test-helper'

setup_file() {
    init_shared_repo
}

setup() {
    cd "$REPO"
}

teardown_file() {
    teardown_repo
}

# --- Helper: create a plan dir from inline _plan.json and epic-core.json ---
# Usage: create_inline_plan "$plan_json" "$epic_json"
# Both arguments are the JSON content strings.
# Returns plan directory path.
create_inline_plan() {
    local plan_json="$1"
    local epic_json="$2"
    local plan_dir="${REPO}/inline-plan-$$-${RANDOM}"
    mkdir -p "$plan_dir"
    echo "$plan_json" > "$plan_dir/_plan.json"
    if [ -n "$epic_json" ]; then
        echo "$epic_json" > "$plan_dir/epic-core.json"
    fi
    echo "$plan_dir"
}

# --- Valid Plans ---

@test "validates minimal valid plan" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "validates plan with dependencies" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "validates full plan with all fields" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

# --- Invalid JSON ---

@test "rejects invalid JSON in epic file" {
    local plan_dir="${REPO}/bad-json-plan"
    mkdir -p "$plan_dir"
    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "test",
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    echo "not json" > "$plan_dir/epic-core.json"
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "invalid JSON"
}

@test "rejects empty JSON object in epic file" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"source":"docs/plan.md","prefix":"test","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "missing"
}

@test "rejects plan with empty epics (no epic files)" {
    local plan_dir="${REPO}/no-epic-files"
    mkdir -p "$plan_dir"
    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "coverage": {"total_sections": 0, "mapped_sections": 0, "unmapped": []}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "no epic"
}

# --- Missing Required Fields ---

@test "rejects epic without id" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"prefix":"test","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"title": "Test", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty id"
}

@test "rejects epic without title" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"prefix":"test","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id": "core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty title"
}

@test "rejects epic without source_sections" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"prefix":"test","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id": "core", "title": "Core", "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty source_sections"
}

@test "rejects epic without tasks" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"prefix":"test","coverage":{"total_sections":2,"mapped_sections":1,"unmapped":[],"context_only":["# T"]}}' \
        '{"id": "core", "title": "Core", "source_sections": ["## 1"]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty tasks"
}

@test "rejects task without source_sections" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"prefix":"test","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id": "core", "title": "Core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A"}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "missing or empty source_sections"
}

# --- Coverage Validation ---

@test "rejects plan with unmapped sections" {
    local plan_dir
    plan_dir=$(create_unmapped_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "unmapped sections found"
    assert_output_contains "### 1.2 Configuration"
    assert_output_contains "### 1.3 Testing"
}

@test "rejects coverage where mapped exceeds total" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"prefix":"test","coverage":{"total_sections":2,"mapped_sections":5,"unmapped":[]}}' \
        '{"id": "core", "title": "Core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "exceeds total_sections"
}

# --- Missing coverage object ---

@test "rejects plan without coverage" {
    local plan_dir
    plan_dir=$(create_inline_plan \
        '{"version":1,"prefix":"test"}' \
        '{"id": "core", "title": "Core", "source_sections": ["## 1"], "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "missing coverage"
}

# --- Directory Not Found ---

@test "rejects missing plan directory" {
    run "$BD_FROM_PLAN" --dry-run "/tmp/nonexistent-plan-12345"
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
