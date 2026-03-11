# AzerothCore AWS Terraform

This repo provisions an AzerothCore stack on AWS using the official precompiled `acore` Docker Hub images instead of building
AzerothCore from source.

## Summary

- Public NLB listeners on `3724` and `8085`
- ECS Fargate services for `authserver` and `worldserver`
- RDS MySQL 8.4 in private subnets
- EFS mounted into `worldserver` at `/azerothcore/env/dist/data`
- One-off ECS task definition for the official `acore/ac-wotlk-client-data` image
- One-off ECS task definition for the official `acore/ac-wotlk-db-import` bootstrap image
- CloudWatch Logs and Secrets Manager for runtime configuration

## Default Images

- `acore/ac-wotlk-authserver:master`
- `acore/ac-wotlk-client-data:master`
- `acore/ac-wotlk-worldserver:master`
- `acore/ac-wotlk-db-import:master`

## Quick Start

1. Create the remote state bucket.
2. `terraform init`
3. `terraform apply`
4. Run the `db-import` ECS task once.
5. Run the `client-data` ECS task once.
6. Update `acore_auth.realmlist.address` to the NLB DNS name or your domain.

## Docker Hub Rate Limits

AWS ECS pulls these official `acore` images from Docker Hub. If you hit unauthenticated pull rate limits, let Terraform
manage the Secrets Manager secret resource and then set the secret value separately:

```bash
terraform apply
```

Then write the credential value once:

```bash
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw docker_registry_credentials_secret_arn)" \
  --secret-string '{"username":"<dockerhub-username>","password":"<dockerhub-password-or-token>"}'
```

`docker_registry_auth_enabled` controls whether ECS actually uses those credentials for image pulls. If you already manage
the secret elsewhere, you can still set `TF_VAR_docker_registry_credentials_secret_arn` instead.

## DB Bootstrap

Terraform creates a task definition for the official `acore/ac-wotlk-db-import` image. Run it once after `terraform apply`
to initialize the AzerothCore databases:

```bash
aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --launch-type FARGATE \
  --task-definition <db_import_task_definition_arn> \
  --network-configuration "awsvpcConfiguration={subnets=[<private_subnet_ids>],securityGroups=[<ecs_security_group_id>],assignPublicIp=DISABLED}"
```

Watch the logs in CloudWatch under `/ecs/azerothcore/db-import`.

## Client Data Bootstrap

Terraform also creates a task definition for the official `acore/ac-wotlk-client-data` image. Run it once after
`terraform apply` to populate EFS with maps, vmaps, and mmaps:

```bash
aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --launch-type FARGATE \
  --task-definition <client_data_task_definition_arn> \
  --network-configuration "awsvpcConfiguration={subnets=[<private_subnet_ids>],securityGroups=[<ecs_security_group_id>],assignPublicIp=DISABLED}"
```

Watch the logs in CloudWatch under `/ecs/azerothcore/client-data`.

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

```bash
docker compose config
```

## Client Data

The official worldserver image expects maps/vmaps/mmaps in `/azerothcore/env/dist/data`. Populate the EFS filesystem before
players connect. The `client-data` ECS task above is the intended cloud bootstrap path for that.

Then initialize Terraform normally:

```bash
terraform init
```

## Notes

- Network Load Balancer preserves the client source IP. Because of that, the ECS task security group must allow your client
  CIDRs directly via `allowed_ingress_cidrs`. The NLB itself does not have a security group.
- The official images come from the AzerothCore `acore-docker` project and Docker Hub.
- The DB bootstrap task is the official AzerothCore importer/bootstrap image. It is not the old custom "load an arbitrary
  SQL dump from S3" flow.
