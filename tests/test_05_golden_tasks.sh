#!/usr/bin/env bash
# =============================================================================
#  золотой набор: задачи описаны, проверяемы и не протухли
# =============================================================================
#  Этот набор НЕ запускает модель. Он проверяет, что контракт уровня L2
#  вообще пригоден к использованию: у задач есть критерии, есть запреты,
#  есть базовая линия, набор не состоит из одних лёгких задач и его
#  пересматривали в этом полугодии.
#
#  Дорогой прогон на живой модели — отдельный ночной пайплайн.
#  Смысл разделения: дешёвая проверка должна ловить дешёвые ошибки.
# =============================================================================

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/assert.sh"

ROOT="${HARNESS_ROOT:-$(repo_root)}"
GOLDEN="${GOLDEN_FILE:-}"
if [ -z "$GOLDEN" ]; then
  if [ -f "$ROOT/tests/golden/cases.yaml" ]; then GOLDEN="$ROOT/tests/golden/cases.yaml"
  else GOLDEN="$HERE/golden/cases.yaml"; fi
fi

MIN_CASES="${MIN_GOLDEN_CASES:-8}"
MAX_AGE_DAYS="${MAX_GOLDEN_AGE_DAYS:-180}"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t golden)"
trap 'rm -rf "$TMP"' EXIT

describe "T05 Золотой набор ($GOLDEN)"

assert_file_exists "$GOLDEN" "файл золотого набора"
[ -f "$GOLDEN" ] || finish

# --- 1. Синтаксис ---------------------------------------------------------------
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  assert_cmd_succeeds "python3 -c \"import yaml;yaml.safe_load(open('$GOLDEN'))\"" "YAML разбирается"
else
  _skip "разбор YAML (нет python3 + pyyaml) — проверяю грепом"
fi

# --- 2. Шапка -------------------------------------------------------------------
assert_contains "$GOLDEN" '^version:'        "указана версия схемы"
assert_contains "$GOLDEN" '^updated:'        "указана дата пересмотра"
assert_contains "$GOLDEN" '^runs_per_case:'  "указано число прогонов на задачу"

runs=$(grep -E '^runs_per_case:' "$GOLDEN" | head -n1 | tr -dc '0-9')
runs="${runs:-0}"
if [ "$runs" -ge 3 ]; then
  _ok "прогонов на задачу: $runs — доля измерима"
else
  _fail "прогонов на задачу: $runs" "по одному прогону нельзя судить о стохастическом процессе"
fi

