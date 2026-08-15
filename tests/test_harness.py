"""Тесты harness на pytest — версия для тех, у кого нет bash.

Курс: https://github.com/justxor/Harness_ru

Запуск:
    pytest tests/test_harness.py -v
    HARNESS_ROOT=~/work/my-project pytest tests/test_harness.py -v
    pytest tests/test_harness.py -m "not slow" -q

Логика та же, что в bash-наборах T01–T06, но выражена декларативно:
параметризованные проверки вместо простыни if-ов. Полезно, когда harness
проверяют вместе с обычными тестами проекта в одном прогоне.

Зависимости: pytest. PyYAML — по желанию (без него часть проверок пропускается).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

# --- границы проверяемого проекта --------------------------------------------

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("HARNESS_ROOT", HERE.parent)).resolve()

CONTRACT_NAMES = [
    "CLAUDE.md",
    "AGENTS.md",
    "GEMINI.md",
    ".cursorrules",
    ".github/copilot-instructions.md",
]
ENTRYPOINTS = ["Makefile", "justfile", "Taskfile.yml", "package.json", "pyproject.toml"]
COMMAND_DIRS = [".claude/commands", ".agent/commands", ".github/prompts"]

MAX_CONTRACT_LINES = int(os.environ.get("MAX_CONTRACT_LINES", "200"))
MAX_CONTRACT_BYTES = int(os.environ.get("MAX_CONTRACT_BYTES", "24000"))
MAX_COMMAND_LINES = int(os.environ.get("MAX_CMD_LINES", "120"))

SECRET_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"ghp_[A-Za-z0-9]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]

RITUAL = re.compile(
    r"(думай шаг за шагом|think step by step|ты — эксперт|you are an expert|"
    r"ты — опытный|делай всё хорошо)",
    re.IGNORECASE,
)


# --- вспомогательное ----------------------------------------------------------


def first_existing(names: list[str]) -> Path | None:
    for name in names:
        path = ROOT / name
        if path.exists():
            return path
    return None


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def command_files() -> list[Path]:
    files: list[Path] = []
    for directory in COMMAND_DIRS:
        base = ROOT / directory
        if base.is_dir():
            files.extend(sorted(base.rglob("*.md")))
    return files


@pytest.fixture(scope="session")
def contract() -> Path:
    path = first_existing(CONTRACT_NAMES)
    if path is None:
        pytest.fail(
            "нет корневого контракта. Ожидался один из: " + ", ".join(CONTRACT_NAMES)
        )
    return path


# =============================================================================
#  T01 · структура
# =============================================================================


def test_contract_exists(contract: Path) -> None:
    """Без контракта агент каждый раз заново угадывает правила проекта."""
    assert contract.stat().st_size > 0, f"{contract.name} пустой"


def test_entrypoint_exists() -> None:
    """Если «как прогнать тесты» знает только человек, агент будет придумывать."""
    assert first_existing(ENTRYPOINTS) is not None, (
        "нет единой точки входа: " + ", ".join(ENTRYPOINTS)
    )


def test_readme_exists() -> None:
    assert (ROOT / "README.md").is_file(), "нет README.md"


def test_gitignore_exists() -> None:
    assert (ROOT / ".gitignore").is_file(), "нет .gitignore"


@pytest.mark.parametrize(
    ("label", "pattern"),
    [
        ("как запускать тесты", r"(тест|test|pytest|jest|go test|cargo test)"),
        ("как линтовать", r"(линт|lint|ruff|eslint|clippy|golangci|форматир)"),
        ("что запрещено", r"(запрещ|нельзя|не трогай|do not|never)"),
        ("где что лежит", r"(структур|архитектур|каталог|модул|layout)"),
    ],
)
def test_contract_answers_question(contract: Path, label: str, pattern: str) -> None:
    """Контракт обязан отвечать на четыре вопроса, иначе он декоративный."""
    assert re.search(pattern, read(contract), re.IGNORECASE), (
        f"контракт не отвечает на вопрос: {label}"
    )


# =============================================================================
#  T02 · бюджет контекста
# =============================================================================


def test_contract_is_short(contract: Path) -> None:
    """Контекст — канал с конечной пропускной способностью."""
    lines = len(read(contract).splitlines())
    assert lines <= MAX_CONTRACT_LINES, (
        f"{contract.name}: {lines} строк при лимите {MAX_CONTRACT_LINES}"
    )


def test_contract_is_light(contract: Path) -> None:
    size = contract.stat().st_size
    assert size <= MAX_CONTRACT_BYTES, (
        f"{contract.name}: {size} байт при лимите {MAX_CONTRACT_BYTES}"
    )


def test_contract_has_structure(contract: Path) -> None:
    """Плоская простыня хуже извлекается и хуже правится."""
    headings = re.findall(r"^#{1,3} ", read(contract), re.MULTILINE)
    assert len(headings) >= 3, f"заголовков всего {len(headings)}"


def test_contract_has_concrete_rules(contract: Path) -> None:
    """Антиметрика к «контракт короткий»: короткий и пустой — не достижение."""
    bullets = re.findall(r"^\s*[-*] ", read(contract), re.MULTILINE)
    assert len(bullets) >= 5, f"конкретных пунктов всего {len(bullets)}"


def test_contract_has_no_placeholders(contract: Path) -> None:
    leftovers = re.findall(r"\b(TODO|FIXME|XXX|TBD)\b", read(contract))
    assert not leftovers, f"незакрытые заглушки: {sorted(set(leftovers))}"


def test_contract_has_no_ritual_phrases(contract: Path) -> None:
    """Заклинания занимают контекст и ничего не гарантируют."""
    found = RITUAL.findall(read(contract))
    assert not found, f"ритуальные фразы: {sorted(set(found))}"


def test_contract_imports_resolve(contract: Path) -> None:
    refs = re.findall(r"@([A-Za-z0-9_./\-]+\.(?:md|json|ya?ml|sh|py|ts))", read(contract))
    missing = [r for r in refs if not (ROOT / r).exists()]
    assert not missing, f"битые @-импорты: {missing}"


# =============================================================================
#  T03 · слэш-команды
# =============================================================================


def _command_ids() -> list[str]:
    return [p.stem for p in command_files()] or ["<нет команд>"]


@pytest.mark.parametrize("cmd", command_files() or [None], ids=_command_ids())
def test_command_is_valid(cmd: Path | None) -> None:
    """Команда агента — это функция: имя, вход, выход, контракт."""
    if cmd is None:
        pytest.skip("каталог команд отсутствует")

    text = read(cmd)
    problems: list[str] = []

    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", cmd.stem):
        problems.append("имя не в kebab-case")
    if not text.startswith("---"):
        problems.append("нет YAML-фронтматтера")
    if not re.search(r"^description:", text, re.MULTILINE):
        problems.append("нет description")
    if not re.search(
        r"(критерий приёмк|критерий приемк|acceptance|готово, когда|definition of done)",
        text,
        re.IGNORECASE,
    ):
        problems.append("нет критерия приёмки")
    if len(text.splitlines()) > MAX_COMMAND_LINES:
        problems.append(f"длиннее {MAX_COMMAND_LINES} строк")
    if re.search(r"(/Users/[a-zA-Z]|/home/[a-zA-Z])", text):
        problems.append("абсолютный путь с чужой машины")
    if re.search(r"(rm -rf /(\s|$)|git push --force|--no-verify)", text):
        problems.append("разрушительная операция без ограды")

    assert not problems, f"{cmd.relative_to(ROOT)}: " + "; ".join(problems)


# =============================================================================
#  T04 · ворота
# =============================================================================


def test_ci_exists() -> None:
    """Ворота, работающие только на вашей машине, — не ворота."""
    workflows = list((ROOT / ".github" / "workflows").glob("*.y*ml"))
    gitlab = ROOT / ".gitlab-ci.yml"
    assert workflows or gitlab.exists(), "нет конфигурации CI"


def test_hook_settings_are_valid_json() -> None:
    for name in (".claude/settings.json", ".agent/settings.json"):
        path = ROOT / name
        if path.exists():
            json.loads(read(path))


def test_no_secrets_committed() -> None:
    """Секрет в репозитории уезжает в контекст модели целиком."""
    suspicious: list[str] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git/" in str(path):
            continue
        if path.suffix not in {".md", ".json", ".yml", ".yaml", ".env", ".txt", ".py", ".sh"}:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                suspicious.append(str(path.relative_to(ROOT)))
                break
    assert not suspicious, f"похоже на секреты: {suspicious[:5]}"


# =============================================================================
#  T05 · золотой набор
# =============================================================================

GOLDEN = ROOT / "tests" / "golden" / "cases.yaml"
if not GOLDEN.exists():
    GOLDEN = HERE / "golden" / "cases.yaml"


@pytest.mark.skipif(not GOLDEN.exists(), reason="нет золотого набора")
def test_golden_set_is_usable() -> None:
    yaml = pytest.importorskip("yaml", reason="нужен PyYAML")
    data = yaml.safe_load(read(GOLDEN))

    cases = data.get("cases") or []
    assert len(cases) >= 8, f"задач всего {len(cases)}"

    ids = [c["id"] for c in cases]
    assert len(ids) == len(set(ids)), "дубли id"

    assert int(data.get("runs_per_case", 0)) >= 3, (
        "по одному прогону нельзя судить о стохастическом процессе"
    )

    for case in cases:
        for field in ("title", "category", "difficulty", "prompt", "accept", "reject"):
            assert case.get(field), f"{case.get('id')}: нет поля {field}"

    categories = {c["category"] for c in cases}
    assert len(categories) >= 3, f"категорий всего {len(categories)}"
    assert "safety" in categories, "нет задач на отказ от опасного действия"

    rates = [c.get("baseline", {}).get("pass_rate", 0) for c in cases]
    assert min(rates) < 0.95, "весь набор проходится почти всегда — он ничего не различает"


# =============================================================================
#  T06 · самотест: проверки обязаны падать
# =============================================================================

BAD_FIXTURE = HERE / "fixtures" / "bad-harness"
GOOD_FIXTURE = HERE / "fixtures" / "good-harness"


@pytest.mark.slow
@pytest.mark.skipif(not BAD_FIXTURE.is_dir(), reason="нет сломанной фикстуры")
def test_suite_fails_on_broken_fixture() -> None:
    """Тест, который никогда не падал, — не тест, а украшение."""
    result = subprocess.run(
        [sys.executable, "-m", "pytest", str(Path(__file__)), "-q", "-x", "-m", "not slow"],
        env={**os.environ, "HARNESS_ROOT": str(BAD_FIXTURE)},
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert result.returncode != 0, (
        "проверки прошли на заведомо сломанной обвязке — они ничего не ловят"
    )


@pytest.mark.slow
@pytest.mark.skipif(not GOOD_FIXTURE.is_dir(), reason="нет эталонной фикстуры")
def test_suite_passes_on_good_fixture() -> None:
    """Обратная сторона: придирчивые тесты отключают, и они перестают защищать."""
    result = subprocess.run(
        [sys.executable, "-m", "pytest", str(Path(__file__)), "-q", "-m", "not slow"],
        env={**os.environ, "HARNESS_ROOT": str(GOOD_FIXTURE)},
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, (
        "ложное срабатывание на корректной обвязке:\n" + result.stdout[-2000:]
    )
