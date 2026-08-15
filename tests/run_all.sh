#!/usr/bin/env bash
# =============================================================================
#  tests/run_all.sh — раннер всех наборов тестов harness
#  Курс: https://github.com/justxor/Harness_ru
#
#  Запуск:
#     bash tests/run_all.sh                 # все наборы
#     bash tests/run_all.sh 02              # только test_02_*
#     bash tests/run_all.sh --list          # показать список наборов
#     HARNESS_ROOT=~/proj bash tests/run_all.sh
#     ASSERT_STRICT=1 bash tests/run_all.sh # предупреждения = провалы
#
#  Код возврата: 0 — всё зелено, 1 — есть провалившиеся наборы.
#  Скрипт ничего не пишет в проверяемый проект и не ходит в сеть.
# =============================================================================

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$HERE/.." && pwd)}"
export ASSERT_STRICT="${ASSERT_STRICT:-0}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; O=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; D=""; O=""
fi

FILTER="${1:-}"

# --- собираем наборы ----------------------------------------------------------
suites=()
for f in "$HERE"/test_*.sh; do
  [ -e "$f" ] || continue
  case "$f" in *run_all.sh) continue ;; esac
  if [ -n "$FILTER" ] && [ "$FILTER" != "--list" ]; then
    case "$(basename "$f")" in *"$FILTER"*) ;; *) continue ;; esac
  fi
  suites+=("$f")
done

if [ "$FILTER" = "--list" ]; then
  printf '%sНаборы тестов harness%s\n' "$B" "$O"
  for f in "$HERE"/test_*.sh; do
    [ -e "$f" ] || continue
    printf '  %-32s %s\n' "$(basename "$f")" "$(sed -n '3s/^#  *//p' "$f")"
  done
  exit 0
fi

if [ "${#suites[@]}" -eq 0 ]; then
  printf '%sНе найдено ни одного набора (фильтр: %s)%s\n' "$R" "$FILTER" "$O"
  exit 1
fi

# --- шапка --------------------------------------------------------------------
printf '\n%s╔══════════════════════════════════════════════════════════════╗%s\n' "$B" "$O"
printf '%s║  Тесты harness · %-43s ║%s\n' "$B" "$(date +%Y-%m-%d\ %H:%M)" "$O"
printf '%s╚══════════════════════════════════════════════════════════════╝%s\n' "$B" "$O"
printf '  %sкорень:%s %s\n' "$D" "$O" "$HARNESS_ROOT"
printf '  %sрежим:%s  %s\n' "$D" "$O" "$( [ "$ASSERT_STRICT" = "1" ] && echo "строгий (warn = fail)" || echo "обычный" )"
printf '  %sнаборов:%s %d\n' "$D" "$O" "${#suites[@]}"

# --- прогон -------------------------------------------------------------------
failed=()
passed=()
started=$(date +%s)

for f in "${suites[@]}"; do
  name="$(basename "$f")"
  t0=$(date +%s)
  bash "$f"
  rc=$?
  t1=$(date +%s)
  dt=$((t1 - t0))
  if [ "$rc" -eq 0 ]; then
    passed+=("$name")
    printf '  %s▸ %s — ok за %dс%s\n' "$D" "$name" "$dt" "$O"
  else
    failed+=("$name")
    printf '  %s▸ %s — ПРОВАЛ (rc=%d) за %dс%s\n' "$R" "$name" "$rc" "$dt" "$O"
  fi
done

ended=$(date +%s)
total=$((ended - started))

# --- сводка -------------------------------------------------------------------
printf '\n%s──────────────────── сводка ────────────────────%s\n' "$B" "$O"
for n in "${passed[@]:-}"; do [ -n "$n" ] && printf '  %s✓%s %s\n' "$G" "$O" "$n"; done
for n in "${failed[@]:-}"; do [ -n "$n" ] && printf '  %s✗%s %s\n' "$R" "$O" "$n"; done

printf '\n  наборов: %d · зелёных: %s%d%s · красных: %s%d%s · время: %dс\n\n' \
  "${#suites[@]}" "$G" "${#passed[@]}" "$O" "$R" "${#failed[@]}" "$O" "$total"

if [ "${#failed[@]}" -gt 0 ]; then
  printf '  %sHarness не готов к работе.%s Чините сверху вниз: структура → бюджет →\n' "$R" "$O"
  printf '  команды → ворота → золотые задачи. Первый красный набор обычно объясняет\n'
  printf '  все остальные.\n\n'
  exit 1
fi

printf '  %sHarness зелёный.%s Не забудьте про L2: ночной прогон золотых задач\n' "$G" "$O"
printf '  (tests/golden/cases.yaml) — статика не заменяет проверку на живой модели.\n\n'
exit 0
