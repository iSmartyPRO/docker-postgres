.DEFAULT_GOAL := help

.PHONY: help setup env network up down restart recreate pull ps health wait version \
        logs logs-postgres shell info \
        backup backup-list restore \
        psql sql dbs db-create db-drop db-size \
        users user-create user-drop extensions connections vacuum

# Optional overrides: DB, USER, PASSWORD, SQL, BACKUP, FORCE, OWNER
DB ?=
USER ?=
PASSWORD ?=
SQL ?=
BACKUP ?=
FORCE ?=
OWNER ?=

help:
	@echo "PostgreSQL stack — available commands:"
	@echo ""
	@echo "  Setup & lifecycle:"
	@echo "    make setup          Create .env with generated password, prepare scripts"
	@echo "    make env            Create .env if missing"
	@echo "    make network        Create docker-lan network if missing"
	@echo "    make up             Start PostgreSQL"
	@echo "    make down           Stop PostgreSQL"
	@echo "    make restart        Restart PostgreSQL container"
	@echo "    make recreate       down + up"
	@echo "    make pull           Pull updated images"
	@echo "    make ps             Container status"
	@echo ""
	@echo "  Monitoring:"
	@echo "    make health         Check PostgreSQL readiness"
	@echo "    make wait           Wait until PostgreSQL is ready"
	@echo "    make version        Show PostgreSQL version"
	@echo "    make info           Show connection info from .env"
	@echo "    make logs           Follow all logs"
	@echo "    make logs-postgres  Follow PostgreSQL logs"
	@echo "    make connections    Show active connections"
	@echo ""
	@echo "  Shell & SQL:"
	@echo "    make psql           Interactive psql (default DB from .env)"
	@echo "    make psql DB=name   Interactive psql to specific database"
	@echo "    make sql SQL='...'  Run SQL query"
	@echo "    make shell          Bash shell inside postgres container"
	@echo ""
	@echo "  Databases:"
	@echo "    make dbs            List databases"
	@echo "    make db-create DB=name [OWNER=user]  Create database"
	@echo "    make db-drop DB=name [FORCE=1]       Drop database"
	@echo "    make db-size [DB=name]                 Show database size"
	@echo ""
	@echo "  Users:"
	@echo "    make users          List roles"
	@echo "    make user-create USER=name PASSWORD=secret  Create role"
	@echo "    make user-drop USER=name [FORCE=1]          Drop role"
	@echo ""
	@echo "  Maintenance:"
	@echo "    make extensions     List installed extensions"
	@echo "    make vacuum [DB=name]  VACUUM ANALYZE"
	@echo "    make backup         Backup default DB to backups/"
	@echo "    make backup-list    List available backups"
	@echo "    make restore BACKUP=backups/file.sql.gz [FORCE=1]"

