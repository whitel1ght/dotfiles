---
name: terraform-plan-review
description: >-
  Review Terraform plan output to identify destruction impacts, verify preserved resources, and catch unintended changes. Use when reviewing terraform plan output, before approving apply jobs, when user mentions "review the plan", "what will be destroyed", or "is it safe to apply".
---


# Terraform Plan Review

Analyze Terraform plan output to verify changes are safe and expected before applying, with special focus on infrastructure decommissioning scenarios.

## Process

### 1. Parse Plan Output

Extract key information from terraform plan:
- Count of resources: add, change, destroy
- List all resources being destroyed (lines with `# ... will be destroyed`)
- List all resources being modified (lines with `# ... will be updated in-place`)
- List all resources being created (lines with `# ... will be created`)
- Note any warnings or errors

### 2. Categorize Resources by Type

Group destroyed/changed resources into categories:

**Compute**:
- EC2 instances (`aws_instance`)
- EKS clusters (`aws_eks_cluster`)
- Launch templates, ASGs
- Lambda functions

**Database**:
- RDS instances (`aws_db_instance`)
- ElastiCache clusters (`aws_elasticache_replication_group`)
- OpenSearch domains (`aws_opensearch_domain`)

**Networking**:
- VPCs, subnets, route tables
- Security groups (`aws_security_group`)
- NAT gateways, internet gateways
- VPC endpoints, peering connections
- Elastic IPs (`aws_eip`)

**Storage**:
- S3 buckets (`aws_s3_bucket`)
- EBS volumes

**DNS**:
- Route53 zones (`aws_route53_zone`)
- Route53 records (`aws_route53_record`)

**IAM**:
- Roles, policies, instance profiles
- Users, groups

**Monitoring**:
- CloudWatch log groups (`aws_cloudwatch_log_group`)
- CloudWatch alarms, dashboards

**Kubernetes**:
- Helm releases (`helm_release`)
- kubectl manifests (`kubectl_manifest`)
- ConfigMaps, Secrets

**Security**:
- KMS keys (`aws_kms_key`)
- WAF resources
- Secrets Manager secrets

### 3. Check Preserved Resources

For decommissioning scenarios, verify these resource types are NOT in the destruction list:

**Must Preserve (if applicable)**:
- Route53 hosted zones (may be serving new infrastructure)
- S3 buckets with business data
- CloudWatch log groups (audit/compliance)
- RDS snapshots

Flag any preserved resource types that appear in the plan with warnings.

### 4. Identify Unexpected Changes

Look for:
- Resources being destroyed that weren't expected
- In-place updates that might cause disruption
- Changes to resources in unexpected modules
- Destruction of resources with `prevent_destroy` lifecycle rules

### 5. Generate Review Report

Create a structured report:

```markdown
## Terraform Plan Review

### Summary
- **Add**: [count]
- **Change**: [count]
- **Destroy**: [count]

### Resources to be DESTROYED ([count])

**Compute ([count])**
- `resource_address` - Description
...

**Networking ([count])**
- `resource_address` - Description
...

[Additional categories as needed]

### Preserved Resources Check

| Resource Type | Status |
|---------------|--------|
| Route53 Zones | [✅ NOT in plan / ⚠️ IN PLAN] |
| S3 Buckets | [✅ NOT in plan / ⚠️ IN PLAN] |
| CloudWatch Logs (main) | [✅ NOT in plan / ⚠️ IN PLAN] |

### Warnings
- [List any deprecation warnings or concerns]

### Verdict
[✅ SAFE TO APPLY / ⚠️ REVIEW NEEDED / ❌ DO NOT APPLY]
[Brief explanation of verdict]
```

### 6. Provide Recommendations

Based on analysis:

**If Safe**:
```
✅ SAFE TO APPLY

All changes match expected scope. Preserved resources are not affected.
Proceed with `apply_dev` (or appropriate apply job).
```

**If Concerns**:
```
⚠️ REVIEW NEEDED

[Specific concern, e.g., "Route53 zone is being destroyed but may be needed"]
Recommend: [Action to take before applying]
```

**If Critical Issues**:
```
❌ DO NOT APPLY

[Critical issue, e.g., "S3 bucket with production data is being destroyed"]
Action Required: [Steps to fix the plan]
```

## Quality Checklist

- [ ] All destroyed resources categorized
- [ ] Preserved resources verified as NOT in plan
- [ ] Unexpected changes flagged
- [ ] Warnings noted and assessed
- [ ] Clear verdict provided
- [ ] Recommendations are actionable

## Special Cases

**Decommissioning Phases**: When reviewing phased destruction:
- Verify only resources for current phase are destroyed
- Confirm dependencies are respected (e.g., EKS before VPC)
- Check that resources for future phases are unchanged

**Large Plans**: For 50+ resource changes:
- Focus on critical categories first (databases, storage, DNS)
- Summarize by module when applicable
- Highlight any production-impacting changes

**Module Removal**: When entire modules are removed:
- All module resources will show as destroyed
- Verify module removal is intentional
- Check for state-only resources that should be preserved

## Output Format Example

```markdown
## Terraform Plan Review - Phase 1

### Summary
- **Add**: 0
- **Change**: 0
- **Destroy**: 47

### Resources to be DESTROYED (47)

**Compute (2)**
- `module.development.module.scrapers-amazon-dcv[0].aws_instance.amazon_dcv` - DCV scraper EC2 (g4dn.xlarge)
- `module.development.module.static_ip_proxy[0].aws_instance.proxy` - Static IP proxy EC2 (t4g.small)

**IAM (10)**
- `module.development.module.scrapers-amazon-dcv[0].aws_iam_role.r` - Scraper IAM role
- `module.development.module.scrapers-amazon-dcv[0].aws_iam_policy.*` - Scraper policies (3)
...

**Networking (15)**
- Security groups and rules for scrapers and proxy
- Network interfaces for proxy
- Elastic IP for proxy

**DNS (2)**
- `aws_route53_record.amazon_dcv` - headed-scraper.development.ecfx-corp.com
- `aws_route53_record.proxy` - socks.i.development.ecfx-corp.com

**Monitoring (3)**
- CloudWatch log groups for scraper and proxy workloads

**Kubernetes (1)**
- `kubectl_manifest.extra_manifests["default-secret-ecfx-sys-proxy-socks5"]` - Proxy secret

### Preserved Resources Check

| Resource Type | Status |
|---------------|--------|
| Route53 Zones | ✅ NOT in plan |
| S3 Buckets | ✅ NOT in plan |
| CloudWatch Logs (main) | ✅ NOT in plan |
| EKS Cluster | ✅ NOT in plan |
| RDS Databases | ✅ NOT in plan |

### Warnings
- 8 deprecation warnings about kubernetes_config_map (cosmetic)

### Verdict
✅ SAFE TO APPLY

Only Phase 1 optional components being destroyed. All preserved resources unaffected.
```

---

For detailed examples, see `examples.md`
