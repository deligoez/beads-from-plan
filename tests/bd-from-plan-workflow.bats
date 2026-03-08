#!/usr/bin/env bats
# Tests for workflow defaults, checklist notes, and bd close reminder

load 'helpers/bd-test-helper'

setup() {
    setup_git_env
    init_repo
}

# --- Workflow Inheritance ---

@test "task inherits quality gate from workflow when not overridden" {
    cat > "${REPO}/wf.json" << 'EOF'
{
  "prefix": "wf",
  "workflow": {
    "quality_gate": "composer lint && composer test",
    "commit_strategy": "conventional"
  },
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "task1",
      "title": "Task without own gate",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" "${REPO}/wf.json"
    [ "$status" -eq 0 ]
    assert_output_contains "Created task:"

    # Check the task description contains inherited quality gate command
    local task_id="${BD_PREFIX}-wf-core-task1"
    local desc
    desc=$(bd show "$task_id" 2>/dev/null)
    [[ "$desc" == *"Quality Gate"* ]]
    [[ "$desc" == *"composer lint && composer test"* ]]
}

@test "task-level quality gate overrides workflow default" {
    cat > "${REPO}/override.json" << 'EOF'
{
  "prefix": "ov",
  "workflow": {
    "quality_gate": "composer lint && composer test && composer type"
  },
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "docs",
      "title": "Write docs",
      "source_sections": ["### 1.1"],
      "quality_gate": "composer lint"
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" "${REPO}/override.json"
    [ "$status" -eq 0 ]

    local task_id="${BD_PREFIX}-ov-core-docs"
    local desc
    desc=$(bd show "$task_id" 2>/dev/null)
    # Should have only "composer lint" (task override), not the full workflow gate
    [[ "$desc" == *"composer lint"* ]]
    [[ "$desc" != *"composer type"* ]]
}

@test "task inherits commit strategy from workflow" {
    cat > "${REPO}/cs.json" << 'EOF'
{
  "prefix": "cs",
  "workflow": {
    "commit_strategy": "conventional"
  },
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "task1",
      "title": "Task",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" "${REPO}/cs.json"
    [ "$status" -eq 0 ]

    local task_id="${BD_PREFIX}-cs-core-task1"
    local desc
    desc=$(bd show "$task_id" 2>/dev/null)
    [[ "$desc" == *"Commit Strategy: conventional"* ]]
}

# --- Checklist Note ---

@test "checklist_note is appended to task description" {
    cat > "${REPO}/cl.json" << 'EOF'
{
  "prefix": "cl",
  "workflow": {
    "checklist_note": "- [ ] Run quality gate\n- [ ] Commit"
  },
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "task1",
      "title": "Task with checklist",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" "${REPO}/cl.json"
    [ "$status" -eq 0 ]

    local task_id="${BD_PREFIX}-cl-core-task1"
    local desc
    desc=$(bd show "$task_id" 2>/dev/null)
    [[ "$desc" == *"Checklist"* ]]
    [[ "$desc" == *"Run quality gate"* ]]
}

@test "no checklist section when workflow has no checklist_note" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" "$plan_file"
    [ "$status" -eq 0 ]

    local task_id="${BD_PREFIX}-test-core-setup"
    local desc
    desc=$(bd show "$task_id" 2>/dev/null)
    # Should not have "Checklist:" section header (no workflow.checklist_note)
    [[ "$desc" != *"Checklist:"* ]]
}

# --- BD Close Reminder ---

@test "bd close reminder is always appended to task description" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" "$plan_file"
    [ "$status" -eq 0 ]

    local task_id="${BD_PREFIX}-test-core-setup"
    local desc
    desc=$(bd show "$task_id" 2>/dev/null)
    [[ "$desc" == *"bd close"* ]]
    [[ "$desc" == *"${task_id}"* ]]
}

@test "bd close reminder includes correct task ID for each task" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" "$plan_file"
    [ "$status" -eq 0 ]

    # Check first task
    local task1="${BD_PREFIX}-dep-model-user"
    local desc1
    desc1=$(bd show "$task1" 2>/dev/null)
    [[ "$desc1" == *"bd close ${task1}"* ]]

    # Check second task
    local task2="${BD_PREFIX}-dep-model-token"
    local desc2
    desc2=$(bd show "$task2" 2>/dev/null)
    [[ "$desc2" == *"bd close ${task2}"* ]]
}

# --- BD Claim Reminder ---

@test "bd claim reminder is always appended to task description" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" "$plan_file"
    [ "$status" -eq 0 ]

    local task_id="${BD_PREFIX}-test-core-setup"
    local desc
    desc=$(bd show "$task_id" 2>/dev/null)
    [[ "$desc" == *"bd update ${task_id} --claim"* ]]
}

@test "bd claim reminder includes correct task ID for each task" {
    local plan_file
    plan_file=$(create_dependency_plan)
    run "$BD_FROM_PLAN" "$plan_file"
    [ "$status" -eq 0 ]

    local task1="${BD_PREFIX}-dep-model-user"
    local desc1
    desc1=$(bd show "$task1" 2>/dev/null)
    [[ "$desc1" == *"bd update ${task1} --claim"* ]]

    local task2="${BD_PREFIX}-dep-model-token"
    local desc2
    desc2=$(bd show "$task2" 2>/dev/null)
    [[ "$desc2" == *"bd update ${task2} --claim"* ]]
}

# --- Full Workflow in Dry Run ---

@test "dry-run shows workflow info" {
    cat > "${REPO}/dryrun-wf.json" << 'EOF'
{
  "prefix": "dr",
  "workflow": {
    "quality_gate": "npm run lint && npm run test",
    "commit_strategy": "agentic-commits",
    "checklist_note": "- [ ] Run quality gate\n- [ ] Commit"
  },
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "task1",
      "title": "Task",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/dryrun-wf.json"
    [ "$status" -eq 0 ]
    assert_output_contains "Plan structure is valid"
}

# --- Plans Without Workflow (backward compat) ---

@test "plans without workflow field still work" {
    local plan_file
    plan_file=$(create_minimal_plan)
    run "$BD_FROM_PLAN" "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "Created task:"
}
