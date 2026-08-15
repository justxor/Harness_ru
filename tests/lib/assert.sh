#!/usr/bin/env bash
# =============================================================================
#  tests/lib/assert.sh — минимальная библиотека ассертов для тестов harness
#  Курс: https://github.com/justxor/Harness_ru
#
#  Зависимости: bash 4+, coreutils, grep. Ставить ничего не нужно.
#
#  Философия. Harness — это код. Код без тестов деградирует (второй закон
#  Лемана). Но тест на harness напишут только если он пишется за три строки.
#  Отсюда требования к этой библиотеке: ноль зависимостей, ноль конфигурации,
#  человекочитаемый вывод и честный код возврата.
#
#  Пример:
#     #!/usr/bin/env bash
#     source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/assert.sh"
#     describe "T01 Структура harness"
#     assert_file_exists "CLAUDE.md" "корневой контракт агента"
#     finish
# =============================================================================

set -uo pipefail

# --- состояние ---------------------------------------------------------------
ASSERT_PASS=0
ASSERT_FAIL=0
ASSERT_SKIP=0
ASSERT_SUITE="${ASSERT_SUITE:-suite}"
ASSERT_STRICT="${ASSERT_STRICT:-0}"   # 1 = предупреждения считать провалами

# --- цвета (отключаются при пайпе и при NO_COLOR) ----------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WRN=$'\033[33m'
  C_DIM=$'\033[2m'; C_B=$'\033[1m';   C_OFF=$'\033[0m'
else
  C_OK=""; C_BAD=""; C_WRN=""; C_DIM=""; C_B=""; C_OFF=""
fi

# --- служебное ---------------------------------------------------------------
describe() {
  ASSERT_SUITE="$1"
  printf '\n%s%s%s\n' "$C_B" "── $ASSERT_SUITE " "$C_OFF"
}

_ok() {
  ASSERT_PASS=$((ASSERT_PASS + 1))
  printf '  %sok%s    %s\n' "$C_OK" "$C_OFF" "$1"
}

_fail() {
  ASSERT_FAIL=$((ASSERT_FAIL + 1))
  printf '  %sFAIL%s  %s\n' "$C_BAD" "$C_OFF" "$1"
  if [ "$#" -gt 1 ] && [ -n "$2" ]; then
    printf '        %s%s%s\n' "$C_DIM" "$2" "$C_OFF"
  fi
  return 0
}

_skip() {
  ASSERT_SKIP=$((ASSERT_SKIP + 1))
  printf '  %sskip%s  %s\n' "$C_WRN" "$C_OFF" "$1"
}

# Мягкая проверка: пишет предупреждение, но не роняет прогон.
# В режиме ASSERT_STRICT=1 превращается в обычный провал.
_warn() {
  if [ "$ASSERT_STRICT" = "1" ]; then
    _fail "$1" "${2:-}"
  else
    printf '  %swarn%s  %s\n' "$C_WRN" "$C_OFF" "$1"
    if [ "$#" -gt 1 ] && [ -n "$2" ]; then
      printf '        %s%s%s\n' "$C_DIM" "$2" "$C_OFF"
    fi
  fi
  return 0
}

# require_cmd jq "нужен для проверки JSON"
# Если инструмента нет — тест не падает, а честно помечается skip.
require_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  _skip "нет инструмента '$1' — проверка пропущена (${2:-})"
  return 1
}

# --- ассерты по файловой системе ---------------------------------------------
assert_file_exists() {
  local p="$1" d="${2:-файл существует}"
  if [ -f "$p" ]; then _ok "$d: $p"; else _fail "$d: $p" "файла нет"; fi
}

assert_dir_exists() {
  local p="$1" d="${2:-каталог существует}"
  if [ -d "$p" ]; then _ok "$d: $p"; else _fail "$d: $p" "каталога нет"; fi
}

assert_file_absent() {
  local p="$1" d="${2:-файла быть не должно}"
  if [ ! -e "$p" ]; then _ok "$d: $p"; else _fail "$d: $p" "файл присутствует"; fi
}

assert_executable() {
  local p="$1" d="${2:-файл исполняемый}"
  if [ -x "$p" ]; then _ok "$d: $p"; else _fail "$d: $p" "нет бита +x: chmod +x $p"; fi
}

assert_not_empty() {
  local p="$1" d="${2:-файл не пустой}"
  if [ -s "$p" ]; then _ok "$d: $p"; else _fail "$d: $p" "0 байт"; fi
}

# --- ассерты по содержимому ---------------------------------------------------
assert_contains() {
  local p="$1" pat="$2" d="${3:-содержит '$2'}"
  if [ ! -f "$p" ]; then _fail "$d" "нет файла $p"; return 0; fi
  if grep -qE -- "$pat" "$p"; then _ok "$d ($p)"; else _fail "$d ($p)" "паттерн не найден: $pat"; fi
}

assert_not_contains() {
  local p="$1" pat="$2" d="${3:-не содержит '$2'}"
  if [ ! -f "$p" ]; then _fail "$d" "нет файла $p"; return 0; fi
  if grep -qE -- "$pat" "$p"; then
    _fail "$d ($p)" "найдено: $(grep -nE -m3 -- "$pat" "$p" | tr '\n' ' ')"
  else
    _ok "$d ($p)"
  fi
}

