#!/usr/bin/env bats
# Tests for dry-run mode output

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

# --- Dry Run Mode ---

@test "dry-run shows epic creation without creating" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "[dry-run]"
    assert_output_contains "bd create --type epic"
    assert_output_contains "DRY RUN"
}

@test "dry-run shows task creation without creating" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "[dry-run]"
    assert_output_contains "bd create --type feature"
    assert_output_contains "rename to"
}

@test "dry-run shows dependency wiring" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "bd dep add"
}

@test "dry-run shows coverage report" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Coverage Report"
    assert_output_contains "Total sections:"
    assert_output_contains "Status: PASS"
}

@test "dry-run shows total estimate" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Total estimate:"
    # 45m + 90m = 2h 15m
    assert_output_contains "2h 15m"
}

@test "dry-run shows task estimates" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "estimate: 45m"
    assert_output_contains "estimate: 90m"
}

@test "dry-run shows priority in task output" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "[P1]"
}

@test "dry-run does not call bd create" {
    local plan_file
    plan_file=$(create_minimal_plan)
    # We can verify this by checking no beads are actually created
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    # bd list should return nothing (or empty)
    local count
    count=$(bd count 2>/dev/null || echo "0")
    [ "$count" = "0" ] || [ "$count" = "" ]
}

# --- Stdin Mode ---

@test "accepts plan from stdin" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run bash -c "cat '$plan_file' | '$BD_FROM_PLAN' --dry-run --stdin"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
    assert_output_contains "DRY RUN"
}

@test "accepts plan from stdin with pipe" {
    run bash -c "echo '{\"epics\":[{\"id\":\"a\",\"title\":\"A\",\"source_sections\":[\"## 1\"],\"tasks\":[{\"id\":\"t\",\"title\":\"T\",\"source_sections\":[\"### 1\"]}]}],\"coverage\":{\"total_sections\":3,\"mapped_sections\":2,\"unmapped\":[],\"context_only\":[\"# X\"]}}' | '$BD_FROM_PLAN' --dry-run --stdin"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}
