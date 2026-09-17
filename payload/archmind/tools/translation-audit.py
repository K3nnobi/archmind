#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

DEFAULT_ROOT = Path.home() / ".config" / "archmind"

TEXT_EXTENSIONS = {
    ".zsh",
    ".sh",
    ".bash",
    ".md",
    ".txt",
    ".conf",
    ".ini",
    ".toml",
    ".yaml",
    ".yml",
    ".json",
    ".desktop",
    ".py",
    ".in",
}

SKIP_DIRECTORIES = {
    ".git",
    "__pycache__",
    ".cache",
    "node_modules",
    "backups",
    "backup",
}

PORTUGUESE_WORDS = {
    "abrir",
    "ajuda",
    "aguardando",
    "alterar",
    "alterações",
    "ambiente",
    "arquivo",
    "arquivos",
    "armazenamento",
    "atual",
    "atualização",
    "atualizações",
    "atualizado",
    "ativo",
    "aviso",
    "cancelar",
    "cancelado",
    "cancelada",
    "caminho",
    "completo",
    "configuração",
    "configurações",
    "computador",
    "confirmar",
    "concluído",
    "concluída",
    "continuar",
    "criar",
    "criando",
    "dados",
    "diagnóstico",
    "diretório",
    "disco",
    "disponível",
    "encerrar",
    "erro",
    "executar",
    "falha",
    "falhou",
    "fechar",
    "informação",
    "informações",
    "instalação",
    "instalar",
    "instalado",
    "instalando",
    "inválido",
    "lista",
    "listar",
    "memória",
    "modelo",
    "modelos",
    "monitoramento",
    "nenhum",
    "nenhuma",
    "novo",
    "pacote",
    "pacotes",
    "pasta",
    "parcial",
    "perfil",
    "perfis",
    "principal",
    "pressione",
    "processador",
    "processos",
    "pronto",
    "projeto",
    "rede",
    "resumo",
    "relatório",
    "restaurar",
    "restauração",
    "selecionado",
    "configurado",
    "configurados",
    "detectado",
    "detectada",
    "encontrado",
    "encontrada",
    "mantido",
    "mantida",
    "preservado",
    "preservada",
    "necessário",
    "necessária",
    "indisponível",
    "serviço",
    "serviços",
    "sim",
    "sistema",
    "sucesso",
    "tamanho",
    "temperatura",
    "temperaturas",
    "tema",
    "último",
    "válido",
    "verificação",
    "voltar",
}

ACCENT_PATTERN = re.compile(r"[áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÜÇ]")
WORD_PATTERN = re.compile(r"[A-Za-zÀ-ÿ]+", re.UNICODE)
LEGACY_IDENTIFIER_PATTERNS = (
    re.compile(r"^\s*(?:completo|pacotes|projeto|sistema_atual)(?:\||\))"),
    re.compile(r"ArchMind-(?:completo|pacotes|projeto)-"),
    re.compile(r"\b(?:create_backup|restore_backup)\s+(?:completo|pacotes|projeto)\b"),
    re.compile(r"\brestore_by_situation\s+sistema_atual\b"),
)


@dataclass(frozen=True)
class Finding:
    path: Path
    line_number: int
    text: str
    reasons: tuple[str, ...]


def should_skip(path: Path, root: Path) -> bool:
    try:
        relative = path.relative_to(root)
    except ValueError:
        return True

    if path.name in {"translation-audit.py", "find_ptbr.sh"}:
        return True

    for part in relative.parts:
        lowered = part.lower()

        if lowered in SKIP_DIRECTORIES:
            return True

        if lowered.startswith("archmind.backup"):
            return True

        if ".backup-" in lowered or lowered.endswith(".backup"):
            return True

    return False


def is_text_candidate(path: Path) -> bool:
    if path.suffix.lower() in TEXT_EXTENSIONS:
        return True

    return path.name in {
        "archmind",
        "archmind-console",
        "archmind-manager",
    }


def line_reasons(line: str) -> tuple[str, ...]:
    reasons: list[str] = []

    if any(pattern.search(line) for pattern in LEGACY_IDENTIFIER_PATTERNS):
        return ()

    if ACCENT_PATTERN.search(line):
        reasons.append("accented Portuguese character")

    words = {
        word.casefold()
        for word in WORD_PATTERN.findall(line)
    }

    matches = sorted(words.intersection(PORTUGUESE_WORDS))

    if matches:
        reasons.append("keywords: " + ", ".join(matches))

    return tuple(reasons)


def scan(root: Path) -> list[Finding]:
    findings: list[Finding] = []

    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue

        if should_skip(path, root):
            continue

        if not is_text_candidate(path):
            continue

        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue

        for line_number, line in enumerate(content.splitlines(), start=1):
            reasons = line_reasons(line)

            if not reasons:
                continue

            findings.append(
                Finding(
                    path=path,
                    line_number=line_number,
                    text=line.strip(),
                    reasons=reasons,
                )
            )

    return findings


def print_report(root: Path, findings: list[Finding]) -> None:
    affected_files = Counter(finding.path for finding in findings)

    print()
    print("=" * 72)
    print("ArchMind Translation Audit")
    print("=" * 72)
    print(f"Root: {root}")
    print(f"Possible Portuguese strings: {len(findings)}")
    print(f"Affected files: {len(affected_files)}")
    print()

    if not findings:
        print("No possible Portuguese strings were found.")
        print()
        print("Translation status: PASS")
        print("=" * 72)
        return

    current_path: Path | None = None

    for finding in findings:
        if finding.path != current_path:
            current_path = finding.path
            relative = current_path.relative_to(root)

            print()
            print(f"[{relative}]")
            print("-" * 72)

        print(f"Line {finding.line_number}: {finding.text}")
        print(f"Reason: {'; '.join(finding.reasons)}")
        print()

    print("=" * 72)
    print("Translation status: REVIEW REQUIRED")
    print("=" * 72)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Find possible Portuguese strings in ArchMind source files."
    )

    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=DEFAULT_ROOT,
        help="ArchMind project root.",
    )

    parser.add_argument(
        "--strict",
        action="store_true",
        help="Return exit code 1 when findings exist.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        help="Write the report to a text file.",
    )

    args = parser.parse_args()
    root = args.root.expanduser().resolve()

    if not root.is_dir():
        print(f"Error: project directory not found: {root}", file=sys.stderr)
        return 2

    findings = scan(root)

    if args.output:
        from contextlib import redirect_stdout

        output = args.output.expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)

        with output.open("w", encoding="utf-8") as handle:
            with redirect_stdout(handle):
                print_report(root, findings)

        print(f"Report written to: {output}")
    else:
        print_report(root, findings)

    if args.strict and findings:
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
