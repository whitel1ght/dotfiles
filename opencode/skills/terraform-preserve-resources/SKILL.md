---
name: terraform-preserve-resources
description: >-
  Generate and execute commands to safely remove resources from Terraform state without destroying them. Use when preserving resources during decommissioning, when user asks to "preserve", "keep", "don't destroy", or "remove from state" specific resources.
---


# Terraform Preserve Resources

Safely detach resources from Terraform state management so they persist in AWS while being removed from Terraform's control.

## Process

### 1. Identify Resources to Preserve

Gather the list of resources that should NOT be destroyed:
- Ask user for specific resources if not clear
- Check decommissioning progress document for preservation requirements
- Common preservation candidates:
  - Route53 zones serving new infrastructure
  - S3 buckets with business data
  - CloudWatch log groups for compliance
  - KMS keys shared across environments

### 2. Find Exact State Paths

Use terraform state commands to find exact resource addresses:

```bash
cd environments/{env}

# List all resources matching pattern
terraform state list | grep "route53_zone"
terraform state list | grep "s3_bucket"
terraform state list | grep "cloudwatch_log_group"
```

Document the exact state paths found.

### 3. Verify Resources Exist in AWS

Before removing from state, confirm resources exist:

```bash
# Route53 zones
aws route53 list-hosted-zones --query "HostedZones[?Name=='development.ecfx-corp.com.']"

# S3 buckets
aws s3 ls | grep "ecfx-court-documents"

# CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/ecfx-development"
```

### 4. Generate State Removal Commands

Create the commands to remove resources from state:

```bash
cd environments/{env}

# Route53 zones
terraform state rm 'module.development.aws_route53_zone.main'
terraform state rm 'module.development.aws_route53_zone.main_public'

# S3 buckets
terraform state rm 'module.development.aws_s3_bucket.court_documents'
terraform state rm 'module.development.aws_s3_bucket.email_messages'
terraform state rm 'module.development.aws_s3_bucket.agent_request_bodies'
terraform state rm 'module.development.aws_s3_bucket.agent_response_bodies'
terraform state rm 'module.development.aws_s3_bucket.documents_pro_tem'
terraform state rm 'module.development.aws_s3_bucket.vpc_flow_logs'

# CloudWatch log groups
terraform state rm 'module.development.aws_cloudwatch_log_group.eks_application'
# ... additional log groups
```

### 5. Alternative: Terraform Removed Blocks (1.7+)

For Terraform 1.7+, generate `removed` blocks as alternative:

```hcl
# Add to environments/{env}/removed.tf

removed {
  from = module.development.aws_route53_zone.main
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.development.aws_route53_zone.main_public
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.development.aws_s3_bucket.court_documents
  lifecycle {
    destroy = false
  }
}

# Continue for all preserved resources...
```

### 6. Generate Verification Steps

Create verification commands to run after state removal:

```bash
# Verify resources removed from state
terraform state list | grep "route53_zone"  # Should return nothing
terraform state list | grep "s3_bucket"     # Should return nothing

# Verify resources still exist in AWS
aws route53 list-hosted-zones --query "HostedZones[?Name=='development.ecfx-corp.com.']"
aws s3 ls s3://ecfx-court-documents-development/
aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/ecfx-development"

# Run terraform plan - preserved resources should NOT appear
terraform plan
```

### 7. Generate Preservation Report

```markdown
## Resource Preservation Plan

### Environment: [env]
### Date: [date]

---

### Resources to Preserve

| Resource Type | State Path | AWS Resource ID | Reason |
|---------------|------------|-----------------|--------|
| Route53 Zone | `module.development.aws_route53_zone.main` | Z2VRGUOAF3DGEF | Serving DuploCloud |
| Route53 Zone | `module.development.aws_route53_zone.main_public` | ZXXXXX | Serving DuploCloud |
| S3 Bucket | `module.development.aws_s3_bucket.court_documents` | ecfx-court-documents-development | Business data |
[Continue for all resources]

---

### Method: [State Removal / Removed Blocks]

#### State Removal Commands

```bash
cd environments/{env}

# Run these commands to remove from state:
terraform state rm 'module.development.aws_route53_zone.main'
terraform state rm 'module.development.aws_route53_zone.main_public'
# ... [remaining commands]
```

#### Alternative: Removed Blocks (Terraform 1.7+)

Create `environments/{env}/removed.tf`:

```hcl
[removed blocks content]
```

---

### Verification Checklist

After running state removal:

- [ ] Resources no longer in `terraform state list`
- [ ] Resources still exist in AWS Console
- [ ] `terraform plan` shows no changes for these resources
- [ ] DNS resolution works for Route53 zones
- [ ] S3 buckets are accessible
- [ ] CloudWatch logs are queryable

---

### Rollback

If resources were incorrectly removed from state:

```bash
# Re-import resources (example)
terraform import 'module.development.aws_route53_zone.main' Z2VRGUOAF3DGEF
terraform import 'module.development.aws_s3_bucket.court_documents' ecfx-court-documents-development
```

---

### Notes

- State removal is NOT reversible without re-import
- Removed resources become "unmanaged" by Terraform
- Future changes to these resources must be made manually or via separate Terraform config
```

## Quality Checklist

- [ ] All preservation candidates identified
- [ ] Exact state paths verified
- [ ] AWS resource existence confirmed
- [ ] State removal commands generated
- [ ] Verification steps included
- [ ] Rollback/import commands documented

## Special Cases

**Nested Modules**: State paths may be deeply nested (e.g., `module.dev.module.vpc.aws_subnet.private[0]`). Verify exact paths.

**For-Each Resources**: Resources created with `for_each` have bracket notation (e.g., `aws_route53_record.records["api"]`).

**Count Resources**: Resources created with `count` have index notation (e.g., `aws_subnet.private[0]`).

**Remote State**: For S3 backend, ensure proper authentication before state operations.

## Safety Notes

1. **NEVER** run `terraform destroy` on resources you want to preserve
2. **ALWAYS** verify resources exist in AWS before removing from state
3. **ALWAYS** run `terraform plan` after state removal to verify expected behavior
4. **DOCUMENT** all state removals for audit trail
5. Consider using `removed` blocks instead of manual state removal for better version control

---

For detailed examples, see `examples.md`
