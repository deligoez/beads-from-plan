#!/usr/bin/env bats
# Tests for large plan handling and post-execution verification

load 'helpers/bd-test-helper'

setup_file() {
    init_template_repo
}

setup() {
    init_repo_from_template
}

teardown_file() {
    teardown_template_repo
}

# --- Large Plan: Dry Run (fast — no bd create calls) ---

@test "dry-run lists all 20 tasks from large plan" {
    local plan_dir
    plan_dir=$(create_large_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]

    # Should list all 15 core tasks
    assert_output_contains "rename to ${BD_PREFIX}-lg-core-t01"
    assert_output_contains "rename to ${BD_PREFIX}-lg-core-t08"
    assert_output_contains "rename to ${BD_PREFIX}-lg-core-t15"

    # Should list all 5 docs tasks
    assert_output_contains "rename to ${BD_PREFIX}-lg-docs-readme"
    assert_output_contains "rename to ${BD_PREFIX}-lg-docs-migration-guide"

    # Should show expected count
    assert_output_contains "Tasks in plan: 20"
    assert_output_contains "tasks after topological sort: 20"

    # Dry-run shows expected task count in summary
    assert_output_contains "Tasks previewed: 20"
}

# --- Large Plan: Real Execution (single run, all assertions) ---
# Consolidated into one test to avoid repeating 20-task creation (saves ~90s)

@test "creates all 20 tasks with deps, progress, and verification" {
    local plan_dir
    plan_dir=$(create_large_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]

    # All 20 tasks created
    assert_output_contains "20 tasks"
    assert_output_not_contains "VERIFICATION FAILED"

    # Spot-check tasks across the range (first, middle, last of large epic)
    assert_output_contains "Created task: ${BD_PREFIX}-lg-core-t01"
    assert_output_contains "Created task: ${BD_PREFIX}-lg-core-t08"
    assert_output_contains "Created task: ${BD_PREFIX}-lg-core-t15"

    # Cross-epic dependency tasks
    assert_output_contains "Created task: ${BD_PREFIX}-lg-docs-readme"
    assert_output_contains "Created task: ${BD_PREFIX}-lg-docs-migration-guide"

    # Cross-epic dependency wiring
    assert_output_contains "Dep: ${BD_PREFIX}-lg-docs-readme depends on ${BD_PREFIX}-lg-core-t08"

    # Progress counter
    assert_output_contains "[1/20]"
    assert_output_contains "[20/20]"

    # Topological sort count
    assert_output_contains "Tasks in plan: 20, tasks after topological sort: 20"
}
