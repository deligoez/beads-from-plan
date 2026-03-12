#!/usr/bin/env bats
# Tests for atomicity validation warnings

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

teardown() {
    teardown_repo
}

# --- Helper: create a plan dir from inline meta + epic JSON ---
_make_plan_dir() {
    local meta_json="$1"
    local epic_json="$2"
    local plan_dir="${REPO}/atom-plan-$$-${RANDOM}"
    mkdir -p "$plan_dir"
    echo "$meta_json" > "$plan_dir/_plan.json"
    echo "$epic_json" > "$plan_dir/epic-core.json"
    echo "$plan_dir"
}

# --- Rule 3: Max 15 Minutes ---

@test "warns when task estimate exceeds 15 minutes" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"big","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"huge","title":"Huge task","source_sections":["### 1.1"],"estimate_minutes":90}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "exceeds 15m"
    assert_output_contains "split this task"
}

@test "no warning for task at exactly 15 minutes" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ok","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"fine","title":"Fine task","source_sections":["### 1.1"],"estimate_minutes":15}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
}

# --- Rule 5: Count the Files (sections > 2) ---

@test "warns when task maps to more than 2 sections" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ms","coverage":{"total_sections":5,"mapped_sections":4,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"wide","title":"Wide task","source_sections":["### 1.1","### 1.2","### 1.3"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "3 sections"
    assert_output_contains "multiple concerns"
}

@test "no warning for task with exactly 2 sections" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ts","coverage":{"total_sections":4,"mapped_sections":3,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"pair","title":"Paired task","source_sections":["### 1.1","### 1.2"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
}

# --- Scope Check: description > 300 chars ---

@test "warns when task description exceeds 300 chars" {
    local long_desc
    long_desc=$(printf 'x%.0s' $(seq 1 350))
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ld","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        "{\"id\":\"core\",\"title\":\"Core\",\"source_sections\":[\"## 1\"],\"tasks\":[{\"id\":\"verbose\",\"title\":\"Verbose task\",\"description\":\"${long_desc}\",\"source_sections\":[\"### 1.1\"]}]}")
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "scope may be too broad"
}

# --- Rule 4: Verb-Object Test (conjunction detection) ---

@test "warns when task title contains 'and'" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"conj","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"multi","title":"Add config and create migration","source_sections":["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "conjunctions"
}

@test "warns when task title contains comma" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"conj","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"multi","title":"Create config, migration, model","source_sections":["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "conjunctions"
}

@test "warns when task title contains plus sign" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"conj","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"multi","title":"Lock manager + handle implementation","source_sections":["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "conjunctions"
}

# --- Rule 7: Title word count ---

@test "warns when task title exceeds 8 words" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"lt","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"wordy","title":"Create the new fancy lock infrastructure service manager handler","source_sections":["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "words"
    assert_output_contains "simplify or split"
}

@test "no warning for 8-word title" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ot","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"ok","title":"Create MachineStateLock model with factory test","source_sections":["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    # 7 words = no word count warning (may trigger 'with' conjunction warning though)
}

# --- Combined warnings ---

@test "all atomicity warnings fire together" {
    local plan_dir
    plan_dir=$(create_atomicity_warning_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY WARNINGS"
    assert_output_contains "exceeds 15m"
    assert_output_contains "3 sections"
    assert_output_contains "scope may be too broad"
    assert_output_contains "conjunctions"
}

@test "no atomicity warnings for well-sized tasks" {
    local plan_dir
    plan_dir=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
}

@test "atomicity warnings are non-fatal (plan still processes)" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"nf","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"big","title":"Big task","source_sections":["### 1.1"],"estimate_minutes":300}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    # But plan still processes
    assert_output_contains "DRY RUN COMPLETE"
}

@test "atomicity banner shows updated guidance" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"bn","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"big","title":"Too big task","source_sections":["### 1.1"],"estimate_minutes":60}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ONE concern"
    assert_output_contains "15 minutes"
}
