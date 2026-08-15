# tests/Makefile — единая точка входа для тестов harness.
# Каталог тестов — тоже часть harness, и правило про единую точку входа
# распространяется и на него.
#
#   make -C tests            справка
#   make -C tests test       все наборы
#   HARNESS_ROOT=~/proj make -C tests test

SHELL := /bin/bash
HERE  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT  ?= $(abspath $(HERE)..)

export HARNESS_ROOT ?= $(ROOT)

.DEFAULT_GOAL := help
.PHONY: help test quick strict list structure budget commands gates golden selftest quiz quiz-check pytest fixtures-good fixtures-bad

help: ## список целей
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | sed 's/:.*## /  —  /'
	@echo ""
	@echo "  проверяемый корень: $(HARNESS_ROOT)"

test: ## все наборы тестов harness
	@bash $(HERE)run_all.sh

quick: structure budget ## только самое быстрое: структура и бюджет

strict: ## все наборы, предупреждения считаются провалами
	@ASSERT_STRICT=1 bash $(HERE)run_all.sh

list: ## список наборов
	@bash $(HERE)run_all.sh --list

structure: ## T01 структура harness
	@bash $(HERE)test_01_structure.sh

budget: ## T02 бюджет контекста
	@bash $(HERE)test_02_context_budget.sh

commands: ## T03 слэш-команды
	@bash $(HERE)test_03_commands.sh

gates: ## T04 ворота и хуки
	@bash $(HERE)test_04_gates_and_hooks.sh

golden: ## T05 золотой набор (статика, без модели)
	@bash $(HERE)test_05_golden_tasks.sh

selftest: ## T06 тесты обязаны падать на сломанной фикстуре
	@bash $(HERE)test_06_selftest.sh

fixtures-good: ## прогнать всё на эталонной фикстуре (ожидается зелёный)
	@HARNESS_ROOT=$(HERE)fixtures/good-harness bash $(HERE)run_all.sh

fixtures-bad: ## прогнать всё на сломанной фикстуре (ожидается красный)
	@HARNESS_ROOT=$(HERE)fixtures/bad-harness bash $(HERE)run_all.sh; test $$? -ne 0

quiz: ## самопроверка по курсу: 10 случайных вопросов
	@bash $(HERE)quiz/quiz.sh -n 10

quiz-check: ## проверить целостность файла вопросов
	@bash $(HERE)quiz/quiz.sh --check

pytest: ## та же логика на pytest
	@python3 -m pytest $(HERE)test_harness.py -q
