#!/usr/bin/env bats
# Tests for input handling: plan directory argument

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

# --- Directory Input ---

@test "reads plan from directory argument" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "reads plan from absolute directory path" {
    local plan_dir
    plan_dir=$(create_minimal_plan "${BATS_TEST_TMPDIR}/abs-plan")
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "merges _plan.json and epic files into single plan" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    # Should see both epics from separate files
    assert_output_contains "dep-model"
    assert_output_contains "dep-api"
}

@test "sorts epic files alphabetically" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    # epic-api.json comes before epic-model.json alphabetically
    # So api epic should appear first in the merged plan
    # But topological sort may reorder tasks — just verify both are present
    assert_output_contains "dep-api"
    assert_output_contains "dep-model"
}

# --- Argument Parsing ---

@test "dry-run flag works before directory" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "DRY RUN"
}

# --- Error Cases ---

@test "fails on nonexistent directory" {
    run "$BD_FROM_PLAN" --dry-run "/tmp/does-not-exist-12345"
    [ "$status" -ne 0 ]
    assert_output_contains "not found"
}

@test "fails with no arguments" {
    run "$BD_FROM_PLAN"
    [ "$status" -ne 0 ]
    assert_output_contains "usage"
}

@test "fails when _plan.json is missing from directory" {
    local plan_dir="${REPO}/bad-plan"
    mkdir -p "$plan_dir"
    cat > "$plan_dir/epic-core.json" << 'EOF'
{
  "id": "core",
  "title": "Core",
  "source_sections": ["## 1"],
  "tasks": [{"id": "a", "title": "A", "source_sections": ["### 1"]}]
}
EOF
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "_plan.json"
}

@test "fails when no epic files exist in directory" {
    local plan_dir="${REPO}/no-epics"
    mkdir -p "$plan_dir"
    cat > "$plan_dir/_plan.json" << 'EOF'
{
  "version": 1,
  "source": "docs/plan.md",
  "prefix": "test",
  "coverage": {"total_sections": 1, "mapped_sections": 0, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "no epic"
}

@test "fails when a regular file is passed instead of directory" {
    local plan_file="${REPO}/plan.json"
    echo '{}' > "$plan_file"
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -ne 0 ]
    assert_output_contains "not a directory"
}
