# Repository Instructions

## Terraform Variable Style

- Keep variable blocks in `variables.tf` alphabetized by variable name.

## Terraform IAM Policy Style

- In IAM policy JSON/HCL, alphabetize every `Action` list within each `Statement` or `Sid`.
- Preserve existing `Sid` order unless there is a specific reason to change it.

## AWS Management

- Manage AWS infrastructure and configuration through Terraform and GitOps.
- Do not create or mutate AWS resources with the AWS CLI unless the user explicitly asks for a one-off operational command.
