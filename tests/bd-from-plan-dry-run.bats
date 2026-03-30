#!/usr/bin/env bats
# Tests for dry-run mode output

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

# --- Dry Run Mode ---

@test "dry-run shows epic creation without creating" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "[dry-run]"
    assert_output_contains "bd create --type epic"
    assert_output_contains "DRY RUN"
}

@test "dry-run shows task creation without creating" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "[dry-run]"
    assert_output_contains "bd create --type feature"
    assert_output_contains "rename to"
}

@test "dry-run shows dependency wiring" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "bd dep add"
}

@test "dry-run shows coverage report" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Coverage Report"
    assert_output_contains "Total sections:"
    assert_output_contains "Status: PASS"
}

@test "dry-run shows total estimate" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Total estimate:"
    # 10m + 15m = 0h 25m
    assert_output_contains "0h 25m"
}

@test "dry-run shows task estimates" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "estimate: 10m"
}

@test "dry-run shows priority in task output" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "[P1]"
}

@test "dry-run does not call bd create" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    # We can verify this by checking no beads are actually created
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    # bd list should return nothing (or empty)
    local count
    count=$(bd count 2>/dev/null || echo "0")
    [ "$count" = "0" ] || [ "$count" = "" ]
}
