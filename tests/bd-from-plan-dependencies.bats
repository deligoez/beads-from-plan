#!/usr/bin/env bats
# Tests for dependency resolution, cycle detection, and topological sorting

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

# --- Cycle Detection ---

@test "detects simple circular dependency (A->B->A)" {
    local plan_file
    plan_file=$(create_circular_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -ne 0 ]
    assert_output_contains "circular dependency"
}

@test "passes with no circular dependencies" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "No circular dependencies"
}

# --- Topological Order ---

@test "tasks appear in dependency order (dry-run)" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]

    # user should appear before token (token depends on user)
    local user_pos token_pos
    user_pos=$(echo "$output" | grep -n "dep-model-user" | head -1 | cut -d: -f1)
    token_pos=$(echo "$output" | grep -n "dep-model-token" | head -1 | cut -d: -f1)
    [ "$user_pos" -lt "$token_pos" ]
}

@test "cross-epic dependencies appear in order (dry-run)" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]

    # model-user should appear before api-login (login depends on model-user)
    local model_pos api_pos
    model_pos=$(echo "$output" | grep -n "dep-model-user" | head -1 | cut -d: -f1)
    api_pos=$(echo "$output" | grep -n "dep-api-login" | head -1 | cut -d: -f1)
    [ "$model_pos" -lt "$api_pos" ]
}

# --- Same-Epic Dependency Resolution ---

@test "resolves same-epic dependency without prefix" {
    # In dependency_plan, token depends on "user" (no epic prefix)
    # Should resolve to model-user within same epic
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "dep-model-token"
    assert_output_contains "dep-model-user"
}

# --- Cross-Epic Dependency Resolution ---

@test "resolves cross-epic dependency with epic prefix" {
    # In dependency_plan, login depends on "model-user" and "model-token"
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "dep-api-login"
    assert_output_contains "deps: model-user, model-token"
}

# --- No Dependencies ---

@test "handles tasks with no dependencies" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "no dependencies to wire"
}

# --- Dependency Wiring in Dry Run ---

@test "shows dependency wiring commands in dry-run" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "bd dep add"
}

# --- Duplicate IDs ---

@test "rejects duplicate task IDs" {
    local plan_file
    plan_file=$(create_duplicate_id_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -ne 0 ]
    assert_output_contains "duplicate task IDs"
}
