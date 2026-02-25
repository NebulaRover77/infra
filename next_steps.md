# next_steps

This is the “do next when back online” checklist.

## 0) Quick sanity checks

- Confirm AWS auth for the target account:

```bash
aws sts get-caller-identity --profile AWSPowerUserAccess-123456789012

	•	Confirm shared tfvars exists and looks right:

cat ./private/ipam.tfvars

1) (Optional but recommended) Configure remote Terraform state

Goal: store Terraform state in S3 (preferably centralized in hd2019 / management account).

Decision points:
	•	Per-account S3 bucket (simpler) vs org-wide central bucket in 123456789012 (more IAM wiring).
	•	Locking: S3 lockfiles (use_lockfile=true) vs legacy DynamoDB (not required).

If going central-bucket:
	•	Create bucket in 123456789012 (xx2019)
	•	Create a role in 123456789012 that other org accounts can assume for state read/write
	•	Add backend "s3" { ... role_arn=... use_lockfile=true } to tfs/main.tf
	•	Re-run make init to migrate state

2) Run Terraform for IPAM scaffold

From repo root:

make fmt
make validate
make init
make plan
make apply
make output

After apply, capture outputs:
	•	ipv4_regional_pool_ids (region -> pool id)
	•	ipv4_regional_pool_cidrs (region -> assigned /16)
	•	ipv6_top_assigned_cidr (Amazon assigned /52)

3) Decide VPC allocation strategy per environment

Current plan:
	•	Regional IPv4 pool: /16 per region
	•	VPC sizes (examples):
	•	dev: /24
	•	stage: /22 (default)
	•	prod: /20

Next: create a vpc/ Terraform module that:
	•	requests IPv4 CIDR from the regional pool (ipv4_ipam_pool_id)
	•	requests IPv6 CIDR from the IPv6 pool (likely /56)
	•	creates subnets, IGW/eIGW, route tables, NAT (if needed), and baseline SGs

4) Default VPC cleanup (optional)

In any new account/region, you can delete the default VPC:

./delete-default-vpc.sh --profile AWSPowerUserAccess-<account> --region us-east-1 --dry-run
./delete-default-vpc.sh --profile AWSPowerUserAccess-<account> --region us-east-1

5) Git hygiene

Before committing:
	•	Do NOT commit terraform.tfstate*, .terraform/, or any *.tfvars with account-specific values.
	•	Consider adding a .gitignore:

Suggested .gitignore:

.terraform/
*.tfstate
*.tfstate.*
.terraform.lock.hcl
crash.log
*.tfvars
*.tfvars.json

Then:

git add Makefile delete-default-vpc.sh tfs README.md next_steps.md .gitignore
git commit -m "Initial infra: IPAM terraform + default VPC cleanup script"
