#!/usr/bin/env bash
# =============================================================================
#  слэш-команды: воспроизводимые процедуры, а не заметки на салфетке
# =============================================================================
#  Команда агента — это функция. У функции есть имя, вход, выход и контракт.
#  Если у процедуры нет критерия приёмки, то «сделано» определяет настроение,
#  а не проверка. Этот набор превращает каталог команд в проверяемый API.
# =============================================================================

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/assert.sh"

ROOT="${HARNESS_ROOT:-$(repo_root)}"
cd "$ROOT" || exit 1

CMD_DIRS="${HARNESS_CMD_DIRS:-.claude/commands .agent/commands .github/prompts}"
MAX_CMD_LINES="${MAX_CMD_LINES:-120}"

describe "T03 Слэш-команды ($ROOT)"

dir=""
for d in $CMD_DIRS; do [ -d "$d" ] && dir="$d" && break; done

if [ -z "$dir" ]; then
  _warn "нет каталога команд" "ожидался один из: $CMD_DIRS — пропускаю проверки"
  finish
fi

mapfile -t cmds < <(find "$dir" -type f -name '*.md' | sort)

if [ "${#cmds[@]}" -eq 0 ]; then
  _fail "каталог команд пуст" "$dir не содержит ни одного .md"
  finish
fi

_ok "найдено команд: ${#cmds[@]} в $dir"

# --- пообъектные проверки ------------------------------------------------------
for f in "${cmds[@]}"; do
  name="$(basename "$f" .md)"

  # 1. Имя. Пробелы, кириллица и CamelCase в имени команды ломают вызов.
  if printf '%s' "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    _ok "[$name] имя в kebab-case"
  else
    _fail "[$name] имя команды" "используйте только a-z, 0-9 и дефис"
  fi

  # 2. Фронтматтер с описанием — то, что агент видит в списке команд.
  assert_yaml_frontmatter "$f" "[$name] есть фронтматтер"
  assert_contains "$f" '^description:' "[$name] у команды есть description"

  # 3. Критерий приёмки. Без него команда не завершаема.
  if grep -qiE '(критерий приёмк|критерий приемк|acceptance|готово, когда|definition of done|проверк[аи] результата)' "$f"; then
    _ok "[$name] есть критерий приёмки"
  else
    _fail "[$name] нет критерия приёмки" "добавьте раздел «Готово, когда:» с проверяемым условием"
  fi

  # 4. Проверяемость: команда должна называть конкретную проверку.
  if grep -qE '(make |npm |pnpm |yarn |pytest|go test|cargo |ruff|eslint|mypy|tsc|bash )' "$f"; then
    _ok "[$name] содержит исполняемую проверку"
  else
    _warn "[$name] нет исполняемой проверки" "агент не сможет доказать, что закончил"
  fi

  # 5. Размер. Процедура на 300 строк — это уже документ, а не команда.
  assert_max_lines "$f" "$MAX_CMD_LINES" "[$name] короче $MAX_CMD_LINES строк"

  # 6. Локальные абсолютные пути — команда не переносится на чужую машину.
  assert_not_contains "$f" '(/Users/[a-zA-Z]|/home/[a-zA-Z]|C:\\Users)' \
    "[$name] нет абсолютных путей с чужой машины"

  # 7. Секреты.
  assert_not_contains "$f" '(sk-[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16})' \
    "[$name] нет похожего на секрет"

  # 8. Разрушительные операции без явного подтверждения.
  if grep -qE '(rm -rf /( |$)|git push --force( |$)|git push -f |DROP DATABASE|--no-verify)' "$f"; then
    _fail "[$name] опасная операция без ограды" "$(grep -nE '(rm -rf /( |$)|git push --force|git push -f |DROP DATABASE|--no-verify)' "$f" | head -n 1)"
  else
    _ok "[$name] нет разрушительных операций без ограды"
  fi

  # 9. Если используется аргумент — он должен быть описан.
  if grep -qE '(\${ARGUMENTS}|\${1}|\${2})' "$f"; then
    if grep -qiE '(аргумент|argument|принимает|usage|использование)' "$f"; then
      _ok "[$name] аргументы описаны"
    else
      _fail "[$name] аргументы не описаны" "команда читает аргумент, но нигде не сказано какой"
    fi
  fi

  # 10. Ссылки на скрипты и файлы должны существовать.
  miss=""
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    case "$ref" in http*|*'*'*) continue ;; esac
    [ -e "$ref" ] || miss="$miss $ref"
  done < <(grep -oE '(scripts|bin|tools)/[A-Za-z0-9_./-]+' "$f" | sort -u)
  if [ -z "$miss" ]; then
    _ok "[$name] все упомянутые скрипты существуют"
  else
    _fail "[$name] битые ссылки на скрипты" "$miss"
  fi
done

# --- проверки по набору в целом -------------------------------------------------

# 11. Дубли имён между каталогами — источник «работает по-разному у разных людей».
alln=$(for d in $CMD_DIRS; do [ -d "$d" ] && find "$d" -name '*.md' -exec basename {} .md \; ; done | sort)
dup=$(printf '%s\n' "$alln" | uniq -d)
if [ -z "$dup" ]; then
  _ok "нет команд с одинаковыми именами"
else
  _fail "дубли имён команд" "$(printf '%s' "$dup" | tr '\n' ' ')"
fi

# 12. Покрытие базовых процедур. Это не догма, но отсутствие всех четырёх
#     обычно означает, что командами просто не пользуются.
have=0
for want in 'fix|bug|debug' 'review|check' 'test|cover' 'ship|release|pr'; do
  if printf '%s\n' "$alln" | grep -qE "$want"; then have=$((have + 1)); fi
done
if [ "$have" -ge 2 ]; then
  _ok "покрыты базовые сценарии ($have из 4 групп)"
else
  _warn "покрыто только $have из 4 базовых групп" "починка, ревью, тесты, выкатка"
fi

# 13. Антиметрика: команд может быть много и все — мусорные.
#     Требуем, чтобы у большинства был критерий приёмки.
withac=0
for f in "${cmds[@]}"; do
  grep -qiE '(критерий приёмк|критерий приемк|acceptance|готово, когда|definition of done)' "$f" && withac=$((withac + 1))
done
pct=$(( withac * 100 / ${#cmds[@]} ))
if [ "$pct" -ge 80 ]; then
  _ok "критерий приёмки есть у $pct % команд"
else
  _fail "критерий приёмки есть только у $pct % команд" "количество команд без качества — метрика ради метрики"
fi

finish
