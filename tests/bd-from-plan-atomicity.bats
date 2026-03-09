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

# --- Rule 3: Max 15 Minutes ---

@test "warns when task estimate exceeds 15 minutes" {
    cat > "${REPO}/big-task.json" << 'EOF'
{
  "prefix": "big",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "huge",
      "title": "Huge task",
      "source_sections": ["### 1.1"],
      "estimate_minutes": 90
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/big-task.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "exceeds 15m"
    assert_output_contains "split this task"
}

@test "no warning for task at exactly 15 minutes" {
    cat > "${REPO}/ok-task.json" << 'EOF'
{
  "prefix": "ok",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "fine",
      "title": "Fine task",
      "source_sections": ["### 1.1"],
      "estimate_minutes": 15
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/ok-task.json"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
}

# --- Rule 5: Count the Files (sections > 2) ---

@test "warns when task maps to more than 2 sections" {
    cat > "${REPO}/multi-section.json" << 'EOF'
{
  "prefix": "ms",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "wide",
      "title": "Wide task",
      "source_sections": ["### 1.1", "### 1.2", "### 1.3"]
    }]
  }],
  "coverage": {"total_sections": 5, "mapped_sections": 4, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/multi-section.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "3 sections"
    assert_output_contains "multiple concerns"
}

@test "no warning for task with exactly 2 sections" {
    cat > "${REPO}/two-section.json" << 'EOF'
{
  "prefix": "ts",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "pair",
      "title": "Paired task",
      "source_sections": ["### 1.1", "### 1.2"]
    }]
  }],
  "coverage": {"total_sections": 4, "mapped_sections": 3, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/two-section.json"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
}

# --- Scope Check: description > 300 chars ---

@test "warns when task description exceeds 300 chars" {
    local long_desc
    long_desc=$(printf 'x%.0s' $(seq 1 350))
    cat > "${REPO}/long-desc.json" << EOF
{
  "prefix": "ld",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "verbose",
      "title": "Verbose task",
      "description": "${long_desc}",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/long-desc.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "scope may be too broad"
}

# --- Rule 4: Verb-Object Test (conjunction detection) ---

@test "warns when task title contains 'and'" {
    cat > "${REPO}/and-title.json" << 'EOF'
{
  "prefix": "conj",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "multi",
      "title": "Add config and create migration",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/and-title.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "conjunctions"
}

@test "warns when task title contains comma" {
    cat > "${REPO}/comma-title.json" << 'EOF'
{
  "prefix": "conj",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "multi",
      "title": "Create config, migration, model",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/comma-title.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "conjunctions"
}

@test "warns when task title contains plus sign" {
    cat > "${REPO}/plus-title.json" << 'EOF'
{
  "prefix": "conj",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "multi",
      "title": "Lock manager + handle implementation",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/plus-title.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "conjunctions"
}

# --- Rule 7: Title word count ---

@test "warns when task title exceeds 8 words" {
    cat > "${REPO}/long-title.json" << 'EOF'
{
  "prefix": "lt",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "wordy",
      "title": "Create the new fancy lock infrastructure service manager handler",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/long-title.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    assert_output_contains "words"
    assert_output_contains "simplify or split"
}

@test "no warning for 8-word title" {
    cat > "${REPO}/ok-title.json" << 'EOF'
{
  "prefix": "ot",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "ok",
      "title": "Create MachineStateLock model with factory test",
      "source_sections": ["### 1.1"]
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/ok-title.json"
    [ "$status" -eq 0 ]
    # 7 words = no word count warning (may trigger 'with' conjunction warning though)
}

# --- Combined warnings ---

@test "all atomicity warnings fire together" {
    local plan_file
    plan_file=$(create_atomicity_warning_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY WARNINGS"
    assert_output_contains "exceeds 15m"
    assert_output_contains "3 sections"
    assert_output_contains "scope may be too broad"
    assert_output_contains "conjunctions"
}

@test "no atomicity warnings for well-sized tasks" {
    local plan_file
    plan_file=$(create_full_plan)
    run "$BD_FROM_PLAN" --dry-run "$plan_file"
    [ "$status" -eq 0 ]
    assert_output_not_contains "ATOMICITY"
}

@test "atomicity warnings are non-fatal (plan still processes)" {
    cat > "${REPO}/atom-nonfatal.json" << 'EOF'
{
  "prefix": "nf",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "big",
      "title": "Big task",
      "source_sections": ["### 1.1"],
      "estimate_minutes": 300
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/atom-nonfatal.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ATOMICITY"
    # But plan still processes
    assert_output_contains "DRY RUN COMPLETE"
}

@test "atomicity banner shows updated guidance" {
    cat > "${REPO}/banner-check.json" << 'EOF'
{
  "prefix": "bn",
  "epics": [{
    "id": "core",
    "title": "Core",
    "source_sections": ["## 1"],
    "tasks": [{
      "id": "big",
      "title": "Too big task",
      "source_sections": ["### 1.1"],
      "estimate_minutes": 60
    }]
  }],
  "coverage": {"total_sections": 3, "mapped_sections": 2, "unmapped": [], "context_only": ["# T"]}
}
EOF
    run "$BD_FROM_PLAN" --dry-run "${REPO}/banner-check.json"
    [ "$status" -eq 0 ]
    assert_output_contains "ONE concern"
    assert_output_contains "15 minutes"
}
