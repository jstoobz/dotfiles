#!/bin/sh
# ============================================================================
# Step 07: PostgreSQL setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/utils.sh"

configure_postgres() {
  info "Starting PostgreSQL and creating default postgres user"

  brew services start postgresql

  # Wait until PostgreSQL is listening
  while ! lsof -i :5432 >/dev/null 2>&1; do sleep 1; done

  createuser -s postgres 2>/dev/null || info "postgres user already exists"
  success "PostgreSQL configured"
}

configure_postgres
