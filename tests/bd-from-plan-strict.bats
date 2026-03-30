#!/usr/bin/env bats
# Tests for --strict, --validate, --stats modes, acceptance criteria check,
# estimate_minutes required, and parallelism report

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

# --- Helper: create a plan dir from inline meta + epic JSON ---
_make_plan_dir() {
    local meta_json="$1"
    local epic_json="$2"
    local plan_dir="${REPO}/strict-plan-$$-${RANDOM}"
    mkdir -p "$plan_dir"
    echo "$meta_json" > "$plan_dir/_plan.json"
    echo "$epic_json" > "$plan_dir/epic-core.json"
    echo "$plan_dir"
}

# === --strict mode ===

@test "strict mode rejects plan with atomicity violations" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"s","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"big","title":"Add config and create migration","source_sections":["### 1.1"],"estimate_minutes":30}]}')
    run "$BD_FROM_PLAN" --strict --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "ATOMICITY ERRORS"
    assert_output_contains "--strict mode"
    assert_output_contains "REJECTED"
}

@test "strict mode passes clean plan" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --strict --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
    assert_output_contains "DRY RUN COMPLETE"
}

@test "strict mode counts violations" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"sv","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"bad","title":"Create config and migration and model","source_sections":["### 1.1"],"estimate_minutes":45}]}')
    run "$BD_FROM_PLAN" --strict --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "violation(s)"
}

@test "non-strict mode shows hint about --strict" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ns","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"big","title":"Huge task","source_sections":["### 1.1"],"estimate_minutes":60}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "--strict"
}

# === --validate mode ===

@test "validate mode passes valid plan" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --validate "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "VALIDATION: PASS"
}

@test "validate mode fails plan with unmapped sections" {
    local plan_dir
    plan_dir=$(create_unmapped_plan)
    run "$BD_FROM_PLAN" --validate "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "unmapped sections"
}

@test "validate mode does not require bd init" {
    # Create a temp directory WITHOUT bd init
    local temp_repo="${BATS_TEST_TMPDIR}/no-bd-repo"
    mkdir -p "$temp_repo"
    cd "$temp_repo"
    git init --quiet
    git config user.email "t@t.com"
    git config user.name "T"
    echo x > README.md
    git add . && git commit -qm "init"
    # DON'T init bd

    local plan_dir="${temp_repo}/plan"
    mkdir -p "$plan_dir"
    cat > "$plan_dir/_plan.json" << 'EOF'
{"version":1,"source":"docs/plan.md","prefix":"v","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}
EOF
    cat > "$plan_dir/epic-core.json" << 'EOF'
{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"a","title":"Task A","source_sections":["### 1.1"],"estimate_minutes":10}]}
EOF

    run "$BD_FROM_PLAN" --validate "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "VALIDATION: PASS"
}

@test "validate mode shows atomicity violation count" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"va","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"big","title":"Big task","source_sections":["### 1.1"],"estimate_minutes":30}]}')
    run "$BD_FROM_PLAN" --validate "$plan_dir"
    # Atomicity is warning-level in validate mode (without --strict), so PASS
    [ "$status" -eq 0 ]
    assert_output_contains "Atomicity:"
    assert_output_contains "warning"
    assert_output_contains "VALIDATION: PASS"
}

# === --stats mode ===

@test "stats mode shows full statistics with parallelism" {
    local plan_dir
    plan_dir=$(create_large_plan)
    run "$BD_FROM_PLAN" --stats "$plan_dir"
    [ "$status" -eq 0 ]

    # Basic stats
    assert_output_contains "Plan Statistics"
    assert_output_contains "Epics:"
    assert_output_contains "Tasks:"
    assert_output_contains "Estimates:"

    # Per-epic breakdown
    assert_output_contains "Per-Epic Breakdown"
    assert_output_contains "core:"
    assert_output_contains "docs:"

    # Parallelism analysis
    assert_output_contains "Parallelism Analysis"
    assert_output_contains "Parallelism levels:"
    assert_output_contains "Max parallel tasks:"
    assert_output_contains "Critical path:"
    assert_output_contains "Speedup potential:"
    assert_output_contains "Level 0:"
    assert_output_contains "Level 1:"
}

@test "stats mode does not create anything" {
    local plan_dir
    plan_dir=$(create_minimal_plan)
    run "$BD_FROM_PLAN" --stats "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_not_contains "Created"
    assert_output_not_contains "bd create"
}

# === estimate_minutes required ===

@test "rejects task without estimate_minutes" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ne","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"a","title":"Task","source_sections":["### 1.1"]}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "estimate_minutes"
}

@test "rejects task with zero estimate_minutes" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ze","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"a","title":"Task","source_sections":["### 1.1"],"estimate_minutes":0}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "estimate_minutes"
}

@test "rejects task with negative estimate_minutes" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ng","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"a","title":"Task","source_sections":["### 1.1"],"estimate_minutes":-5}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "estimate_minutes"
}

@test "accepts task with valid estimate_minutes" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ok","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"a","title":"Task","source_sections":["### 1.1"],"estimate_minutes":10}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
}

# === Acceptance criteria count (Rule 6) ===

@test "warns when acceptance has more than 3 checkpoints" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ac","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"multi","title":"Multi task","source_sections":["### 1.1"],"estimate_minutes":10,"acceptance":"Manager acquires locks. Handle releases locks. Stale locks self-healed. Migration is publishable."}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "checkpoints"
}

@test "no warning for acceptance with 3 or fewer checkpoints" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"ac2","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"ok","title":"Simple task","source_sections":["### 1.1"],"estimate_minutes":10,"acceptance":"Model exists. Migration runs. Tests pass."}]}')
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_not_contains "checkpoints"
}

@test "strict mode rejects acceptance with too many checkpoints" {
    local plan_dir
    plan_dir=$(_make_plan_dir \
        '{"version":1,"prefix":"acs","coverage":{"total_sections":3,"mapped_sections":2,"unmapped":[],"context_only":["# T"]}}' \
        '{"id":"core","title":"Core","source_sections":["## 1"],"tasks":[{"id":"multi","title":"Multi task","source_sections":["### 1.1"],"estimate_minutes":10,"acceptance":"A works. B works. C works. D works. E works."}]}')
    run "$BD_FROM_PLAN" --strict --dry-run "$plan_dir"
    [ "$status" -ne 0 ]
    assert_output_contains "ATOMICITY ERRORS"
}

# === Parallelism report in execution ===

@test "parallelism report shown after plan execution" {
    local plan_dir
    plan_dir=$(create_dependency_plan)
    run "$BD_FROM_PLAN" "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Parallelism Analysis"
    assert_output_contains "Parallelism levels:"
}

@test "parallelism report shown in dry-run" {
    local plan_dir
    plan_dir=$(create_large_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_dir"
    [ "$status" -eq 0 ]
    assert_output_contains "Parallelism Analysis"
    assert_output_contains "Speedup potential:"
}

# === Help text ===

@test "help shows all new options" {
    run "$BD_FROM_PLAN" --help
    [ "$status" -eq 0 ]
    assert_output_contains "--strict"
    assert_output_contains "--validate"
    assert_output_contains "--stats"
}
