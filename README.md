# AzerothCore AWS Terraform

This repo provisions an AzerothCore stack on AWS using the official precompiled
`acore` Docker Hub images instead of building AzerothCore from source.

## Summary

- Public NLB listeners on `3724` and `8085`
- ECS Fargate services for `authserver` and `worldserver`
- RDS MySQL 8.4 in private subnets
- EFS mounted into `worldserver` at `/azerothcore/env/dist/data`
- One-off ECS task definition for the official `acore/ac-wotlk-client-data` image
- One-off ECS task definition for the official `acore/ac-wotlk-db-import` bootstrap image
- CloudWatch Logs and Secrets Manager for runtime configuration

## Default Images

- `acore/ac-wotlk-authserver@sha256:cc1a457c5bedc3db65248527757eab15232f9c338f38d7c7fc8e7d58fa97a247`
- `acore/ac-wotlk-client-data@sha256:76919b5d8080c0ac55ec17299a79e30bbbd94fae778465b742045af0c806db02`
- `acore/ac-wotlk-worldserver@sha256:abda30081e74c1d56f8c8728541cf8605e6716c828ea13a139dbc76c1175df53`
- `acore/ac-wotlk-db-import:master`

`authserver`, `worldserver`, and `client-data` are pinned intentionally so they do not drift with `:master`.
`db-import` remains on `:master` for now because the exact successful digest was no longer recoverable from ECS.

## Quick Start

1. Create the remote state bucket.
1. `terraform init`
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

## One-Off Auth and Characters Transfer

Terraform also manages a temporary S3 bucket for one-off auth and characters DB
transfer artifacts. Apply Terraform before using the scripts below, then remove
the bucket resource after the migration is finished.

Dump and upload local native-MySQL `acore_auth` and `acore_characters`:

```bash
scripts/export-local-auth-characters.sh
```

That script uploads compressed dumps to the transfer bucket and prints the
prefix to use for the cloud-side import.

Import those dumps into the private RDS instance, restore the `realmlist` row to
the NLB DNS name and world port, and bring the ECS services back up:

```bash
scripts/import-cloud-auth-characters.sh <transfer-prefix>
```

The import script:

- scales `azerothcore-authserver` and `azerothcore-worldserver` down to `0`
- imports `acore_auth` and `acore_characters` from the transfer bucket
- updates `acore_auth.realmlist` back to the public NLB DNS name and `8085`
- verifies the `realmlist` row through the existing `mysql-admin` ECS task
- restores the prior ECS service counts

Set `LOCAL_DB_HOST`, `LOCAL_DB_PORT`, `LOCAL_DB_USER`, `LOCAL_DB_PASSWORD`, or
`TRANSFER_PREFIX` before running the export script if your local MySQL differs
from the defaults.

## Local Smoke Test

The local [docker-compose.yml](/Users/thekbb/wow-infra/docker-compose.yml) uses
the official `acore` images too. It starts:

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

The official worldserver image expects maps/vmaps/mmaps in `/azerothcore/env/dist/data`. Populate the EFS filesystem
before players connect. The `client-data` ECS task above is the intended cloud bootstrap path for that.

Then initialize Terraform normally:

```bash
terraform init
```

## Notes

- Network Load Balancer preserves the client source IP. Because of that, the ECS
  task security group must allow your client CIDRs directly via
  `allowed_ingress_cidrs`. The NLB itself does not have a security group.
- The official images come from the AzerothCore `acore-docker` project and Docker Hub.
- The DB bootstrap task is the official AzerothCore importer/bootstrap image.
  It is not the old custom "load an arbitrary SQL dump from S3" flow.