assert_matches() {
  local s="$1" pat="$2" d="${3:-строка совпадает с '$2'}"
  if printf '%s' "$s" | grep -qE -- "$pat"; then _ok "$d"; else _fail "$d" "получено: $s"; fi
}

assert_eq() {
  local exp="$1" got="$2" d="${3:-значения совпадают}"
  if [ "$exp" = "$got" ]; then _ok "$d"; else _fail "$d" "ожидалось '$exp', получено '$got'"; fi
}

# --- ассерты по размеру (бюджет контекста) ------------------------------------
assert_max_lines() {
  local p="$1" max="$2" d="${3:-не длиннее $2 строк}"
  if [ ! -f "$p" ]; then _fail "$d" "нет файла $p"; return 0; fi
  local n; n=$(wc -l < "$p" | tr -d ' ')
  if [ "$n" -le "$max" ]; then _ok "$d ($p = $n)"; else _fail "$d ($p)" "строк $n при лимите $max"; fi
}

assert_max_bytes() {
  local p="$1" max="$2" d="${3:-не тяжелее $2 байт}"
  if [ ! -f "$p" ]; then _fail "$d" "нет файла $p"; return 0; fi
  local n; n=$(wc -c < "$p" | tr -d ' ')
  if [ "$n" -le "$max" ]; then _ok "$d ($p = $n)"; else _fail "$d ($p)" "байт $n при лимите $max"; fi
}

# Грубая оценка токенов: ~4 байта на токен для латиницы, ~2 для кириллицы.
# Нужна не точность, а сигнал «контракт распух».
assert_max_tokens_approx() {
  local p="$1" max="$2" d="${3:-примерно не больше $2 токенов}"
  if [ ! -f "$p" ]; then _fail "$d" "нет файла $p"; return 0; fi
  local b; b=$(wc -c < "$p" | tr -d ' ')
  local t=$((b / 3))
  if [ "$t" -le "$max" ]; then _ok "$d ($p ≈ $t)"; else _warn "$d ($p)" "≈$t токенов при ориентире $max"; fi
}

# --- ассерты по командам ------------------------------------------------------
assert_cmd_succeeds() {
  local cmd="$1" d="${2:-команда завершается успешно}"
  local out; out=$(eval "$cmd" 2>&1); local rc=$?
  if [ "$rc" -eq 0 ]; then _ok "$d"; else _fail "$d" "rc=$rc :: $(printf '%s' "$out" | tail -n 3 | tr '\n' ' ')"; fi
}

assert_cmd_fails() {
  local cmd="$1" d="${2:-команда обязана падать}"
  local out; out=$(eval "$cmd" 2>&1); local rc=$?
  if [ "$rc" -ne 0 ]; then _ok "$d (rc=$rc)"; else _fail "$d" "команда неожиданно прошла — ворота не работают"; fi
}

# --- ассерты по форматам ------------------------------------------------------
assert_json_valid() {
  local p="$1" d="${2:-валидный JSON}"
  if [ ! -f "$p" ]; then _fail "$d" "нет файла $p"; return 0; fi
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$p" >/dev/null 2>&1; then _ok "$d ($p)"; else _fail "$d ($p)" "$(jq empty "$p" 2>&1 | head -n 1)"; fi
  elif command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$p" >/dev/null 2>&1; then
      _ok "$d ($p)"
    else
      _fail "$d ($p)" "$(python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$p" 2>&1 | tail -n 1)"
    fi
  else
    _skip "$d ($p): нет ни jq, ни python3"
  fi
}

assert_yaml_frontmatter() {
  local p="$1" d="${2:-есть YAML-фронтматтер}"
  if [ ! -f "$p" ]; then _fail "$d" "нет файла $p"; return 0; fi
  if [ "$(head -n 1 "$p")" = "---" ] && [ "$(sed -n '2,40p' "$p" | grep -c '^---$')" -ge 1 ]; then
    _ok "$d ($p)"
  else
    _fail "$d ($p)" "первая строка должна быть --- и блок должен закрываться"
  fi
}

# --- итог ---------------------------------------------------------------------
finish() {
  local total=$((ASSERT_PASS + ASSERT_FAIL))
  printf '\n  %sитого%s  прошло %s%d%s · упало %s%d%s · пропущено %d (всего проверок %d)\n' \
    "$C_B" "$C_OFF" "$C_OK" "$ASSERT_PASS" "$C_OFF" \
    "$C_BAD" "$ASSERT_FAIL" "$C_OFF" "$ASSERT_SKIP" "$total"
  if [ "$ASSERT_FAIL" -gt 0 ]; then
    printf '  %sсуита «%s» провалена%s\n\n' "$C_BAD" "$ASSERT_SUITE" "$C_OFF"
    exit 1
  fi
  printf '  %sсуита «%s» зелёная%s\n\n' "$C_OK" "$ASSERT_SUITE" "$C_OFF"
  exit 0
}

# Корень репозитория — чтобы тесты можно было запускать из любого каталога.
repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
  fi
}
