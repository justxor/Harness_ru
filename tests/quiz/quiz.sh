#!/usr/bin/env bash
# =============================================================================
#  tests/quiz/quiz.sh — самопроверка по курсу прямо в терминале
#  Курс: https://github.com/justxor/Harness_ru
#
#  Запуск:
#     bash tests/quiz/quiz.sh                 # 10 случайных вопросов
#     bash tests/quiz/quiz.sh -n 40           # все вопросы
#     bash tests/quiz/quiz.sh -t контекст     # только по теме
#     bash tests/quiz/quiz.sh --topics        # список тем
#     bash tests/quiz/quiz.sh --check         # проверить сам файл вопросов (для CI)
#
#  Ответ вводится цифрой. Пустой ввод — «не знаю», это честный ответ и он
#  считается ошибкой, но без штрафа за угадывание.
# =============================================================================

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="${QUIZ_DB:-$HERE/questions.tsv}"
N=10
TOPIC=""
MODE="quiz"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n) N="$2"; shift 2 ;;
    -t) TOPIC="$2"; shift 2 ;;
    --topics) MODE="topics"; shift ;;
    --check)  MODE="check";  shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,2\}//'; exit 0 ;;
    *) printf 'неизвестный аргумент: %s\n' "$1"; exit 2 ;;
  esac
done

if [ ! -f "$DB" ]; then
  printf 'нет файла вопросов: %s\n' "$DB"
  exit 1
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; O=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; D=""; O=""
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t quiz)"
trap 'rm -rf "$TMP"' EXIT

# --- режим: список тем -----------------------------------------------------------
if [ "$MODE" = "topics" ]; then
  printf '%sТемы и число вопросов%s\n' "$B" "$O"
  awk -F'\t' '!/^#/ && NF>=6 {c[$2]++} END{for(t in c) printf "  %-14s %d\n", t, c[t]}' "$DB" | sort
  exit 0
fi

# --- режим: проверка целостности файла вопросов ------------------------------------
# Данные для теста — тоже артефакт harness, и они тоже должны проверяться.
if [ "$MODE" = "check" ]; then
  problems=0
  while IFS=$'\t' read -r id topic q opts correct expl; do
    case "$id" in ''|'#'*) continue ;; esac
    n_opts=$(printf '%s' "$opts" | awk -F'|' '{print NF}')
    if [ -z "$topic" ] || [ -z "$q" ] || [ -z "$expl" ]; then
      printf '%s[%s]%s нет обязательного поля\n' "$R" "$id" "$O"; problems=$((problems+1))
    fi
    if [ "$n_opts" -ne 4 ]; then
      printf '%s[%s]%s вариантов %s, ожидалось 4\n' "$R" "$id" "$O" "$n_opts"; problems=$((problems+1))
    fi
    if ! printf '%s' "$correct" | grep -qE '^[1-4]$'; then
      printf '%s[%s]%s номер верного ответа «%s» вне диапазона 1..4\n' "$R" "$id" "$O" "$correct"; problems=$((problems+1))
    fi
    if [ "${#expl}" -lt 20 ]; then
      printf '%s[%s]%s разбор слишком короткий: ответ без объяснения ничему не учит\n' "$Y" "$id" "$O"
    fi
  done < "$DB"

  dup=$(awk -F'\t' '!/^#/ && NF>=6 {print $1}' "$DB" | sort | uniq -d)
  if [ -n "$dup" ]; then
    printf '%sдубли id:%s %s\n' "$R" "$O" "$(printf '%s' "$dup" | tr '\n' ' ')"
    problems=$((problems+1))
  fi

  # Антиметрика к «все ответы правильные»: если верный ответ почти всегда
  # под одним номером, тест проверяет память на позицию, а не понимание.
  skew=$(awk -F'\t' '!/^#/ && NF>=6 {c[$5]++; t++} END{m=0; for(k in c) if(c[k]>m) m=c[k]; printf "%d", m*100/t}' "$DB")
  if [ "$skew" -gt 60 ]; then
    printf '%sперекос:%s %s%% верных ответов под одним номером\n' "$R" "$O" "$skew"
    problems=$((problems+1))
  else
    printf 'распределение верных ответов: максимум %s%% на один номер — приемлемо\n' "$skew"
  fi

  total=$(awk -F'\t' '!/^#/ && NF>=6' "$DB" | wc -l | tr -d ' ')
  if [ "$problems" -eq 0 ]; then
    printf '%sфайл вопросов в порядке: %s вопросов%s\n' "$G" "$total" "$O"
    exit 0
  fi
  printf '%sпроблем в файле вопросов: %s%s\n' "$R" "$problems" "$O"
  exit 1
