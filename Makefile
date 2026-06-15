.PHONY: setup env up down ps health logs backup restore psql network pull

setup: env
	@chmod +x scripts/*.sh
	@./scripts/setup-pgadmin.sh

env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		PG_PASS=$$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24); \
		ADMIN_PASS=$$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24); \
		sed -i "s/change_me_strong_password/$$PG_PASS/" .env; \
		sed -i "s/change_me_admin_password/$$ADMIN_PASS/" .env; \
		echo "✓ .env created with generated passwords"; \
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

pull:
	docker compose pull

ps:
	docker compose ps

health:
	@set -a && . ./.env && set +a && \
		docker compose exec postgres pg_isready -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"

logs:
	docker compose logs -f

backup:
	@./scripts/backup.sh

restore:
	@./scripts/restore.sh $(BACKUP)

psql:
	@set -a && . ./.env && set +a && \
		docker compose exec -it postgres psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"
