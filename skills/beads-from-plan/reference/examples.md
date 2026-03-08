# Examples

## Simple Plan: Two Epics, Four Tasks

### Source Markdown

```markdown
# Order Processing System

## Overview
This plan covers the order processing pipeline.

## 1. Order Model
### 1.1 Create Order Model
Define the Order model with status, total, customer_id fields.
Create migration with proper indexes.

### 1.2 Order Status Machine
Implement state machine for order lifecycle:
pending -> confirmed -> shipped -> delivered

## 2. Payment Integration
### 2.1 Payment Gateway
Integrate Stripe payment gateway. Requires Order model to exist.

### 2.2 Payment Webhooks
Handle Stripe webhook callbacks for payment confirmation.
Depends on payment gateway integration.
```

### Resulting JSON Plan

```json
{
  "version": 1,
  "source": "docs/plans/order-processing.md",
  "prefix": "order",
  "workflow": {
    "quality_gate": "composer lint && composer test && composer type",
    "commit_strategy": "agentic-commits",
    "checklist_note": "- [ ] Run quality gate: composer lint && composer test && composer type\n- [ ] Commit using agentic-commits"
  },
  "epics": [
    {
      "id": "model",
      "title": "Order Model",
      "description": "Order model and state machine implementation",
      "priority": 1,
      "source_sections": ["## 1. Order Model"],
      "tasks": [
        {
          "id": "create",
          "title": "Create Order model and migration",
          "description": "Define Order model with status, total, customer_id fields. Create migration with proper indexes.",
          "type": "feature",
          "priority": 1,
          "estimate_minutes": 10,
          "depends_on": [],
          "source_sections": ["### 1.1 Create Order Model"],
          "source_lines": "7-10",
          "acceptance": "Order model with migration, factory, indexes on status and customer_id",
          "commit_strategy": "agentic-commits"
        },
        {
          "id": "state-machine",
          "title": "Implement order status state machine",
          "description": "State machine for order lifecycle: pending -> confirmed -> shipped -> delivered",
          "type": "feature",
          "priority": 1,
          "estimate_minutes": 15,
          "depends_on": ["create"],
          "source_sections": ["### 1.2 Order Status Machine"],
          "source_lines": "12-15",
          "acceptance": "State machine transitions work. Invalid transitions throw. Tests cover all paths.",
          "commit_strategy": "agentic-commits"
        }
      ]
    },
    {
      "id": "payment",
      "title": "Payment Integration",
      "description": "Stripe payment gateway integration with webhook support",
      "priority": 2,
      "source_sections": ["## 2. Payment Integration"],
      "tasks": [
        {
          "id": "gateway",
          "title": "Integrate Stripe payment gateway",
          "description": "Integrate Stripe payment gateway. Requires Order model to exist.",
          "type": "feature",
          "priority": 2,
          "estimate_minutes": 15,
          "depends_on": ["model-create"],
          "source_sections": ["### 2.1 Payment Gateway"],
          "source_lines": "17-19",
          "acceptance": "Stripe charges work in test mode. Error handling for failed payments.",
          "commit_strategy": "agentic-commits"
        },
        {
          "id": "webhooks",
          "title": "Handle Stripe payment webhooks",
          "description": "Handle Stripe webhook callbacks for payment confirmation. Depends on payment gateway.",
          "type": "feature",
          "priority": 2,
          "estimate_minutes": 10,
          "depends_on": ["gateway"],
          "source_sections": ["### 2.2 Payment Webhooks"],
          "source_lines": "21-23",
          "acceptance": "Webhook endpoint validates signatures. Payment confirmed updates order status.",
          "quality_gate": "composer lint && composer test",
          "commit_strategy": "agentic-commits"
        }
      ]
    }
  ],
  "coverage": {
    "total_sections": 8,
    "mapped_sections": 6,
    "unmapped": [],
    "context_only": ["# Order Processing System", "## Overview"]
  }
}
```

### What bd-from-plan Creates

```
Created epic: order-model (Order Model)
  Created task: order-model-create (Create Order model and migration) [P1]
  Created task: order-model-state-machine (Implement order status state machine) [P1]
    Added dep: order-model-state-machine depends on order-model-create
Created epic: order-payment (Payment Integration)
  Created task: order-payment-gateway (Integrate Stripe payment gateway) [P2]
    Added dep: order-payment-gateway depends on order-model-create
  Created task: order-payment-webhooks (Handle Stripe payment webhooks) [P2]
    Added dep: order-payment-webhooks depends on order-payment-gateway

Done: 2 epics, 4 tasks, 3 dependencies created
```

---

## Dependency Resolution

The script uses **smart resolution** — it works with both formats transparently:

### Same-epic dependency (just task ID):
```json
{
  "id": "state-machine",
  "depends_on": ["create"]
}
```
Resolves to: `order-model-state-machine` depends on `order-model-create` (same epic `model`).

### Cross-epic dependency (epicId-taskId):
```json
{
  "id": "gateway",
  "depends_on": ["model-create"]
}
```
Resolves to: `order-payment-gateway` depends on `order-model-create` (cross-epic from `payment` to `model`).

### Resolution logic:
1. Try exact match against all `epicId-taskId` combinations in the plan
2. If no match, treat as same-epic: prepend the current epic's ID

This means kebab-case task IDs (e.g., `create-lock-model`) work correctly in both positions.

---

## Coverage Failure Example

```json
{
  "coverage": {
    "total_sections": 8,
    "mapped_sections": 5,
    "unmapped": ["### 1.3 Order Validation", "### 2.3 Refund Flow"],
    "context_only": ["# Title"]
  }
}
```

Script output:
```
ERROR: 2 unmapped sections found:
  - ### 1.3 Order Validation
  - ### 2.3 Refund Flow
Fix: Add tasks for these sections or mark them as context_only
```

---

## Dry Run Output

```bash
bd-from-plan --dry-run "$PLAN_FILE"
```

```
DRY RUN - No changes will be made

Plan: docs/plans/order-processing.md
Prefix: order

Epics (2):
  [1] order-model: Order Model (P1)
      Tasks: 2

  [2] order-payment: Payment Integration (P2)
      Tasks: 2

Tasks (4, topological order):
  [1] order-model-create: Create Order model and migration
      Type: feature | Priority: P1 | Est: 10m
      Deps: (none)
      Gate: composer lint && composer test && composer type

  [2] order-model-state-machine: Implement order status state machine
      Type: feature | Priority: P1 | Est: 15m
      Deps: order-model-create
      Gate: composer lint && composer test && composer type

  [3] order-payment-gateway: Integrate Stripe payment gateway
      Type: feature | Priority: P2 | Est: 15m
      Deps: order-model-create
      Gate: composer lint && composer test && composer type

  [4] order-payment-webhooks: Handle Stripe payment webhooks
      Type: feature | Priority: P2 | Est: 10m
      Deps: order-payment-gateway
      Gate: composer lint && composer test

Coverage: 8 total, 6 mapped, 2 context_only, 0 unmapped -> PASS

Dependencies (3):
  order-model-state-machine -> order-model-create
  order-payment-gateway -> order-model-create
  order-payment-webhooks -> order-payment-gateway

No cycles detected.

Total estimate: 50m
```
