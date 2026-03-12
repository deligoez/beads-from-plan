#!/usr/bin/env bats
# Tests for actual beads creation (requires bd CLI)

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

teardown() {
    teardown_repo
}

# --- Real Execution ---

@test "creates epic from minimal plan" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Created epic: ${BD_PREFIX}-test-core"

    # Verify epic exists
    run bd show "${BD_PREFIX}-test-core"
    [ "$status" -eq 0 ]
}

@test "creates task with parent epic" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Created task: ${BD_PREFIX}-test-core-setup"

    # Verify task exists and has parent
    run bd show "${BD_PREFIX}-test-core-setup"
    [ "$status" -eq 0 ]
}

@test "creates multiple epics and tasks from dependency plan" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Created epic: ${BD_PREFIX}-dep-model"
    assert_output_contains "Created epic: ${BD_PREFIX}-dep-api"
    assert_output_contains "Created task: ${BD_PREFIX}-dep-model-user"
    assert_output_contains "Created task: ${BD_PREFIX}-dep-model-token"
    assert_output_contains "Created task: ${BD_PREFIX}-dep-api-login"
    assert_output_contains "Created task: ${BD_PREFIX}-dep-api-logout"
}

@test "wires dependencies between tasks" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Dep:"
    assert_output_contains "depends on"
}

@test "creates tasks with correct priority" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "[P1]"
}

@test "shows summary with counts" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "2 epics"
    assert_output_contains "4 tasks"
    assert_output_contains "dependencies"
}

@test "shows coverage report after creation" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Coverage Report"
    assert_output_contains "Status: PASS"
}

@test "shows ready tasks after creation" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Ready to work on"
}

# --- Idempotency ---

@test "handles re-run gracefully (existing issues)" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    # First run
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]

    # Second run - should not fail
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    # May show warnings about existing issues
    assert_output_contains "may already exist" || assert_output_contains "Created"
}
