# Arsenal FC Analytics Platform - Makefile
# Convenience commands for common operations

.PHONY: help start stop restart logs clean test db-shell airflow-shell build up-build

help: ## Show this help message
	@echo "Arsenal FC Analytics Platform - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  make start          - Start all services"
	@echo "  make load-data      - Load historical data (first time)"
	@echo "  make status         - Check service status"
	@echo ""

# ============================================================================
# Main Commands
# ============================================================================

up: start ## Alias for start ## Start all services
	@echo "🚀 Starting Arsenal FC Analytics Platform..."
	docker compose up -d
	@echo "✅ Services started!"
	@echo ""
	@echo "Access URLs:"
	@echo "  📊 Frontend:  http://localhost:3000"
	@echo "  🔌 Backend:   http://localhost:4000/graphql"
	@echo "  🌪️  Airflow:   http://localhost:8080 (admin/admin)"
	@echo "  🗄️  PostgreSQL: localhost:5432"

build: ## Build all Docker images
	@echo "🔨 Building Docker images..."
	docker compose build

up-build: ## Build and start all services
	@echo "🔨 Building and starting services..."
	docker compose up --build -d
	@echo "✅ Services built and started!"

down: stop ## Alias for stop ## Stop all services
	@echo "🛑 Stopping services..."
	docker compose down
	@echo "✅ Services stopped"

restart: ## Restart all services
	@echo "🔄 Restarting services..."
	docker compose down
	docker compose up -d
	@echo "✅ Services restarted"

status: ## Check status of all services
	@echo "📊 Service Status:"
	@docker compose ps
	@echo ""
	@echo "Health Checks:"
	@echo -n "  Frontend:  "
	@curl -s http://localhost:3000 > /dev/null && echo "✅" || echo "❌"
	@echo -n "  Backend:   "
	@curl -s http://localhost:4000/health > /dev/null && echo "✅" || echo "❌"
	@echo -n "  Airflow:   "
	@curl -s http://localhost:8080/health > /dev/null && echo "✅" || echo "❌"
	@echo -n "  PostgreSQL: "
	@docker exec arsenalfc_postgres pg_isready -U analytics_user > /dev/null 2>&1 && echo "✅" || echo "❌"

# ============================================================================
# Logs
# ============================================================================

logs: ## View logs from all services
	docker compose logs -f

logs-backend: ## View backend logs
	docker compose logs -f backend

logs-frontend: ## View frontend logs
	docker compose logs -f frontend

logs-postgres: ## View PostgreSQL logs
	docker compose logs -f postgres

logs-airflow: ## View Airflow scheduler logs
	docker compose logs -f airflow-scheduler

logs-airflow-web: ## View Airflow webserver logs
	docker compose logs -f airflow-webserver

# ============================================================================
# Database
# ============================================================================

db-shell: ## Open PostgreSQL shell
	docker exec -it arsenalfc_postgres psql -U analytics_user -d arsenalfc_analytics

db-check: ## Check if database has data
	@echo "📊 Checking database..."
	@docker exec arsenalfc_postgres psql -U analytics_user -d arsenalfc_analytics \
		-c "SELECT COUNT(*) as total_matches FROM bronze.understat_raw;" || echo "❌ Database not accessible"

db-stats: ## Show database statistics
	@echo "📊 Database Statistics:"
	@docker exec arsenalfc_postgres psql -U analytics_user -d arsenalfc_analytics \
		-c "SELECT schemaname, tablename, n_live_tup as rows FROM pg_stat_user_tables ORDER BY n_live_tup DESC;"

load-data: ## Load historical data (first time setup)
	@echo "📥 Loading historical match data..."
	@docker exec arsenalfc_airflow_scheduler python /opt/airflow/scripts/backfill_all.py
	@echo "✅ Data loaded!"

init-db: ## Initialize database (first time setup)
	@echo "🗄️  Initializing database..."
	docker compose up -d postgres
	@echo "⏳ Waiting for PostgreSQL to be ready..."
	@sleep 10
	@echo "✅ Database initialized!"

backup-db: ## Backup database to file
	@echo "💾 Backing up database..."
	@docker exec arsenalfc_postgres pg_dump -U analytics_user arsenalfc_analytics > backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "✅ Backup created!"

restore-db: ## Restore database from backup (usage: make restore-db FILE=backup.sql)
	@if [ -z "$(FILE)" ]; then echo "❌ Usage: make restore-db FILE=backup.sql"; exit 1; fi
	@echo "📥 Restoring database from $(FILE)..."
	@docker exec -i arsenalfc_postgres psql -U analytics_user arsenalfc_analytics < $(FILE)
	@echo "✅ Restore completed!"

# ============================================================================
# Airflow
# ============================================================================

airflow-shell: ## Open Airflow scheduler shell
	docker exec -it arsenalfc_airflow_scheduler bash