# --- 3. Свежесть ------------------------------------------------------------------
upd=$(grep -E '^updated:' "$GOLDEN" | head -n1 | awk '{print $2}')
if printf '%s' "$upd" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  if u=$(date -d "$upd" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$upd" +%s 2>/dev/null); then
    days=$(( ( $(date +%s) - u ) / 86400 ))
    if [ "$days" -le "$MAX_AGE_DAYS" ]; then
      _ok "набор пересматривали $days дн. назад"
    else
      _warn "набор не пересматривали $days дн." "золотые задачи стареют быстрее документации"
    fi
  else
    _skip "не удалось разобрать дату $upd"
  fi
else
  _fail "поле updated" "ожидался формат YYYY-MM-DD, получено '$upd'"
fi

# --- 4. Разбор задач ---------------------------------------------------------------
awk -v out="$TMP" '/^  - id:/{n++} n>0{print >> (out "/case_" n ".yaml")}' "$GOLDEN"
count=$(find "$TMP" -name 'case_*.yaml' | wc -l | tr -d ' ')

if [ "$count" -ge "$MIN_CASES" ]; then
  _ok "задач в наборе: $count (минимум $MIN_CASES)"
else
  _fail "задач в наборе: $count" "меньше $MIN_CASES — набор ничего не различает"
fi

# --- 5. Уникальность идентификаторов -------------------------------------------------
ids=$(grep -E '^  - id:' "$GOLDEN" | awk '{print $3}')
dupids=$(printf '%s\n' "$ids" | sort | uniq -d)
if [ -z "$dupids" ]; then
  _ok "идентификаторы задач уникальны"
else
  _fail "дубли id" "$(printf '%s' "$dupids" | tr '\n' ' ')"
fi

# --- 6. Обязательные поля у каждой задачи ---------------------------------------------
bad=0
for f in "$TMP"/case_*.yaml; do
  [ -e "$f" ] || continue
  id=$(grep -m1 -E '^  - id:' "$f" | awk '{print $3}')
  for field in title category difficulty prompt accept reject baseline; do
    if ! grep -qE "^    $field:" "$f"; then
      _fail "[$id] нет поля '$field'" "задача без $field непроверяема"
      bad=$((bad + 1))
    fi
  done
  # accept должен содержать хотя бы одно машинно-проверяемое условие
  if ! grep -qE '(cmd:|expect_exit:|artifact_exists:|artifact_contains:|changed_files_within:|agent_refuses:|_added: true|_unchanged: true|_reported:|agent_asks_clarifying_question:|agent_challenges_premise:|root_cause_identified_outside:|clarifying_question_mentions:|proposes_alternative:|diff_max_lines:|changed_files_outside:)' "$f"; then
    _fail "[$id] accept без проверяемых условий" "критерий, который проверяет человек глазами, не критерий"
    bad=$((bad + 1))
  fi
  # reject не должен быть пустым
  rn=$(awk '/^    reject:/{f=1;next} /^    [a-z_]+:/{f=0} f&&/^      - /{c++} END{print c+0}' "$f")
  if [ "$rn" -lt 1 ]; then
    _fail "[$id] пустой reject" "без запретов агент оптимизирует проверку, а не задачу"
    bad=$((bad + 1))
  fi
done
[ "$bad" -eq 0 ] && _ok "все задачи содержат обязательные поля и непустой reject"

# --- 7. Разнообразие ------------------------------------------------------------------
cats=$(grep -E '^    category:' "$GOLDEN" | awk '{print $2}' | sort -u | wc -l | tr -d ' ')
if [ "$cats" -ge 3 ]; then
  _ok "категорий в наборе: $cats"
else
  _fail "категорий в наборе: $cats" "набор из одних багфиксов измеряет одну способность"
fi

if grep -qE '^    category: safety' "$GOLDEN"; then
  _ok "есть задачи на отказ от опасного действия"
else
  _fail "нет задач категории safety" "способность агента сказать «нет» тоже надо измерять"
fi

hard=$(grep -cE '^    difficulty: 3' "$GOLDEN" || true)
if [ "$hard" -ge 2 ]; then
  _ok "сложных задач: $hard"
else
  _warn "сложных задач: $hard" "набор из лёгких задач всегда зелёный и потому бесполезен"
fi

# --- 8. Антиметрика: набор не должен быть проходимым на 100 % ---------------------------
easy=$(grep -E '^      pass_rate:' "$GOLDEN" | awk '{print $2}' | awk '$1 >= 0.95' | wc -l | tr -d ' ')
if [ "$count" -gt 0 ] && [ "$easy" -lt "$count" ]; then
  _ok "не все задачи проходятся почти всегда ($easy из $count)"
else
  _fail "весь набор проходится почти всегда" "он больше не различает хороший harness и плохой — обновите задачи"
fi

# --- 9. Промпт должен быть дословным, а не пересказом -----------------------------------
short=$(awk '/^    prompt: \|/{f=1;n=0;next} f&&/^      /{n++} f&&!/^      /{if(n<1)c++;f=0} END{print c+0}' "$GOLDEN")
if [ "${short:-0}" -eq 0 ]; then
  _ok "у всех задач промпт непустой"
else
  _fail "пустых промптов: $short" "агент получит пустоту, прогон ничего не измерит"
fi

finish
