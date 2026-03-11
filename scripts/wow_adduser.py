#!/usr/bin/env python3

import getpass
import hashlib
import json
import os
import secrets
import subprocess
import sys
import time

N = int(
    "894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7",
    16,
)
G = 7
MYSQL_ADMIN_LOG_GROUP = "/ecs/azerothcore/mysql-admin"


def run(cmd: list[str], *, capture_output: bool = True) -> str:
    result = subprocess.run(cmd, check=True, text=True, capture_output=capture_output)
    return result.stdout.strip()


def sql_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "''")


def compute_verifier(username: str, password: str) -> tuple[str, str]:
    salt = secrets.token_bytes(32)
    identity = f"{username.upper()}:{password.upper()}".encode("utf-8")
    h1 = hashlib.sha1(identity).digest()
    h2 = hashlib.sha1(salt + h1).digest()
    exponent = int.from_bytes(h2, byteorder="little")
    verifier = pow(G, exponent, N).to_bytes(32, byteorder="little")
    return salt.hex(), verifier.hex()


def build_sql(username: str, password: str, gmlevel: str | None) -> str:
    salt_hex, verifier_hex = compute_verifier(username, password)
    username_sql = sql_escape(username)
    statements = [
        "START TRANSACTION",
        (
            "INSERT INTO account (username, salt, verifier, email, reg_mail) "
            f"VALUES ('{username_sql}', UNHEX('{salt_hex}'), UNHEX('{verifier_hex}'), '', '')"
        ),
    ]
    if gmlevel is not None:
        statements.append("SET @account_id = LAST_INSERT_ID()")
        statements.append(
            "INSERT INTO account_access (id, gmlevel, RealmID, comment) "
            f"VALUES (@account_id, {int(gmlevel)}, -1, 'Created by wow:adduser')"
        )
    statements.append("COMMIT")
    return "; ".join(statements) + ";"


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if value:
        return value
    print(
        f"{name} is required. Usage: task wow:adduser ACCOUNT_NAME=<name> [GMLEVEL=3]",
        file=sys.stderr,
    )
    sys.exit(1)


def main() -> int:
    username = require_env("ACCOUNT_NAME")
    if len(username) > 20:
        print(
            "ACCOUNT_NAME must be 20 characters or fewer for AzerothCore accounts.",
            file=sys.stderr,
        )
        return 1

    gmlevel = os.environ.get("GMLEVEL", "").strip() or None
    if gmlevel is not None:
        try:
            gmlevel_int = int(gmlevel)
        except ValueError:
            print("GMLEVEL must be an integer.", file=sys.stderr)
            return 1
        if gmlevel_int < 0 or gmlevel_int > 4:
            print("GMLEVEL must be between 0 and 4.", file=sys.stderr)
            return 1
        gmlevel = str(gmlevel_int)

    password = os.environ.get("PASSWORD", "")
    if not password:
        password = getpass.getpass("Password: ")
    if not password:
        print("Password is required.", file=sys.stderr)
        return 1

    cluster = run(["terraform", "output", "-raw", "ecs_cluster_name"])
    mysql_admin_task = run(["terraform", "output", "-raw", "mysql_admin_task_definition_arn"])
    security_group = run(["terraform", "output", "-raw", "ecs_security_group_id"])
    subnets = run(["terraform", "output", "-json", "private_subnet_ids"])
    subnet_list = ",".join(json.loads(subnets))
    sql = build_sql(username, password, gmlevel)
    overrides = json.dumps(
        {
            "containerOverrides": [
                {
                    "name": "mysql-admin",
                    "environment": [
                        {"name": "SQL", "value": sql},
                    ],
                }
            ]
        }
    )
    network = (
        "awsvpcConfiguration="
        f"{{subnets=[{subnet_list}],securityGroups=[{security_group}],assignPublicIp=DISABLED}}"
    )

    run_task_output = run(
        [
            "aws",
            "ecs",
            "run-task",
            "--cluster",
            cluster,
            "--launch-type",
            "FARGATE",
            "--task-definition",
            mysql_admin_task,
            "--network-configuration",
            network,
            "--overrides",
            overrides,
        ]
    )
    run_task = json.loads(run_task_output)
    if run_task.get("failures"):
        print(json.dumps(run_task["failures"], indent=2), file=sys.stderr)
        return 1

    task_arn = run_task["tasks"][0]["taskArn"]
    task_id = task_arn.rsplit("/", 1)[-1]
    print(f"Started mysql-admin task for user '{username}'.", flush=True)
    print(f"Task ARN: {task_arn}", flush=True)

    print("Waiting for task to stop...", flush=True)
    last_task_status = None
    last_container_status = None
    last_progress_at = time.monotonic()
    while True:
        describe_output = run(
            ["aws", "ecs", "describe-tasks", "--cluster", cluster, "--tasks", task_arn]
        )
        task = json.loads(describe_output)["tasks"][0]
        container = task["containers"][0]
        task_status = task.get("lastStatus", "UNKNOWN")
        container_status = container.get("lastStatus", "UNKNOWN")
        if task_status != last_task_status or container_status != last_container_status:
            print(
                f"Task status: {task_status}; container status: {container_status}",
                flush=True,
            )
            last_task_status = task_status
            last_container_status = container_status
            last_progress_at = time.monotonic()
        elif time.monotonic() - last_progress_at >= 30:
            print(
                f"Still waiting. Task status: {task_status}; container status: {container_status}",
                flush=True,
            )
            last_progress_at = time.monotonic()
        if task_status == "STOPPED":
            break
        time.sleep(5)

    container = task["containers"][0]

    stream_name = f"mysql-admin/mysql-admin/{task_id}"
    print(f"Fetching logs from {MYSQL_ADMIN_LOG_GROUP}:{stream_name}", flush=True)
    logs_output = run(
        [
            "aws",
            "logs",
            "get-log-events",
            "--log-group-name",
            MYSQL_ADMIN_LOG_GROUP,
            "--log-stream-name",
            stream_name,
            "--query",
            "events[].message",
            "--output",
            "text",
        ]
    )
    if logs_output:
        print(logs_output)

    exit_code = container.get("exitCode")
    if exit_code != 0:
        print(
            f"mysql-admin task failed with exit code {exit_code}: {task.get('stoppedReason', 'unknown')}",
            file=sys.stderr,
        )
        return 1

    print(f"Account task completed for user '{username}'.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
