#!/usr/bin/env bats
# Tests for input handling: files, stdin, arguments

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

teardown() {
    teardown_repo
}

# --- File Input ---

@test "reads plan from file argument" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "reads plan from absolute path" {
    local plan_file
    plan_file=$(create_minimal_plan "${BATS_TEST_TMPDIR}/abs-plan.json")
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

# --- Stdin Input ---

@test "reads plan from stdin with --stdin flag" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run bash -c "cat '$plan_file' | '$BD_FROM_PLAN' --dry-run --stdin"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

@test "stdin works with piped echo" {
    run bash -c "echo '{\"epics\":[{\"id\":\"x\",\"title\":\"X\",\"source_sections\":[\"## 1\"],\"tasks\":[{\"id\":\"y\",\"title\":\"Y\",\"source_sections\":[\"### 1\"]}]}],\"coverage\":{\"total_sections\":3,\"mapped_sections\":2,\"unmapped\":[],\"context_only\":[\"# T\"]}}' | '$BD_FROM_PLAN' --dry-run --stdin"
    [ "$status" -eq 0 ]
}

# --- Argument Parsing ---

@test "dry-run flag works before file" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "DRY RUN"
}

@test "dry-run flag works with stdin" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run bash -c "cat '$plan_file' | '$BD_FROM_PLAN' --dry-run --stdin"
    [ "$status" -eq 0 ]
    assert_output_contains "DRY RUN"
}

# --- Error Cases ---

@test "fails on nonexistent file" {
    run "$BD_FROM_PLAN" --dry-run "/tmp/does-not-exist-12345.json"
    [ "$status" -ne 0 ]
    assert_output_contains "not found"
}

@test "fails with no arguments" {
    run "$BD_FROM_PLAN"
    [ "$status" -ne 0 ]
    assert_output_contains "usage"
}

@test "fails on empty stdin" {
    run bash -c "echo '' | '$BD_FROM_PLAN' --dry-run --stdin"
    [ "$status" -ne 0 ]
}
