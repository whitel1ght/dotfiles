---
name: terraform-state-inventory
description: >-
  Generate a human-readable inventory of resources in Terraform state for a specific environment. Use when planning infrastructure changes, understanding what resources exist, documenting current state, or when user mentions "list resources", "what's in state", "inventory", or "show infrastructure".
---


# Terraform State Inventory

Generate a comprehensive, categorized inventory of all resources managed by Terraform in a specific environment's state.

## Process

### 1. Access State

Navigate to the environment directory and list state:

```bash
cd environments/{env}
terraform state list
```

If state is remote, ensure proper AWS authentication.

### 2. Parse State Output

Process the state list to:
- Count total resources
- Identify module structure
- Group by resource type
- Flag resources matching preservation patterns

### 3. Categorize Resources

Group resources into logical categories:

**Compute**:
- `aws_instance.*`
- `aws_eks_cluster.*`
- `aws_launch_template.*`

**Database**:
- `aws_db_instance.*`
- `aws_db_parameter_group.*`
- `aws_elasticache_replication_group.*`
- `aws_opensearch_domain.*`

**Networking**:
- `aws_vpc.*`
- `aws_subnet.*`
- `aws_security_group.*`
- `aws_nat_gateway.*`
- `aws_internet_gateway.*`
- `aws_route_table.*`
- `aws_vpc_endpoint.*`
- `aws_eip.*`

**Storage**:
- `aws_s3_bucket.*`
- `aws_s3_bucket_policy.*`

**DNS**:
- `aws_route53_zone.*`
- `aws_route53_record.*`

**IAM**:
- `aws_iam_role.*`
- `aws_iam_policy.*`
- `aws_iam_instance_profile.*`
- `aws_iam_role_policy_attachment.*`

**Monitoring**:
- `aws_cloudwatch_log_group.*`
- `aws_cloudwatch_metric_alarm.*`

**Security**:
- `aws_kms_key.*`
- `aws_kms_alias.*`
- `aws_wafv2_web_acl.*`
- `aws_secretsmanager_secret.*`

**Kubernetes**:
- `helm_release.*`
- `kubectl_manifest.*`
- `kubernetes_*`

### 4. Identify Module Structure

Parse module paths to understand hierarchy:
- Root module resources
- Nested module resources (e.g., `module.development.module.k8s`)
- Count resources per module

### 5. Flag Preservation Candidates

Mark resources that typically need preservation during decommissioning:
- Route53 zones (serving new infrastructure)
- S3 buckets (business data)
- CloudWatch log groups (compliance)
- KMS keys (may be shared)

### 6. Generate Inventory Report

```markdown
## Terraform State Inventory: [environment]

### Summary
- **Total Resources**: [count]
- **Modules**: [count] ([list module names])
- **Last Refreshed**: [date/time if available]

### Module Structure

```
[environment]/
├── module.{name}/ ([count] resources)
│   ├── module.nested/ ([count] resources)
│   └── ...
└── [root resources] ([count])
```

### Resources by Category

**Compute ([count])**
- [count]x EKS cluster(s)
- [count]x EC2 instance(s)
- [count]x Launch template(s)

**Database ([count])**
- [count]x RDS instance(s)
- [count]x Parameter group(s)
- [count]x ElastiCache cluster(s)

[Continue for all categories]

### Preservation Candidates

⚠️ Resources that may need preservation during decommissioning:

| Resource | State Path | Reason |
|----------|------------|--------|
| Route53 Zone (internal) | `module.dev.aws_route53_zone.main` | May serve new infra |
| Route53 Zone (public) | `module.dev.aws_route53_zone.main_public` | May serve new infra |
| S3 Court Documents | `module.dev.aws_s3_bucket.court_documents` | Business data |
[Continue for all preservation candidates]

### Full Resource List

<details>
<summary>Click to expand full resource list</summary>

```
[Full terraform state list output]
```

</details>
```

## Quality Checklist

- [ ] All resources categorized
- [ ] Module structure documented
- [ ] Preservation candidates flagged
- [ ] Counts match total
- [ ] Output is readable and organized

## Special Cases

**Large States**: For 200+ resources, summarize by module first, provide full list in collapsible section.

**Remote State Access Issues**: If state can't be accessed, provide commands user can run locally.

**Multiple Environments**: Can generate comparative inventory across environments.

## Commands Reference

```bash
# List all resources
terraform state list

# Count resources
terraform state list | wc -l

# List resources matching pattern
terraform state list | grep "aws_s3_bucket"

# Show specific resource details
terraform state show 'module.dev.aws_s3_bucket.court_documents'

# List resources in specific module
terraform state list | grep "^module.development.module.k8s"
```

---

For detailed examples, see `examples.md`