fi

# --- отбор и перемешивание ---------------------------------------------------------
awk -F'\t' -v topic="$TOPIC" '!/^#/ && NF>=6 && (topic=="" || $2==topic)' "$DB" > "$TMP/pool.tsv"

pool_size=$(wc -l < "$TMP/pool.tsv" | tr -d ' ')
if [ "$pool_size" -eq 0 ]; then
  printf 'нет вопросов по теме «%s». Список тем: bash %s --topics\n' "$TOPIC" "${BASH_SOURCE[0]}"
  exit 1
fi
[ "$N" -gt "$pool_size" ] && N="$pool_size"

# Портируемое перемешивание: shuf есть не везде.
awk 'BEGIN{srand()} {printf "%.9f\t%s\n", rand(), $0}' "$TMP/pool.tsv" \
  | sort -k1,1 | cut -f2- | head -n "$N" > "$TMP/ask.tsv"

# --- прогон --------------------------------------------------------------------------
printf '\n%s╔═══════════════════════════════════════════════════════╗%s\n' "$B" "$O"
printf '%s║  Самопроверка по курсу Harness · %-2s вопрос(ов)%s        ║%s\n' "$B" "$N" "" "$O"
printf '%s╚═══════════════════════════════════════════════════════╝%s\n' "$B" "$O"
printf '%sОтвет — цифра 1–4. Enter без цифры — «не знаю».%s\n' "$D" "$O"

right=0
i=0
: > "$TMP/wrong.txt"

while IFS=$'\t' read -r id topic q opts correct expl <&3; do
  i=$((i + 1))
  printf '\n%s%d/%d%s  %s[%s]%s  %s\n' "$B" "$i" "$N" "$O" "$D" "$topic" "$O" "$q"
  printf '%s' "$opts" | awk -F'|' '{for(k=1;k<=NF;k++) printf "    %d) %s\n", k, $k}'
  printf '  ваш ответ: '
  read -r ans

  if [ "$ans" = "$correct" ]; then
    right=$((right + 1))
    printf '  %s✓ верно%s\n' "$G" "$O"
  else
    good=$(printf '%s' "$opts" | awk -F'|' -v k="$correct" '{print $k}')
    if [ -z "$ans" ]; then
      printf '  %s— не знаю.%s Верно: %s\n' "$Y" "$O" "$good"
    else
      printf '  %s✗ неверно.%s Верно: %s\n' "$R" "$O" "$good"
    fi
    printf '%s\n' "$topic" >> "$TMP/wrong.txt"
  fi
  printf '  %s%s%s\n' "$D" "$expl" "$O"
done 3< "$TMP/ask.tsv"

# --- итог ------------------------------------------------------------------------------
pct=$(( right * 100 / N ))
printf '\n%s────────────────────────────────────────%s\n' "$B" "$O"
printf '  результат: %s%d из %d%s (%d%%)\n' "$B" "$right" "$N" "$O" "$pct"

if [ -s "$TMP/wrong.txt" ]; then
  printf '\n  %sслабые темы:%s\n' "$Y" "$O"
  sort "$TMP/wrong.txt" | uniq -c | sort -rn | head -n 5 \
    | awk '{printf "    %-14s ошибок: %s\n", $2, $1}'
fi

printf '\n'
if [ "$pct" -ge 85 ]; then
  printf '  %sМатериал усвоен.%s Проверьте себя на практике: задачник в README\n' "$G" "$O"
  printf '  и лабораторные работы дадут то, чего не даст ни один тест с вариантами.\n\n'
elif [ "$pct" -ge 60 ]; then
  printf '  %sОснова есть, дыры видны.%s Перечитайте разделы по слабым темам\n' "$Y" "$O"
  printf '  и прогоните тест ещё раз через день, а не сразу: повтор сразу\n'
  printf '  проверяет короткую память, а не понимание.\n\n'
else
  printf '  %sПока рано.%s Пройдите Часть 0 (теоретическая база) и диагностический\n' "$R" "$O"
  printf '  протокол, затем вернитесь. Тест с вариантами — самая мягкая проверка\n'
  printf '  из возможных; если она даётся тяжело, практика будет тяжелее.\n\n'
fi

exit 0
