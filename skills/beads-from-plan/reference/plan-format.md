# Plan Format Reference

## Expected Markdown Structure

The input markdown plan should follow a hierarchical structure:

```markdown
# Plan Title                     <- context_only
## Overview / Introduction       <- context_only (optional)
## 1. First Work Stream          <- becomes an epic
### 1.1 First Task               <- becomes a task
### 1.2 Second Task              <- becomes a task
#### 1.2.1 Sub-detail            <- merged into parent task or separate task
## 2. Second Work Stream         <- becomes an epic
### 2.1 Another Task             <- becomes a task
## Appendix / References         <- context_only (optional)
```

## Section Classification

| Pattern | Classification | Becomes |
|---------|---------------|---------|
| `#` title | context_only | Nothing (plan title) |
| `##` with "Overview", "Introduction", "Summary" | context_only | Nothing |
| `##` with "Appendix", "References", "Links" | context_only | Nothing |
| `##` with content sections | epic | `bd create --type epic` |
| `###` under an epic | task | `bd create --type task --parent` |
| `####` with substantial content | task or merged | Depends on size |
| `####` with brief content | merged into parent | Part of parent task description |

## What Makes a Good Plan for Decomposition

### Good: Clear hierarchy with actionable sections
```markdown
## 1. Database Layer
### 1.1 Create User Model
- Fields: email, password_hash, created_at
- Indexes: unique on email
- Relationships: hasMany(Token)

### 1.2 Create Token Model
- Fields: user_id, token, expires_at
- Relationships: belongsTo(User)
```

### Bad: Flat structure with no hierarchy
```markdown
## Tasks
- Create user model
- Create token model
- Add authentication
- Write tests
```

### Bad: Too much prose, not enough structure
```markdown
## Authentication
We need to think about how authentication will work. There are
several approaches we could take. Let's consider the options...
```

## Dependency Indicators in Prose

Look for these patterns when extracting dependencies:

| Pattern | Meaning |
|---------|---------|
| "requires X" | depends on X |
| "after X is complete" | depends on X |
| "builds on X" | depends on X |
| "uses the X from section Y" | depends on Y's task |
| "extends X" | depends on X |
| "once X exists" | depends on X |
| "assuming X is done" | depends on X |

## Estimating Task Size

| Indicator | Estimate |
|-----------|----------|
| Single model + migration | 10 min |
| CRUD endpoint | 15 min |
| Complex business logic | Split into 2-3 tasks of 10-15 min |
| Integration with external service | Split into 3-4 tasks of 10-15 min |
| Full feature with tests | Split into multiple tasks of 5-15 min |
| Configuration/setup | 5-10 min |
| Documentation | 5-10 min |
