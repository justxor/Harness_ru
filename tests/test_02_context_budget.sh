#!/usr/bin/env bash
# =============================================================================
#  бюджет контекста: контракты не распухли и не противоречат себе
# =============================================================================
#  Контекст — это канал с шумом и конечной пропускной способностью. Каждая
#  строка, которая грузится всегда, отбирает место у строк, которые нужны
#  именно сейчас. Этот набор ловит самую частую деградацию harness: контракт
#  растёт линейно, полезность — нет.
#
#  Переменные:
#     MAX_CONTRACT_LINES (200)  максимум строк в корневом контракте
#     MAX_CONTRACT_BYTES (24000)
#     MAX_ALWAYS_TOKENS  (6000) ориентир по «всегда загруженному» контексту
# =============================================================================

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/assert.sh"

ROOT="${HARNESS_ROOT:-$(repo_root)}"
cd "$ROOT" || exit 1

MAX_CONTRACT_LINES="${MAX_CONTRACT_LINES:-200}"
MAX_CONTRACT_BYTES="${MAX_CONTRACT_BYTES:-24000}"
MAX_ALWAYS_TOKENS="${MAX_ALWAYS_TOKENS:-6000}"
CONTRACTS="${HARNESS_CONTRACTS:-CLAUDE.md AGENTS.md GEMINI.md .cursorrules .github/copilot-instructions.md}"

describe "T02 Бюджет контекста ($ROOT)"

contract=""
for f in $CONTRACTS; do [ -f "$f" ] && contract="$f" && break; done

if [ -z "$contract" ]; then
  _fail "нет корневого контракта" "сначала закройте T01"
  finish
fi

# --- 1. Размер --------------------------------------------------------------
assert_max_lines        "$contract" "$MAX_CONTRACT_LINES" "контракт короче $MAX_CONTRACT_LINES строк"
assert_max_bytes        "$contract" "$MAX_CONTRACT_BYTES" "контракт легче $MAX_CONTRACT_BYTES байт"
assert_max_tokens_approx "$contract" "$MAX_ALWAYS_TOKENS" "контракт укладывается в бюджет постоянного контекста"

# --- 2. Структура: без заголовков документ нечитаем и для человека, и для модели
h=$(grep -cE '^#{1,3} ' "$contract" || true)
if [ "$h" -ge 3 ]; then
  _ok "в контракте $h заголовков — есть навигация"
else
  _fail "в контракте $h заголовков" "плоская простыня хуже извлекается и хуже правится"
fi

# --- 3. Дубли: одна и та же мысль, сказанная трижды, не становится втрое важнее
dups=$(grep -vE '^\s*$' "$contract" | grep -vE '^\s*[-*#>|]' | sort | uniq -d | head -n 5)
if [ -z "$dups" ]; then
  _ok "нет дословных дублей строк"
else
  _warn "есть дословные дубли строк" "$(printf '%s' "$dups" | head -n 3 | tr '\n' ' | ')"
fi

# --- 4. Инфляция капса: когда «ВАЖНО» стоит везде, оно не значит ничего --------
imp=$(grep -coE '(ВАЖНО|КРИТИЧНО|ОБЯЗАТЕЛЬНО|IMPORTANT|CRITICAL|MUST|NEVER|ALWAYS)' "$contract" || true)
if [ "$imp" -le 8 ]; then
  _ok "маркеров важности $imp — умеренно"
else
  _warn "маркеров важности $imp" "инфляция акцентов: выделено всё — значит, ничего"
fi

# --- 5. Правило первых экранов -------------------------------------------------
# Середина длинного контекста используется хуже краёв (Liu et al., 2023).
# Значит, жёсткие запреты обязаны стоять в начале или в конце, а не в середине.
lines=$(wc -l < "$contract" | tr -d ' ')
if [ "$lines" -gt 120 ]; then
  head_hit=$(head -n 40 "$contract" | grep -cE '(запрещ|нельзя|не трогай|NEVER|DO NOT)' || true)
  tail_hit=$(tail -n 40 "$contract" | grep -cE '(запрещ|нельзя|не трогай|NEVER|DO NOT)' || true)
  if [ "$((head_hit + tail_hit))" -gt 0 ]; then
    _ok "жёсткие правила стоят у краёв документа"
  else
    _warn "жёсткие правила спрятаны в середине" "перенесите запреты в начало или в конец"
  fi
fi

# --- 6. Ссылки-импорты ведут в существующие файлы ------------------------------
missing=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  [ -e "$ref" ] || { missing=$((missing + 1)); [ "$missing" -le 3 ] && _fail "битая ссылка в контракте" "$ref"; }
done < <(grep -oE '@[A-Za-z0-9_./-]+\.(md|json|ya?ml|sh|py|ts)' "$contract" 2>/dev/null | sed 's/^@//' | sort -u)
[ "$missing" -eq 0 ] && _ok "все @-импорты контракта существуют"

# --- 7. Незакрытые хвосты ------------------------------------------------------
assert_not_contains "$contract" '(TODO|FIXME|XXX|TBD|<заполнить>|lorem ipsum)' \
  "в контракте нет незакрытых заглушек"

# --- 8. Совокупный «всегда загруженный» вес ------------------------------------
# Считаем всё, что попадает в контекст на старте сессии.
always_bytes=$(wc -c < "$contract" | tr -d ' ')
for extra in AGENTS.md .cursorrules .claude/settings.json; do
  [ -f "$extra" ] && [ "$extra" != "$contract" ] && always_bytes=$((always_bytes + $(wc -c < "$extra" | tr -d ' ')))
done
always_tokens=$((always_bytes / 3))
if [ "$always_tokens" -le "$MAX_ALWAYS_TOKENS" ]; then
  _ok "стартовый контекст ≈$always_tokens токенов (лимит $MAX_ALWAYS_TOKENS)"
else
  _warn "стартовый контекст ≈$always_tokens токенов" "выносите редко нужное в docs/ и подгружайте по требованию"
fi

# --- 9. Процедуры не должны быть мини-книгами ----------------------------------
for d in .claude/commands .agent/commands .github/prompts; do
  [ -d "$d" ] || continue
  big=$(find "$d" -type f -size +8k 2>/dev/null | head -n 3)
  if [ -z "$big" ]; then
    _ok "процедуры в $d компактные (< 8 КБ)"
  else
    _warn "тяжёлые процедуры в $d" "$(printf '%s' "$big" | tr '\n' ' ')"
  fi
done

# --- 10. Антиметрика ------------------------------------------------------------
# Короткий контракт — не самоцель. Если он короткий и при этом ничего не
# запрещает, мы просто выкинули пользу и порадовались цифре.
rules=$(grep -cE '^\s*[-*] ' "$contract" || true)
if [ "$rules" -ge 5 ]; then
  _ok "контракт содержит $rules конкретных пунктов — экономия не за счёт смысла"
else
  _fail "в контракте всего $rules пунктов" "антиметрика сработала: файл короткий, но пустой"
fi

finish
