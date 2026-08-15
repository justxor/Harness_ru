#!/usr/bin/env bash
# =============================================================================
#  самотест: тесты harness умеют падать
# =============================================================================
#  Главный вопрос к любому набору тестов: а он вообще что-нибудь ловит.
#  Ответ должен быть воспроизводимым, а не устным. Здесь он такой:
#
#    на fixtures/good-harness  наборы T01–T05 обязаны быть ЗЕЛЁНЫМИ;
#    на fixtures/bad-harness   наборы T01–T04 обязаны быть КРАСНЫМИ.
#
#  Это дешёвая версия мутационного тестирования: мутация уже подготовлена
#  и лежит в репозитории. Если сломанная обвязка проходит проверку —
#  красным становится этот файл, и чинить надо тесты, а не обвязку.
# =============================================================================

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/assert.sh"

GOOD="$HERE/fixtures/good-harness"
BAD="$HERE/fixtures/bad-harness"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t selftest)"
trap 'rm -rf "$TMP"' EXIT

describe "T06 Самотест: тесты обязаны падать на сломанном входе"

# --- 0. Фикстуры на месте --------------------------------------------------------
assert_dir_exists "$GOOD" "эталонная фикстура"
assert_dir_exists "$BAD"  "сломанная фикстура"
if [ ! -d "$GOOD" ] || [ ! -d "$BAD" ]; then finish; fi

SUITES="test_01_structure.sh test_02_context_budget.sh test_03_commands.sh test_04_gates_and_hooks.sh"

run_suite() {  # run_suite <файл> <корень>
  ( cd "$2" && HARNESS_ROOT="$2" ASSERT_STRICT=0 NO_COLOR=1 bash "$HERE/$1" ) >/dev/null 2>&1
  printf '%s' "$?"
}

# --- 1. На эталонной обвязке всё зелено -------------------------------------------
# Если здесь красно — тесты слишком строгие и будут раздражать людей,
# а раздражающие тесты отключают.
for s in $SUITES test_05_golden_tasks.sh; do
  [ -f "$HERE/$s" ] || { _skip "нет набора $s"; continue; }
  rc=$(run_suite "$s" "$GOOD")
  if [ "$rc" = "0" ]; then
    _ok "[good] $s — зелёный, как и должен"
  else
    _fail "[good] $s — красный (rc=$rc)" "ложное срабатывание: тест придирается к корректной обвязке"
  fi
done

# --- 2. На сломанной обвязке всё красное ---------------------------------------------
# Если здесь зелено — тест ничего не проверяет.
for s in $SUITES; do
  [ -f "$HERE/$s" ] || { _skip "нет набора $s"; continue; }
  rc=$(run_suite "$s" "$BAD")
  if [ "$rc" != "0" ]; then
    _ok "[bad] $s — упал, как и должен (rc=$rc)"
  else
    _fail "[bad] $s — прошёл на сломанной обвязке" "тест-украшение: удалите или почините"
  fi
done

# --- 3. Самопроверка библиотеки ассертов ------------------------------------------------
# Ассерт, который не умеет провалиться, опаснее отсутствующего: он создаёт
# ложное чувство покрытия.
mk() {  # mk <имя> <тело>
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'source "%s/lib/assert.sh"\n' "$HERE"
    printf 'describe "meta"\n'
    printf '%s\n' "$2"
    printf 'finish\n'
  } > "$TMP/$1"
}

printf 'a\nb\nc\nd\ne\n' > "$TMP/five.txt"
printf 'ok\n' > "$TMP/one.txt"

mk pass_lines.sh "assert_max_lines '$TMP/one.txt' 3 'короткий файл проходит'"
mk fail_lines.sh "assert_max_lines '$TMP/five.txt' 3 'длинный файл обязан упасть'"
mk pass_exists.sh "assert_file_exists '$TMP/one.txt'"
mk fail_exists.sh "assert_file_exists '$TMP/no-such-file'"
mk pass_contains.sh "assert_contains '$TMP/one.txt' '^ok$'"
mk fail_contains.sh "assert_contains '$TMP/one.txt' '^nope$'"
mk fail_cmdfails.sh "assert_cmd_fails 'true' 'true не падает — ассерт обязан это заметить'"
mk pass_cmdfails.sh "assert_cmd_fails 'false'"

assert_cmd_succeeds "bash '$TMP/pass_lines.sh'"    "assert_max_lines пропускает короткий файл"
assert_cmd_fails    "bash '$TMP/fail_lines.sh'"    "assert_max_lines ловит длинный файл"
assert_cmd_succeeds "bash '$TMP/pass_exists.sh'"   "assert_file_exists видит файл"
assert_cmd_fails    "bash '$TMP/fail_exists.sh'"   "assert_file_exists ловит отсутствие файла"
assert_cmd_succeeds "bash '$TMP/pass_contains.sh'" "assert_contains находит паттерн"
assert_cmd_fails    "bash '$TMP/fail_contains.sh'" "assert_contains ловит отсутствие паттерна"
assert_cmd_succeeds "bash '$TMP/pass_cmdfails.sh'" "assert_cmd_fails доволен падающей командой"
assert_cmd_fails    "bash '$TMP/fail_cmdfails.sh'" "assert_cmd_fails ловит неожиданно успешную команду"

# --- 4. Раннер уважает код возврата -------------------------------------------------------
# Раннер, который всегда возвращает 0, обесценивает весь каталог.
if [ -f "$HERE/run_all.sh" ]; then
  assert_contains "$HERE/run_all.sh" 'exit 1' "раннер умеет вернуть ненулевой код"
fi

# --- 5. Каждый набор хотя бы один раз может провалиться -----------------------------------
# Формальный, но полезный признак: в файле есть вызов _fail или assert_*.
for f in "$HERE"/test_*.sh; do
  [ -e "$f" ] || continue
  n="$(basename "$f")"
  [ "$n" = "test_06_selftest.sh" ] && continue
  if grep -qE '(_fail |assert_)' "$f"; then
    _ok "[$n] содержит проверки, способные провалиться"
  else
    _fail "[$n] нет ни одной проверки" "файл называется тестом, но ничего не утверждает"
  fi
done

finish