airflow-enable-dag: ## Enable smart match scraper DAG
	@echo "🌪️  Enabling smart match scraper DAG..."
	@docker exec arsenalfc_airflow_scheduler airflow dags unpause arsenal_smart_match_scraper
	@echo "✅ DAG enabled!"

airflow-list-dags: ## List all Airflow DAGs
	@docker exec arsenalfc_airflow_scheduler airflow dags list

airflow-trigger-manual: ## Manually trigger match scraper
	@echo "🔄 Triggering manual match scraper..."
	@docker exec arsenalfc_airflow_scheduler airflow dags trigger arsenal_manual_match_scraper
	@echo "✅ DAG triggered!"

# ============================================================================
# Development
# ============================================================================

backend-shell: ## Open backend container shell
	docker exec -it arsenalfc_backend sh

frontend-shell: ## Open frontend container shell
	docker exec -it arsenalfc_frontend sh

rebuild-backend: ## Rebuild backend service
	@echo "🔨 Rebuilding backend..."
	docker compose up --build -d backend
	@echo "✅ Backend rebuilt!"

rebuild-frontend: ## Rebuild frontend service
	@echo "🔨 Rebuilding frontend..."
	docker compose up --build -d frontend
	@echo "✅ Frontend rebuilt!"

# ============================================================================
# Testing & Verification
# ============================================================================

test-backend: ## Test backend GraphQL API
	@echo "🧪 Testing backend GraphQL API..."
	@curl -s -X POST http://localhost:4000/graphql \
		-H "Content-Type: application/json" \
		-d '{"query":"{ seasons }"}' | jq '.' || echo "❌ Backend not responding"

test-frontend: ## Test frontend is accessible
	@echo "🧪 Testing frontend..."
	@curl -s http://localhost:3000 > /dev/null && echo "✅ Frontend is up" || echo "❌ Frontend not responding"

test-all: ## Test all services
	@echo "🧪 Testing all services..."
	@make test-backend
	@make test-frontend
	@make db-check

# ============================================================================
# Cleanup
# ============================================================================

clean: ## Remove all containers, volumes, and data (WARNING: deletes data)
	@echo "⚠️  WARNING: This will delete all data!"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "🧹 Cleaning up..."
	docker compose down -v
	@echo "✅ Cleaned up successfully"

clean-containers: ## Remove containers but keep volumes
	@echo "🧹 Removing containers..."
	docker compose down
	@echo "✅ Containers removed (data preserved)"

# ============================================================================
# Quick Actions
# ============================================================================

quick-start: ## Quick start: build, start, load data, enable DAG
	@echo "🚀 Quick Start - Setting up everything..."
	@make up-build
	@echo "⏳ Waiting for services to be ready..."
	@sleep 30
	@make load-data
	@make airflow-enable-dag
	@echo ""
	@echo "✅ Platform is ready!"
	@echo "  📊 Frontend: http://localhost:3000"
	@echo "  🔌 Backend:  http://localhost:4000/graphql"
	@echo "  🌪️  Airflow:  http://localhost:8080"

full-restart: ## Full restart: stop, clean, rebuild, start, load data
	@echo "🔄 Full restart..."
	@make stop
	@make clean-containers
	@make up-build
	@echo "⏳ Waiting for services..."
	@sleep 30
	@make load-data
	@make airflow-enable-dag
	@echo "✅ Full restart complete!"

# ============================================================================
# Information
# ============================================================================

version: ## Show platform version
	@echo "Arsenal FC Analytics Platform v2.0.0"
	@echo ""
	@echo "Components:"
	@echo "  - Frontend:  Next.js 14 + React 18"
	@echo "  - Backend:   Node.js 20 + GraphQL (Apollo Server)"
	@echo "  - Airflow:   2.8.1"
	@echo "  - PostgreSQL: 15"
	@echo ""
	@echo "Ports:"
	@echo "  - Frontend:  3000"
	@echo "  - Backend:   4000"
	@echo "  - Airflow:   8080"
	@echo "  - PostgreSQL: 5432"

info: ## Show platform information and URLs
	@echo "📊 Arsenal FC Analytics Platform"
	@echo ""
	@echo "Access URLs:"
	@echo "  📊 Frontend (Website):  http://localhost:3000"
	@echo "  🔌 Backend (GraphQL):   http://localhost:4000/graphql"
	@echo "  🌪️  Airflow UI:          http://localhost:8080"
	@echo "  🗄️  PostgreSQL:           localhost:5432"
	@echo ""
	@echo "Credentials:"
	@echo "  Airflow:     admin / admin"
	@echo "  PostgreSQL: analytics_user / analytics_pass"
	@echo ""
	@make status

# ============================================================================
# Default target
# ============================================================================

.DEFAULT_GOAL := help
