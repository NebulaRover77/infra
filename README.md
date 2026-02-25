README.md

# infra

Small infra toolbox repo for:
- Terraform (currently: VPC IPAM scaffold) in `./tfs`
- Utility scripts (currently: delete default VPC) in repo root
- Simple `Makefile` wrapper so you don’t have to remember terraform CLI flags

## Layout

- `Makefile`  
  Convenience targets that run Terraform from `./tfs` and always use a shared tfvars file:
  `$(PRIVATE)/ipam.tfvars`

- `tfs/`  
  Terraform config that creates an AWS VPC IPAM with:
  - IPv4 private hierarchy:
    - top-level pool: `10.0.0.0/8`
    - one regional child pool per configured operating region: **/16** (assigned automatically)
    - VPC allocations from regional pool: **variable**, default **/22**, allowed range **/20..../24**
  - IPv6 public pool:
    - Amazon-assigned **/52** (no CIDR hardcoding)
    - default allocations: /56 (configurable)

- `delete-default-vpc.sh`  
  Bash script that finds and deletes the **default VPC** in a region (or all regions), including:
  IGW, subnets, route tables, non-default NACLs, non-default SGs, VPC endpoints, NAT gateways, and
  optionally deletes the DHCP options set if unused.

## Prereqs

- Terraform >= 1.5
- AWS CLI v2
- Logged in via SSO to the target AWS account/profile you plan to operate on
  (e.g. `aws sso login --profile AWSPowerUserAccess-<account>`)

## Shared tfvars

This repo expects the values file to live outside git:

`./private/ipam.tfvars`

(`./private` is a tracked symlink to your private infra directory.)

Example:

```hcl
profile = "AWSPowerUserAccess-123456789012"
region  = "us-east-1"
additional_operating_regions = ["us-east-2", "us-west-2"]

tags = {
  Project = "network"
  Owner   = "jonax"
}

Terraform usage

From the repo root:

make fmt
make validate
make init
make plan
make apply
make output

Notes:
	•	make plan/apply/destroy automatically adds -var-file="$(PRIVATE)/ipam.tfvars".
	•	make init does not pass tfvars (Terraform doesn’t need them for init).

delete-default-vpc.sh usage

Dry run first:

./delete-default-vpc.sh --profile AWSPowerUserAccess-123456789012 --region us-east-1 --dry-run

Then:

./delete-default-vpc.sh --profile AWSPowerUserAccess-123456789012 --region us-east-1
# or:
./delete-default-vpc.sh --profile AWSPowerUserAccess-123456789012 --all-regions

What this repo is NOT doing (yet)
	•	No remote Terraform state backend configured in code (still local state by default).
	•	No VPC creation module yet; this is IPAM scaffolding only.
