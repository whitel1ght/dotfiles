---
name: decommissioning-phase-checklist
description: >-
  Generate phase-specific checklists for infrastructure decommissioning. Use when starting a new decommissioning phase, verifying phase completion, tracking progress, or when user mentions "start phase", "phase checklist", "what's next for decommissioning", or "decommissioning status".
---


# Decommissioning Phase Checklist

Generate comprehensive checklists for each phase of infrastructure decommissioning to ensure safe, systematic teardown.

## Process

### 1. Identify Current Phase

Determine which phase is being worked on:
- Read progress document (`docs/dev-decommissioning-progress.md`)
- Check recent git commits and branches
- Ask user if unclear

### 2. Load Phase Details

For the identified phase, gather:
- Phase number and name
- Resources to be destroyed
- Files to be modified
- Pre-requisites from previous phases
- Preservation requirements

### 3. Generate Pre-requisites Checklist

Create checklist of items that must be verified BEFORE starting:

```markdown
### Pre-requisites

- [ ] Previous phase completed and validated
- [ ] All workloads migrated to new infrastructure
- [ ] No traffic routed to resources being destroyed
- [ ] Manual snapshots created (if applicable)
- [ ] Team notified of planned changes
```

### 4. Generate Execution Checklist

Create step-by-step execution checklist:

```markdown
### Execution Steps

- [ ] Create feature branch: `git checkout -b feature/dev-phase-X-description`
- [ ] Modify Terraform files:
  - [ ] `environments/dev/main.tf` - [specific changes]
  - [ ] [Additional files as needed]
- [ ] Run local validation: `terraform validate`
- [ ] Commit changes with descriptive message
- [ ] Push branch and create MR
- [ ] Wait for `validate_dev` job to pass
- [ ] Wait for `plan_dev` job to complete
- [ ] Review plan output using terraform-plan-review skill
- [ ] Verify only expected resources in destruction list
- [ ] Manually trigger `apply_dev` job
- [ ] Wait for apply to complete
```

### 5. Generate Validation Checklist

Create post-apply validation checklist:

```markdown
### Validation

- [ ] Apply completed without errors
- [ ] Destroyed resources no longer exist in AWS Console
- [ ] Preserved resources still accessible:
  - [ ] Route53 zones resolve correctly
  - [ ] S3 buckets accessible
  - [ ] CloudWatch logs retained
- [ ] New infrastructure unaffected:
  - [ ] DuploCloud services responding
  - [ ] Application health checks passing
- [ ] No orphaned resources in AWS
- [ ] Update progress document with completion status
- [ ] Commit progress document update
```

### 6. Generate Rollback Plan

Include rollback information:

```markdown
### Rollback Plan

If issues occur during this phase:

1. **Do NOT proceed to next phase**
2. **Immediate Actions**:
   - [Phase-specific immediate actions]
3. **Recovery Options**:
   - [Available recovery paths]
4. **Escalation**:
   - Contact: [relevant team/person]
   - Severity: [impact level]
```

### 7. Present Complete Checklist

Combine all sections into a complete phase checklist.

## Phase Templates

### Phase 1: Disable Optional Components

```markdown
## Phase 1: Disable Optional Components

### Pre-requisites
- [ ] Confirm optional components not in use
- [ ] Verify new infrastructure has equivalent functionality

### Execution Steps
- [ ] Create branch: `feature/dev-disable-optional-components`
- [ ] Modify `environments/dev/main.tf`:
  - [ ] Set `scrapers_dcv_inst_enabled = false`
  - [ ] Set `static_ip_proxy_enabled = false`
  - [ ] Set `deploy_fairwinds_insights = false`
- [ ] Run `terraform validate`
- [ ] Commit, push, create MR
- [ ] Review `plan_dev` output
- [ ] Trigger `apply_dev`

### Validation
- [ ] EC2 instances terminated
- [ ] Security groups deleted
- [ ] IAM roles/policies deleted
- [ ] Route53 records removed
- [ ] EKS cluster still operational
- [ ] DuploCloud services unaffected

### Rollback
- Re-enable flags in main.tf
- Apply to recreate resources
```

### Phase 2: Remove EKS Cluster

```markdown
## Phase 2: Remove EKS Cluster

### Pre-requisites
- [ ] Phase 1 completed
- [ ] All workloads migrated to DuploCloud
- [ ] No kubectl contexts pointing to ecfx-development
- [ ] Route53 records point to DuploCloud

### Execution Steps
- [ ] Create branch: `feature/dev-remove-eks-cluster`
- [ ] Modify files:
  - [ ] `environments/dev/main.tf` - Remove k8s module reference
  - [ ] `environments/dev/config_maps.tf` - Remove EKS configs
  - [ ] `environments/dev/environment_secrets.tf` - Remove EKS secrets
  - [ ] `environments/dev/external_secrets.tf` - Remove EKS external secrets
- [ ] Run `terraform validate`
- [ ] Commit, push, create MR
- [ ] Review `plan_dev` - expect ~100+ resources destroyed
- [ ] Trigger `apply_dev`

### Validation
- [ ] EKS cluster deleted from AWS Console
- [ ] No EC2 worker nodes remaining
- [ ] Security groups cleaned up
- [ ] IAM roles for workloads deleted
- [ ] Route53 zones still resolve
- [ ] S3 buckets accessible
- [ ] DuploCloud services unaffected

### Rollback
- EKS would need full recreation from scratch
- Terraform code preserved for reference
- Consider: Is rollback necessary? New infra should handle load
```

### Phase 3-7: Additional Templates

Similar structure for:
- Phase 3: Remove RDS (include snapshot reminder)
- Phase 4: Remove ElastiCache
- Phase 5: Remove OpenSearch
- Phase 6: Remove VPC (destruction order critical)
- Phase 7: Final Cleanup

## Output Format

```markdown
# [Environment] Decommissioning - Phase [N]: [Name]

**Status**: [Not Started / In Progress / Completed]
**Branch**: `feature/[branch-name]`
**MR**: [link or "pending"]

---

### Pre-requisites
[Checklist items]

---

### Execution Steps
[Checklist items]

---

### Expected Resources to Destroy
[List with counts by category]

---

### Validation
[Checklist items]

---

### Rollback Plan
[Recovery steps]

---

### Notes
[Any phase-specific considerations]
```

## Quality Checklist

- [ ] Correct phase identified
- [ ] Pre-requisites include previous phase completion
- [ ] Execution steps are specific and actionable
- [ ] Validation includes both destruction and preservation checks
- [ ] Rollback plan is realistic for the phase
- [ ] Progress document reference included

## Special Cases

**First Phase**: No previous phase pre-requisite, but verify initial migration is complete.

**VPC Phase**: Must be LAST - all compute resources must be destroyed first.

**Database Phases**: Always remind about snapshots before destruction.

**Partial Completion**: If phase partially applied, document state and determine safe continuation.

---

For detailed examples, see `examples.md`
