#!/usr/bin/env bash
# ==============================================================================
# AWS RDS PostgreSQL Ephemeral Test Environment Manager
# ==============================================================================
# Manages a low-cost AWS RDS PostgreSQL instance (db.t4g.micro, 20GB gp3,
# 0-day backup retention, single-AZ) for testing User Manager for PostgreSQL.
#
# Usage:
#   ./scripts/aws_rds_test_env.sh up          # Create (or start) RDS instance & bootstrap dbroles
#   ./scripts/aws_rds_test_env.sh status      # Show instance state and endpoint hostname
#   ./scripts/aws_rds_test_env.sh bootstrap   # Re-run SQL setup (dbroles + sample roles/users)
#   ./scripts/aws_rds_test_env.sh stop        # Stop instance (pauses compute for up to 7 days)
#   ./scripts/aws_rds_test_env.sh start       # Start a stopped instance
#   ./scripts/aws_rds_test_env.sh down        # Delete instance completely ($0 ongoing cost)
#
# Optional Environment Variables:
#   AWS_REGION          AWS region (defaults to aws configure region or eu-central-1)
#   INSTANCE_ID         RDS DB instance identifier (default: pg-usermanager-test)
#   DB_NAME             Initial database name (default: postgres)
#   MASTER_USER         Master superuser username (default: postgres)
#   MASTER_PASS         Master superuser password (auto-generated or prompted if not set)
#   DBROLES_USER        Role Admin username for the app (default: dbroles)
#   DBROLES_PASS        Role Admin password for the app (default: same as MASTER_PASS)
#   AWS_SG_ID           Existing VPC Security Group ID (auto-created if omitted)
#   ALLOWED_CIDR        CIDR allowed on port 5432 (default: <your-public-ip>/32)
# ==============================================================================

set -euo pipefail

# Automatically load .env from project root if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

INSTANCE_ID="${INSTANCE_ID:-pg-usermanager-test}"
DB_NAME="${DB_NAME:-postgres}"
MASTER_USER="${MASTER_USER:-postgres}"
DBROLES_USER="${DBROLES_USER:-dbroles}"
INSTANCE_CLASS="${INSTANCE_CLASS:-db.t4g.micro}"
ALLOCATED_STORAGE="${ALLOCATED_STORAGE:-20}"
SG_NAME="${SG_NAME:-pg-usermanager-test-sg}"

REGION_ARGS=()
if [[ -n "${AWS_REGION:-}" ]]; then
  REGION_ARGS=(--region "$AWS_REGION")
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Required command '$1' is not installed." >&2
    exit 1
  fi
}

get_instance_status() {
  aws rds describe-db-instances \
    "${REGION_ARGS[@]}" \
    --db-instance-identifier "$INSTANCE_ID" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "not-found"
}

get_instance_endpoint() {
  aws rds describe-db-instances \
    "${REGION_ARGS[@]}" \
    --db-instance-identifier "$INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text 2>/dev/null || echo ""
}

