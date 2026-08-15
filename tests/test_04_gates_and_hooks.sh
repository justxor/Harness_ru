#!/usr/bin/env bash
# =============================================================================
#  ворота и хуки: проверки реально закрываются, а не украшают репозиторий
# =============================================================================
#  Ворота, которые никогда не падали, — не ворота, а декорация. Поэтому здесь
#  мало «есть ли файл» и много «а упадёт ли оно на заведомо плохом входе».
#  Это дешёвый аналог мутационного тестирования, применённый к harness.
#
#  Все мутации выполняются во временном каталоге. Проверяемый проект
#  не изменяется ни на байт.
# =============================================================================

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/assert.sh"

ROOT="${HARNESS_ROOT:-$(repo_root)}"
cd "$ROOT" || exit 1

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

describe "T04 Ворота и хуки ($ROOT)"

# --- 1. Ворота вообще описаны ---------------------------------------------------
gates_file=""
for f in Makefile justfile Taskfile.yml package.json; do [ -f "$f" ] && gates_file="$f" && break; done

if [ -n "$gates_file" ]; then
  _ok "точка входа для ворот: $gates_file"
  assert_contains "$gates_file" '(test|check)' "$gates_file умеет запускать проверки"
else
  _fail "нет точки входа для ворот" "агенту нечего вызвать перед коммитом"
fi

# --- 2. CI существует и запускает то же самое -----------------------------------
ci=""
for f in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml; do
  [ -e "$f" ] && ci="$f" && break
done

if [ -n "$ci" ]; then
  _ok "CI найден: $ci"
  # Паритет: то, что гоняется локально, должно гоняться и в CI. Расхождение —
  # источник «у меня всё зелёное, а в CI красное» и наоборот.
  if grep -qE '(make |npm run |pnpm |yarn |pytest|go test|cargo test|bash tests/)' "$ci"; then
    _ok "CI вызывает те же команды, что и локальная точка входа"
  else
    _warn "CI не вызывает знакомых команд" "проверьте паритет локальных и удалённых ворот"
  fi
  assert_not_contains "$ci" '(continue-on-error:\s*true|\|\| true)' \
    "в CI нет проверок, которым разрешено падать молча"
else
  _fail "нет конфигурации CI" "ворота, которые работают только на вашей машине, не ворота"
fi

# --- 3. Хуки: конфигурация валидна ----------------------------------------------
for j in .claude/settings.json .claude/settings.local.json .agent/settings.json; do
  [ -f "$j" ] || continue
  assert_json_valid "$j" "конфигурация хуков — валидный JSON"
  if grep -q '"hooks"' "$j"; then
    _ok "$j описывает хуки"
  else
    _warn "$j без секции hooks" "автоматических проверок после правок агента нет"
  fi
done

if [ -d ".git/hooks" ]; then
  active=$(find .git/hooks -type f ! -name '*.sample' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$active" -gt 0 ]; then
    _ok "локальных git-хуков активно: $active"
  else
    _warn "нет активных git-хуков" "не критично, если ворота держит CI"
  fi
fi

# --- 4. Обход ворот не должен быть привычкой -------------------------------------
bypass=$(grep -rslE 'git (commit|push)[^\n]*--no-verify' \
         --include='*.sh' --include='*.md' --include='Makefile' --include='*.yml' . 2>/dev/null | head -n 3)
if [ -z "$bypass" ]; then
  _ok "нигде не зашит обход хуков (--no-verify)"
else
  _fail "обход хуков зашит в процедуры" "$(printf '%s' "$bypass" | tr '\n' ' ')"
fi

# --- 5. Мутация: линтер обязан падать на сломанном файле -------------------------
# Смысл: доказать, что проверка отличает хорошее от плохого.
if command -v python3 >/dev/null 2>&1 && command -v ruff >/dev/null 2>&1; then
  printf 'def f(:\n  pass\n' > "$TMP/broken.py"
  assert_cmd_fails "ruff check '$TMP/broken.py'" "ruff падает на синтаксически битом файле"
else
  _skip "мутация линтера Python (нет ruff/python3)"
fi

if command -v node >/dev/null 2>&1; then
  printf 'const a = ;\n' > "$TMP/broken.js"
  assert_cmd_fails "node --check '$TMP/broken.js'" "node --check падает на битом JS"
else
  _skip "мутация линтера JS (нет node)"
fi

# --- 6. Мутация: shell-скрипты harness синтаксически валидны ----------------------
bad_sh=0
while IFS= read -r s; do
  bash -n "$s" 2>/dev/null || { bad_sh=$((bad_sh + 1)); _fail "синтаксис shell" "$s"; }
done < <(find . -name '*.sh' -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null | head -n 200)
[ "$bad_sh" -eq 0 ] && _ok "все .sh проходят bash -n"

# --- 7. Мутация: YAML в CI разбирается -------------------------------------------
if [ -n "$ci" ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    assert_cmd_succeeds "python3 -c \"import yaml,sys; yaml.safe_load(open('$ci'))\"" "CI-конфигурация разбирается как YAML"
  else
    _skip "разбор YAML (нет python3+pyyaml)"
  fi
fi

# --- 8. Ворота должны быть быстрыми ----------------------------------------------
# Медленные ворота отключают. Не потому что люди плохие, а потому что
# двадцатиминутный цикл обратной связи несовместим с работой.
if [ -f "Makefile" ] && grep -qE '^(test|check):' Makefile; then
  _ok "в Makefile есть цель test/check"
  if grep -qE '^(quick|fast|smoke):' Makefile; then
    _ok "есть быстрый профиль проверок (quick/fast/smoke)"
  else
    _warn "нет быстрого профиля проверок" "агенту нужен цикл в секунды, а не в минуты"
  fi
fi

# --- 9. Секреты не утекают через конфигурацию ------------------------------------
leak=$(grep -rlE '(sk-[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16})' \
       --include='*.json' --include='*.yml' --include='*.yaml' --include='*.md' . 2>/dev/null | head -n 3)
if [ -z "$leak" ]; then
  _ok "в конфигурациях нет похожего на секреты"
else
  _fail "возможная утечка секретов" "$(printf '%s' "$leak" | tr '\n' ' ')"
fi

# --- 10. Антиметрика --------------------------------------------------------------
# «Все проверки зелёные» ничего не стоит, если проверок две и обе тривиальны.
gates_count=0
[ -n "$gates_file" ] && gates_count=$((gates_count + 1))
[ -n "$ci" ] && gates_count=$((gates_count + 1))
[ -f ".claude/settings.json" ] && gates_count=$((gates_count + 1))
[ -f ".pre-commit-config.yaml" ] && gates_count=$((gates_count + 1))
if [ "$gates_count" -ge 2 ]; then
  _ok "уровней ворот: $gates_count — отказ одного не открывает дорогу всему"
else
  _fail "уровней ворот: $gates_count" "единственная проверка = единственная точка отказа"
fi

finish