setup: env
	@chmod +x scripts/*.sh
	@echo "✓ Setup complete"

env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		PG_PASS=$$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24); \
		sed -i "s/change_me_strong_password/$$PG_PASS/" .env; \
		echo "✓ .env created with generated password"; \
	else \
		echo "✓ .env already exists"; \
	fi

network:
	@docker network inspect docker-lan >/dev/null 2>&1 \
		|| (docker network create docker-lan && echo "✓ docker-lan network created")

up: network
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart postgres

recreate: down up

pull:
	docker compose pull

ps:
	docker compose ps

health:
	@set -a && . ./.env && set +a && \
		docker compose exec postgres pg_isready -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"

wait:
	@set -a && . ./.env && set +a && \
		echo "Waiting for PostgreSQL..." && \
		until docker compose exec postgres pg_isready -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" >/dev/null 2>&1; do sleep 1; done && \
		echo "✓ PostgreSQL is ready"

version:
	@set -a && . ./.env && set +a && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -tAc "SELECT version();"

info:
	@set -a && . ./.env && set +a && \
		echo "Host:      0.0.0.0 (all interfaces, or postgres on docker-lan)" && \
		echo "Port:      $${POSTGRES_PORT:-5432}" && \
		echo "Database:  $$POSTGRES_DB" && \
		echo "User:      $$POSTGRES_USER" && \
		echo "Version:   $${POSTGRES_VERSION:-18.4-alpine}" && \
		echo "Timezone:  $${TZ:-UTC}" && \
		echo "URL:       postgresql://$$POSTGRES_USER:<password>@<host>:$${POSTGRES_PORT:-5432}/$$POSTGRES_DB"

logs:
	docker compose logs -f

logs-postgres:
	docker compose logs -f postgres

shell:
	docker compose exec -it postgres bash

backup:
	@./scripts/backup.sh

backup-list:
	@ls -lh backups/*.sql.gz 2>/dev/null || echo "No backups found in backups/"

restore:
	@FORCE=$(FORCE) ./scripts/restore.sh $(BACKUP)

psql:
	@set -a && . ./.env && set +a && \
		TARGET_DB="$${DB:-$$POSTGRES_DB}" && \
		docker compose exec -it postgres psql -U "$$POSTGRES_USER" -d "$$TARGET_DB"

sql:
	@set -a && . ./.env && set +a && \
		if [ -z "$(SQL)" ]; then echo "Usage: make sql SQL='SELECT 1'" >&2; exit 1; fi && \
		TARGET_DB="$${DB:-$$POSTGRES_DB}" && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d "$$TARGET_DB" -c "$(SQL)"

dbs:
	@set -a && . ./.env && set +a && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d postgres -c \
		"SELECT datname AS database, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database WHERE datistemplate = false ORDER BY datname;"

db-create:
	@set -a && . ./.env && set +a && \
		if [ -z "$(DB)" ]; then echo "Usage: make db-create DB=name [OWNER=user]" >&2; exit 1; fi && \
		OWNER_NAME="$(OWNER)"; \
		[ -n "$$OWNER_NAME" ] || OWNER_NAME="$$POSTGRES_USER"; \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d postgres -c \
		"CREATE DATABASE \"$(DB)\" OWNER \"$$OWNER_NAME\";" && \
		echo "✓ Database '$(DB)' created (owner: $$OWNER_NAME)"

db-drop:
	@set -a && . ./.env && set +a && \
		if [ -z "$(DB)" ]; then echo "Usage: make db-drop DB=name [FORCE=1]" >&2; exit 1; fi && \
		if [ "$(DB)" = "$$POSTGRES_DB" ] && [ "$(FORCE)" != "1" ]; then \
			echo "Refusing to drop default database $$POSTGRES_DB. Use FORCE=1 to override." >&2; exit 1; \
		fi && \
		if [ "$(FORCE)" != "1" ]; then \
			printf "Drop database '$(DB)'? [y/N] " && read -r confirm && \
			[ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "Aborted." && exit 0); \
		fi && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d postgres -c \
		"DROP DATABASE IF EXISTS \"$(DB)\";" && \
		echo "✓ Database '$(DB)' dropped"

db-size:
	@set -a && . ./.env && set +a && \
		TARGET_DB="$${DB:-$$POSTGRES_DB}" && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d "$$TARGET_DB" -tAc \
		"SELECT pg_size_pretty(pg_database_size(current_database()));"

users:
	@set -a && . ./.env && set +a && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d postgres -c \
		"SELECT rolname AS role, rolsuper AS superuser, rolcreatedb AS createdb, rolcanlogin AS login FROM pg_roles WHERE rolname NOT LIKE 'pg_%' ORDER BY rolname;"

user-create:
	@set -a && . ./.env && set +a && \
		if [ -z "$(USER)" ] || [ -z "$(PASSWORD)" ]; then \
			echo "Usage: make user-create USER=name PASSWORD=secret" >&2; exit 1; \
		fi && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d postgres -c \
		"CREATE ROLE \"$(USER)\" WITH LOGIN PASSWORD '$(PASSWORD)';" && \
		echo "✓ Role '$(USER)' created"

user-drop:
	@set -a && . ./.env && set +a && \
		if [ -z "$(USER)" ]; then echo "Usage: make user-drop USER=name [FORCE=1]" >&2; exit 1; fi && \
		if [ "$(USER)" = "$$POSTGRES_USER" ] && [ "$(FORCE)" != "1" ]; then \
			echo "Refusing to drop default user $$POSTGRES_USER. Use FORCE=1 to override." >&2; exit 1; \
		fi && \
		if [ "$(FORCE)" != "1" ]; then \
			printf "Drop role '$(USER)'? [y/N] " && read -r confirm && \
			[ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "Aborted." && exit 0); \
		fi && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d postgres -c \
		"DROP ROLE IF EXISTS \"$(USER)\";" && \
		echo "✓ Role '$(USER)' dropped"

extensions:
	@set -a && . ./.env && set +a && \
		TARGET_DB="$${DB:-$$POSTGRES_DB}" && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d "$$TARGET_DB" -c \
		"SELECT extname AS extension, extversion AS version FROM pg_extension ORDER BY extname;"

connections:
	@set -a && . ./.env && set +a && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -c \
		"SELECT pid, usename, datname, client_addr, state, query_start, left(query, 60) AS query FROM pg_stat_activity WHERE pid <> pg_backend_pid() ORDER BY query_start;"

vacuum:
	@set -a && . ./.env && set +a && \
		TARGET_DB="$${DB:-$$POSTGRES_DB}" && \
		echo "Running VACUUM ANALYZE on $$TARGET_DB..." && \
		docker compose exec -T postgres psql -U "$$POSTGRES_USER" -d "$$TARGET_DB" -c "VACUUM ANALYZE;" && \
		echo "✓ Done"
