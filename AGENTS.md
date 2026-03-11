# Repository Instructions

## Markdown Style

- Read `.markdownlint.yml` and follow its rules when editing Markdown in this repo.
- Keep Markdown lines within the configured maximum line length.

## YAML Style

- Read `.yamllint.yml` and follow its rules when editing YAML in this repo.
- Keep YAML lines within the configured maximum line length.

## Terraform Variable Style

- Keep variable blocks in `variables.tf` alphabetized by variable name.

## Terraform IAM Policy Style

- In IAM policy JSON/HCL, alphabetize every `Action` list within each `Statement` or `Sid`.
- Preserve existing `Sid` order unless there is a specific reason to change it.

## AWS Management

- Manage AWS infrastructure and configuration through Terraform and GitOps.
- Do not create or mutate AWS resources with the AWS CLI unless the user explicitly asks
  for a one-off operational command.

## Shell Examples

- All shell examples must be well-formed for `zsh` on macOS.
- Prefer copy-paste-safe commands that do not depend on shell-specific line wrapping behavior.
- When providing multiline commands, format continuations so they can be pasted into `zsh`
  without introducing parse errors.