ensure_security_group() {
  if [[ -n "${AWS_SG_ID:-}" ]]; then
    echo "$AWS_SG_ID"
    return
  fi

  local vpc_id
  vpc_id=$(aws ec2 describe-vpcs \
    "${REGION_ARGS[@]}" \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

  if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
    echo "Error: Could not find a default VPC. Please set AWS_SG_ID explicitly." >&2
    exit 1
  fi

  local sg_id
  sg_id=$(aws ec2 describe-security-groups \
    "${REGION_ARGS[@]}" \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$vpc_id" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

  if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
    echo "Creating security group '$SG_NAME' in VPC $vpc_id..." >&2
    sg_id=$(aws ec2 create-security-group \
      "${REGION_ARGS[@]}" \
      --group-name "$SG_NAME" \
      --description "Allow PostgreSQL 5432 for User Manager test instance" \
      --vpc-id "$vpc_id" \
      --query 'GroupId' \
      --output text)
  fi

  local cidr="${ALLOWED_CIDR:-}"
  if [[ -z "$cidr" ]]; then
    local my_ip
    my_ip=$(curl -fsSL https://checkip.amazonaws.com | tr -d '[:space:]')
    cidr="${my_ip}/32"
  fi

  echo "Ensuring inbound port 5432 is open for $cidr on $sg_id..." >&2
  aws ec2 authorize-security-group-ingress \
    "${REGION_ARGS[@]}" \
    --group-id "$sg_id" \
    --protocol tcp \
    --port 5432 \
    --cidr "$cidr" >/dev/null 2>&1 || true

  echo "$sg_id"
}

bootstrap_sql() {
  local endpoint="$1"
  local master_pass="$2"
  local dbroles_pass="${DBROLES_PASS:-$master_pass}"

  if ! command -v psql >/dev/null 2>&1; then
    echo ""
    echo "Note: 'psql' is not installed locally, skipping automatic SQL bootstrap."
    echo "You can connect in the app as '$MASTER_USER' and use the Create Role Admin dialog,"
    echo "or install libpq/psql and run: ./scripts/aws_rds_test_env.sh bootstrap"
    return
  fi

  echo "Bootstrapping '$DBROLES_USER' and sample roles on $endpoint..."
  PGPASSWORD="$master_pass" psql \
    "sslmode=require host=$endpoint port=5432 dbname=$DB_NAME user=$MASTER_USER" \
    -v dbroles_user="$DBROLES_USER" \
    -v dbroles_pass="$dbroles_pass" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dbroles') THEN
    CREATE ROLE dbroles WITH LOGIN CREATEROLE;
  ELSE
    ALTER ROLE dbroles WITH LOGIN CREATEROLE;
  END IF;
END
$$;

ALTER ROLE :"dbroles_user" WITH PASSWORD :'dbroles_pass';
COMMENT ON ROLE :"dbroles_user" IS 'grant and revoke roles to users';

-- Create sample non-login roles (Groups) and grant ADMIN OPTION to dbroles
DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['developers', 'analysts', 'support', 'readonly', 'finance', 'hr']
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I WITH NOLOGIN', r);
      EXECUTE format('COMMENT ON ROLE %I IS %L', r, initcap(r) || ' access group');
    END IF;
    EXECUTE format('GRANT %I TO dbroles WITH ADMIN OPTION', r);
  END LOOP;
END
$$;
SQL

  echo "SQL bootstrap complete!"
}

cmd_up() {
  require_cmd aws
  local status
  status=$(get_instance_status)

  if [[ "$status" == "not-found" ]]; then
    if [[ -z "${MASTER_PASS:-}" ]]; then
      read -r -s -p "Enter a password for '$MASTER_USER' / '$DBROLES_USER' (min 8 chars): " MASTER_PASS
      echo ""
    fi
    if [[ ${#MASTER_PASS} -lt 8 ]]; then
      echo "Error: Password must be at least 8 characters." >&2
      exit 1
    fi

    local sg_id
    sg_id=$(ensure_security_group)

    echo "Creating RDS PostgreSQL instance '$INSTANCE_ID' ($INSTANCE_CLASS, ${ALLOCATED_STORAGE}GB gp3)..."
    aws rds create-db-instance \
      "${REGION_ARGS[@]}" \
      --db-instance-identifier "$INSTANCE_ID" \
      --engine postgres \
      --db-instance-class "$INSTANCE_CLASS" \
      --allocated-storage "$ALLOCATED_STORAGE" \
      --storage-type gp3 \
      --master-username "$MASTER_USER" \
      --master-user-password "$MASTER_PASS" \
      --db-name "$DB_NAME" \
      --vpc-security-group-ids "$sg_id" \
      --publicly-accessible \
      --backup-retention-period 0 \
      --no-multi-az \
      --no-deletion-protection >/dev/null

    echo "Waiting for '$INSTANCE_ID' to become available (typically 4-6 minutes)..."
    aws rds wait db-instance-available "${REGION_ARGS[@]}" --db-instance-identifier "$INSTANCE_ID"

    local endpoint
    endpoint=$(get_instance_endpoint)
    bootstrap_sql "$endpoint" "$MASTER_PASS"
  elif [[ "$status" == "stopped" ]]; then
    cmd_start
  else
    echo "Instance '$INSTANCE_ID' already exists (status: $status)."
    echo "Waiting until available..."
    aws rds wait db-instance-available "${REGION_ARGS[@]}" --db-instance-identifier "$INSTANCE_ID"
  fi

  cmd_status
}

cmd_bootstrap() {
  require_cmd aws
  require_cmd psql
  local endpoint
  endpoint=$(get_instance_endpoint)
  if [[ -z "$endpoint" || "$endpoint" == "None" ]]; then
    echo "Error: Instance '$INSTANCE_ID' has no endpoint yet." >&2
    exit 1
  fi
  if [[ -z "${MASTER_PASS:-}" ]]; then
    read -r -s -p "Enter master password for '$MASTER_USER': " MASTER_PASS
    echo ""
  fi
  bootstrap_sql "$endpoint" "$MASTER_PASS"
}

cmd_stop() {
  require_cmd aws
  echo "Stopping RDS instance '$INSTANCE_ID'..."
  echo "Reminder: AWS automatically restarts stopped instances after 7 days."
  aws rds stop-db-instance "${REGION_ARGS[@]}" --db-instance-identifier "$INSTANCE_ID" >/dev/null
  echo "Stop requested. Run './scripts/aws_rds_test_env.sh status' to check progress."
}

cmd_start() {
  require_cmd aws
  echo "Starting RDS instance '$INSTANCE_ID'..."
  aws rds start-db-instance "${REGION_ARGS[@]}" --db-instance-identifier "$INSTANCE_ID" >/dev/null
  echo "Waiting for '$INSTANCE_ID' to become available..."
  aws rds wait db-instance-available "${REGION_ARGS[@]}" --db-instance-identifier "$INSTANCE_ID"
  cmd_status
}

cmd_down() {
  require_cmd aws
  local status
  status=$(get_instance_status)
  if [[ "$status" == "not-found" ]]; then
    echo "Instance '$INSTANCE_ID' does not exist."
    return
  fi

  echo "Deleting RDS instance '$INSTANCE_ID' (skipping final snapshot & deleting backups for \$0 cost)..."
  aws rds delete-db-instance \
    "${REGION_ARGS[@]}" \
    --db-instance-identifier "$INSTANCE_ID" \
    --skip-final-snapshot \
    --delete-automated-backups >/dev/null

  echo "Waiting for '$INSTANCE_ID' deletion to complete..."
  aws rds wait db-instance-deleted "${REGION_ARGS[@]}" --db-instance-identifier "$INSTANCE_ID"
  echo "Instance '$INSTANCE_ID' deleted. Ongoing RDS cost is now \$0.00."
}

cmd_status() {
  require_cmd aws
  local status
  status=$(get_instance_status)
  if [[ "$status" == "not-found" ]]; then
    echo "Instance '$INSTANCE_ID': NOT FOUND (deleted / not created)"
    return
  fi

  local endpoint
  endpoint=$(get_instance_endpoint)
  echo "============================================================"
  echo "Instance ID : $INSTANCE_ID"
  echo "Status      : $status"
  echo "Hostname    : ${endpoint:-<pending>}"
  echo "Port        : 5432"
  echo "Database    : $DB_NAME"
  echo "App Login   : $DBROLES_USER"
  echo "SSL         : Required"
  echo "============================================================"
}

case "${1:-status}" in
  up)        cmd_up ;;
  bootstrap) cmd_bootstrap ;;
  stop)      cmd_stop ;;
  start)     cmd_start ;;
  down|destroy|delete) cmd_down ;;
  status)    cmd_status ;;
  *)
    echo "Usage: $0 {up|status|bootstrap|stop|start|down}" >&2
    exit 1
    ;;
esac

