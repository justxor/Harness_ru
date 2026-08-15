#!/usr/bin/env bash
# =============================================================================
#  структура harness: контракты, каталоги, единая точка входа
# =============================================================================
#  Проверяет, что у проекта вообще есть обвязка для агента, а не «мы просто
#  открываем чат и пишем что надо». Это уровень L0: секунды, без модели.
#
#  Настройка через переменные окружения:
#     HARNESS_ROOT        корень проверяемого проекта (по умолчанию — репозиторий)
#     HARNESS_CONTRACTS   список допустимых имён корневого контракта
#     ASSERT_STRICT=1     предупреждения считать провалами
# =============================================================================

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/assert.sh"

ROOT="${HARNESS_ROOT:-$(repo_root)}"
cd "$ROOT" || { echo "нет каталога $ROOT"; exit 1; }

CONTRACTS="${HARNESS_CONTRACTS:-CLAUDE.md AGENTS.md GEMINI.md .cursorrules .github/copilot-instructions.md .windsurfrules}"
ENTRYPOINTS="${HARNESS_ENTRYPOINTS:-Makefile justfile Taskfile.yml package.json pyproject.toml}"
CMD_DIRS="${HARNESS_CMD_DIRS:-.claude/commands .agent/commands .cursor/rules .github/prompts}"

describe "T01 Структура harness ($ROOT)"

# --- 1. Корневой контракт ------------------------------------------------------
# Без него агент каждый раз заново угадывает правила проекта. Это главный
# источник «агент делает не то»: не модель плохая, а контракта нет.
found_contract=""
for f in $CONTRACTS; do
  if [ -f "$f" ]; then found_contract="$f"; break; fi
done

if [ -n "$found_contract" ]; then
  _ok "корневой контракт найден: $found_contract"
else
  _fail "корневой контракт" "не найден ни один из: $CONTRACTS"
fi

# --- 2. Контракт отвечает на четыре обязательных вопроса -----------------------
# Что за проект · как собрать и проверить · что нельзя трогать · где границы.
if [ -n "$found_contract" ]; then
  assert_not_empty "$found_contract" "контракт не пустой"

  assert_contains "$found_contract" "(тест|test|pytest|jest|go test|cargo test)" \
    "контракт объясняет, как запускать тесты"

  assert_contains "$found_contract" "(линт|lint|ruff|eslint|clippy|golangci|форматир)" \
    "контракт объясняет, как линтовать и форматировать"

  assert_contains "$found_contract" "(запрещ|нельзя|не трогай|do not|never|Ограничен)" \
    "контракт содержит явные запреты, а не только пожелания"

  assert_contains "$found_contract" "(структур|архитектур|каталог|модул|layout|дерево)" \
    "контракт описывает, где что лежит"

  # Секретам в контракте не место: он уходит в контекст модели целиком.
  assert_not_contains "$found_contract" "(sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)" \
    "в контракте нет похожего на секрет"

  # Контракт с «всегда думай шаг за шагом» и прочей магией — признак карго-культа.
  if grep -qiE "(думай шаг за шагом|think step by step|ты — эксперт|you are an expert)" "$found_contract"; then
    _warn "в контракте есть ритуальные фразы" "они занимают контекст и ничего не гарантируют; замените на проверяемые правила"
  else
    _ok "в контракте нет ритуальных фраз-заклинаний"
  fi
fi

# --- 3. Единая точка входа для команд ------------------------------------------
# Если «как прогнать тесты» знает только человек, агент будет придумывать.
found_entry=""
for f in $ENTRYPOINTS; do
  if [ -f "$f" ]; then found_entry="$f"; break; fi
done
if [ -n "$found_entry" ]; then
  _ok "единая точка входа найдена: $found_entry"
else
  _fail "единая точка входа" "нет ни одного из: $ENTRYPOINTS — агенту нечего вызвать одной командой"
fi

# --- 4. Каталог воспроизводимых процедур (слэш-команды) ------------------------
found_cmds=""
for d in $CMD_DIRS; do
  if [ -d "$d" ]; then found_cmds="$d"; break; fi
done
if [ -n "$found_cmds" ]; then
  n=$(find "$found_cmds" -type f | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then
    _ok "процедуры агента: $found_cmds ($n шт.)"
  else
    _fail "процедуры агента" "каталог $found_cmds пуст"
  fi
else
  _warn "нет каталога воспроизводимых процедур" "ожидался один из: $CMD_DIRS"
fi

# --- 5. Документация, на которую можно сослаться -------------------------------
if [ -d "docs" ] || [ -d "doc" ] || [ -d "documentation" ]; then
  _ok "есть каталог документации"
else
  _warn "нет каталога docs/" "агенту негде взять контекст глубже одного файла"
fi

assert_file_exists "README.md" "README на месте"

# --- 6. Решения зафиксированы, а не живут в голове -----------------------------
if [ -d "docs/adr" ] || [ -d "adr" ] || [ -d "docs/decisions" ]; then
  _ok "архитектурные решения записаны (ADR)"
else
  _warn "нет ADR" "агент будет переизобретать уже принятые решения"
fi

# --- 7. Гигиена репозитория ----------------------------------------------------
assert_file_exists ".gitignore" "есть .gitignore"

if [ -f ".gitignore" ]; then
  assert_contains ".gitignore" "(\.env|secrets|\*\.log|node_modules|__pycache__|\.venv)" \
    ".gitignore закрывает очевидный мусор и секреты"
fi

# Артефакты агента не должны попадать в историю.
assert_file_absent ".claude/local-state.json" "локальное состояние агента не закоммичено"

# .env в индексе — классическая утечка через контекст агента.
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  _fail ".env не в индексе" ".env закоммичен — агент прочитает секреты и может их процитировать"
else
  _ok ".env не закоммичен"
fi

# --- 8. Тесты продукта вообще есть ---------------------------------------------
if [ -d "tests" ] || [ -d "test" ] || [ -d "spec" ] || ls ./*_test.go >/dev/null 2>&1; then
  _ok "у проекта есть каталог тестов"
else
  _warn "не найден каталог тестов" "без них у агента нет обратной связи, кроме вашего мнения"
fi

# --- 9. Свежесть контракта -----------------------------------------------------
# Контракт, который не меняли полгода при активной разработке, почти наверняка врёт.
if [ -n "$found_contract" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  last=$(git log -1 --format=%ct -- "$found_contract" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ "$last" = "0" ] || [ -z "$last" ]; then
    _skip "не удалось определить дату правки контракта"
  else
    days=$(( (now - last) / 86400 ))
    if [ "$days" -le 120 ]; then
      _ok "контракт правился $days дн. назад"
    else
      _warn "контракт не правился $days дн." "проверьте, что он всё ещё описывает реальность"
    fi
  fi
fi

finish
