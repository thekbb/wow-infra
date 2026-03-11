# AzerothCore AWS Terraform

This repo provisions an AzerothCore stack on AWS using the official precompiled `acore` Docker Hub images instead of building AzerothCore from source.

Summary
- Public NLB listeners on `3724` and `8085`
- ECS Fargate services for `authserver` and `worldserver`
- RDS MySQL 8.4 in private subnets
- EFS mounted into `worldserver` at `/azerothcore/env/dist/data`
- One-off ECS task definition for the official `acore/ac-wotlk-db-import` bootstrap image
- CloudWatch Logs and Secrets Manager for runtime configuration

Default images
- `acore/ac-wotlk-authserver:master`
- `acore/ac-wotlk-worldserver:master`
- `acore/ac-wotlk-db-import:master`

## Quick Start

1. Create the remote state bucket.
2. `terraform init`
3. `terraform apply`
4. Run the `db-import` ECS task once.
5. Put client data into EFS.
6. Update `acore_auth.realmlist.address` to the NLB DNS name or your domain.

## DB Bootstrap

Terraform creates a task definition for the official `acore/ac-wotlk-db-import` image. Run it once after `terraform apply` to initialize the AzerothCore databases:

```bash
aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --launch-type FARGATE \
  --task-definition <db_import_task_definition_arn> \
  --network-configuration "awsvpcConfiguration={subnets=[<private_subnet_ids>],securityGroups=[<ecs_security_group_id>],assignPublicIp=DISABLED}"
```

Watch the logs in CloudWatch under `/ecs/azerothcore/db-import`.

## Local Smoke Test

The local [docker-compose.yml](/Users/thekbb/wow-infra/docker-compose.yml) uses the official `acore` images too. It starts:
- local MySQL
- the official `ac-wotlk-client-data` image to populate a Docker volume with maps/vmaps/mmaps
- the official `ac-wotlk-db-import` image to initialize the databases
- `authserver` and `worldserver`

Run:

```bash
docker compose up
```

Check the rendered config first if you want:

```bash
docker compose config
```

## Client Data

The official worldserver image expects maps/vmaps/mmaps in `/azerothcore/env/dist/data`. Populate the EFS filesystem before players connect.

## Remote State Bootstrap

Terraform is configured to use an S3 backend in `us-east-2` with S3 lockfiles. Because the state bucket must exist before `terraform init`, create it once with the AWS CLI:

```bash
export AWS_REGION=us-east-2
export TF_STATE_BUCKET="wow-infra-tfstate"

aws s3api create-bucket \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-bucket-versioning \
  --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "$TF_STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "$TF_STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Then initialize Terraform normally:

```bash
terraform init
```

## Terraform Apply

```bash
terraform apply
```

Key variables you may want to adjust:
- `allowed_ingress_cidrs`
- `db_instance_class`
- `desired_task_cpu`
- `desired_task_memory`
- `auth_image`
- `world_image`
- `db_import_image`

Outputs
- `nlb_dns_name`
- `rds_endpoint`
- `db_secret_arn`
- `db_import_task_definition_arn`
- `ecs_cluster_name`
- `ecs_security_group_id`
- `private_subnet_ids`

## Notes

- Network Load Balancer preserves the client source IP. Because of that, the ECS task security group must allow your client CIDRs directly via `allowed_ingress_cidrs`. The NLB itself does not have a security group.
- The official images come from the AzerothCore `acore-docker` project and Docker Hub.
- The DB bootstrap task is the official AzerothCore importer/bootstrap image. It is not the old custom "load an arbitrary SQL dump from S3" flow.
