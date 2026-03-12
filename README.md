# AzerothCore AWS Terraform

This repo provisions an AzerothCore stack on AWS using the official precompiled
`acore` Docker Hub images.

## Summary

- Public NLB listeners on `3724` and `8085`
- ECS Fargate services for `authserver` and `worldserver`
- RDS MySQL 8.4 in private subnets
- EFS mounted into `worldserver` at `/azerothcore/env/dist/data`
- One-off ECS task definition for the official `acore/ac-wotlk-client-data` image
- One-off ECS task definition for the official `acore/ac-wotlk-db-import` bootstrap image
- CloudWatch Logs and Secrets Manager for runtime configuration

`authserver`, `worldserver`, and `client-data` are pinned intentionally so they do not drift with `:master`.

## Quick Start

1. Create the remote state bucket.
1. `terraform init`
1. Add your allowed public client CIDRs to `allowed_ingress.auto.tfvars`.
1. `terraform apply`
1. Run the `db-import` ECS task once.
1. Run the `client-data` ECS task once.
1. Update `acore_auth.realmlist.address` to the NLB DNS name or your domain.

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

`docker_registry_auth_enabled` controls whether ECS actually uses those credentials for image pulls. If you already
manage the secret elsewhere, you can still set `TF_VAR_docker_registry_credentials_secret_arn` instead.

## DB Bootstrap

Terraform creates a task definition for the official `acore/ac-wotlk-db-import`
image. Run it once after `terraform apply` to initialize the AzerothCore
databases:

```bash
SUBNETS='<private_subnet_ids>'
SG='<ecs_security_group_id>'
NETCFG="awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}"

aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --launch-type FARGATE \
  --task-definition <db_import_task_definition_arn> \
  --network-configuration "$NETCFG"
```

Watch the logs in CloudWatch under `/ecs/azerothcore/db-import`.

## Client Data Bootstrap

Terraform also creates a task definition for the official `acore/ac-wotlk-client-data` image. Run it once after
`terraform apply` to populate EFS with maps, vmaps, and mmaps:

```bash
SUBNETS='<private_subnet_ids>'
SG='<ecs_security_group_id>'
NETCFG="awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}"

aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --launch-type FARGATE \
  --task-definition <client_data_task_definition_arn> \
  --network-configuration "$NETCFG"
```

Watch the logs in CloudWatch under `/ecs/azerothcore/client-data`.

## SQL Administration

Terraform creates a one-off MySQL admin task definition you can use to run SQL against the private RDS instance
from inside the VPC.

Example: update `realmlist.address` to `wow.thekbb.net`:

```bash
SUBNETS='<private_subnet_ids>'
SG='<ecs_security_group_id>'
NETCFG="awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}"
SQL="UPDATE realmlist SET address = 'wow.thekbb.net' WHERE id = 1;"
OVERRIDES='{"containerOverrides":[{"name":"mysql-admin","environment":[{"name":"SQL","value":"'"$SQL"'"}]}]}'

aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --launch-type FARGATE \
  --task-definition <mysql_admin_task_definition_arn> \
  --network-configuration "$NETCFG" \
  --overrides "$OVERRIDES"
```

Example: inspect the current realm rows:

```bash
SUBNETS='<private_subnet_ids>'
SG='<ecs_security_group_id>'
NETCFG="awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}"
SQL='SELECT id, name, address, localAddress, localSubnetMask, port FROM realmlist;'
OVERRIDES='{"containerOverrides":[{"name":"mysql-admin","environment":[{"name":"SQL","value":"'"$SQL"'"}]}]}'

aws ecs run-task \
  --cluster <ecs_cluster_name> \
  --launch-type FARGATE \
  --task-definition <mysql_admin_task_definition_arn> \
  --network-configuration "$NETCFG" \
  --overrides "$OVERRIDES"
```

Watch the logs in CloudWatch under `/ecs/azerothcore/mysql-admin`.

## Notes

- Network Load Balancer preserves the client source IP. Because of that, the ECS
  task security group must allow your client CIDRs directly via
  `allowed_ingress_cidrs`. The NLB itself does not have a security group.
- Edit `allowed_ingress.auto.tfvars` to add or remove approved player IPs. This
  file is intended to be easy to update via pull request with `/32` entries for
  each player's public IP.
- The official images come from the AzerothCore `acore-docker` project and Docker Hub.
- The DB bootstrap task is the official AzerothCore importer/bootstrap image.
  It is not the old custom "load an arbitrary SQL dump from S3" flow.
