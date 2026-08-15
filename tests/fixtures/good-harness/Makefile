# Makefile — единая точка входа для агента и человека (fixture: good-harness).
# Правило: если процедуры нет в Makefile, её не существует.

.PHONY: help quick test lint types migrate-check api-diff test-race ci

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## /  —  /'

quick: lint ## быстрая петля обратной связи: до 20 секунд
	pytest tests/unit -q --maxfail=1

test: lint types ## полные ворота перед коммитом
	pytest tests -q

lint: ## линтер и форматтер
	ruff check src tests
	ruff format --check src tests

types: ## строгая проверка типов
	mypy --strict src

migrate-check: ## миграции обратно совместимы
	alembic check

api-diff: ## публичный API не изменился
	python -m tools.api_diff --baseline docs/api-baseline.json

test-race: ## тесты на гонки, 50 повторов
	pytest tests/concurrency -q --count=50

ci: test migrate-check api-diff ## то же, что гоняет CI: паритет обязателен
