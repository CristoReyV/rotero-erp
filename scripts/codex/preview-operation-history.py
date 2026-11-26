"""Plan a local historical-operations import without writing to a database."""

from argparse import ArgumentParser
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from datetime import date, datetime
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Literal
from uuid import UUID
from zipfile import BadZipFile

from openpyxl import load_workbook
from openpyxl.utils.exceptions import InvalidFileException


ARCHIVE_HEADERS = {
    0: "folio wls",
    14: "línea transportista",
    29: "cliente",
    32: "fecha de despacho / cruce",
}
# These are the candidate continuation markers in the workbook preview.
CONTINUATION_FIELDS = (1, 14, 15, 29, 32, 34, 36, 37)
# The source folio column also contains labels and mixed references. The local
# preview only proposes compact identifiers as new entries without review.
FOLIO_DIGIT = re.compile(r"[0-9]")
FOLIO_FORM = re.compile(r"[A-Za-z0-9]+(?:[-_/][A-Za-z0-9]+)*")


@dataclass(frozen=True)
class Origin:
    source_sha256: str
    source_sheet: str
    source_row: int


@dataclass(frozen=True)
class Content:
    reference_code: str
    source_customer_name: str | None
    source_carrier_name: str | None
    source_dispatch_crossing_date: str | None


@dataclass(frozen=True)
class Candidate:
    company_id: str
    origin: Origin
    content: Content | None


@dataclass(frozen=True)
class Sheet:
    candidates: list[tuple[str, Candidate]]
    continuations: list[tuple[int, str | None]]
    invalid_rows: list[int]


def present(value) -> bool:
    return value is not None and (not isinstance(value, str) or bool(value.strip()))


def folio_key(folio: str) -> str:
    # Mirrors the archive's company-scoped unique index after input trimming.
    return folio.strip().lower()


def keys_needing_spacing_review(keys: set[tuple[str, str]]) -> set[tuple[str, str]]:
    review = set()
    for company_id, folio in keys:
        compact = re.sub(r"\s+", "", folio)
        if folio != compact and FOLIO_FORM.fullmatch(compact):
            review.add((company_id, compact))
    return review


def literal(cell, max_length: int, *, date_allowed: bool = False) -> str | None:
    value = cell.value
    if not present(value):
        return None
    if cell.data_type in ("f", "e"):
        raise ValueError("archive cell needs source review")
    if date_allowed and isinstance(value, date):
        if isinstance(value, datetime) and value.time() == datetime.min.time():
            value = value.date()
        value = value.isoformat()
    if not isinstance(value, str) or len(value) > max_length or "\x00" in value:
        raise ValueError("archive cell cannot be stored as source text")
    return value


def read_sheet(worksheet, company_id: str, digest: str) -> Sheet:
    headers = next(worksheet.iter_rows(min_row=1, max_row=1, max_col=39, values_only=True), ())
    if any(str(headers[i] or "").strip().casefold() != name for i, name in ARCHIVE_HEADERS.items()):
        raise ValueError("unexpected archive column headings")
    candidates, continuations, invalid_rows = [], [], []
    nearest_folio = None
    for row_number, row in enumerate(worksheet.iter_rows(min_row=2, max_col=39), 2):
        first = row[0]
        if not present(first.value):
            if any(present(row[i].value) for i in CONTINUATION_FIELDS) and any(
                present(cell.value) and cell.data_type != "f" for cell in row
            ):
                continuations.append((row_number, nearest_folio))
            continue
        if str(first.value).strip().casefold() == "folio wls":
            nearest_folio = None
            continue
        if first.data_type not in ("s", "n") or type(first.value) not in (str, int, float):
            invalid_rows.append(row_number)
            nearest_folio = None
            continue
        folio = str(first.value).strip()
        if not FOLIO_DIGIT.search(folio) or len(folio) > 160 or any(ord(c) < 32 for c in folio):
            invalid_rows.append(row_number)
            nearest_folio = None
            continue
        nearest_folio = folio_key(folio)
        origin = Origin(digest, worksheet.title, row_number)
        try:
            content = Content(
                folio,
                literal(row[29], 500),
                literal(row[14], 500),
                literal(row[32], 1000, date_allowed=True),
            )
        except ValueError:
            content = None
        candidates.append((nearest_folio, Candidate(company_id, origin, content)))
    return Sheet(candidates, continuations, invalid_rows)


def digest_of(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_book(path: Path, company_map: dict[str, str]) -> tuple[str, dict[str, Sheet]]:
    digest = digest_of(path)
    book = load_workbook(path, read_only=True, data_only=False, keep_links=False)
    try:
        for name in set(book.sheetnames) - company_map.keys():
            first_row = next(book[name].iter_rows(max_row=1, max_col=1, values_only=True), ())
            if first_row and str(first_row[0] or "").strip().casefold() == "folio wls":
                raise ValueError("each operations sheet requires explicit company mapping")
        sheets = {sheet: read_sheet(book[sheet], company_id, digest) for sheet, company_id in company_map.items()}
    finally:
        book.close()
    if digest_of(path) != digest:
        raise ValueError("the workbook changed during its review")
    return digest, sheets


def load_mapping(value: dict) -> dict[str, str]:
    if not isinstance(value, dict) or not value:
        raise ValueError("company mapping must be a nonempty sheet-to-UUID object")
    result = {name: str(UUID(company_id)) for name, company_id in value.items()}
    if len(set(result.values())) != len(result):
        raise ValueError("use one distinct approved company per source sheet")
    return result


def existing_rows(value: list[dict]) -> list[Candidate]:
    if not isinstance(value, list):
        raise ValueError("existing archive input must be an array")
    rows = []
    for row in value:
        content = Content(*(row[key] for key in Content.__dataclass_fields__))
        origin = Origin(*(row[key] for key in Origin.__dataclass_fields__))
        if (
            not isinstance(content.reference_code, str) or not folio_key(content.reference_code)
            or any(x is not None and not isinstance(x, str) for x in (
                content.source_customer_name, content.source_carrier_name, content.source_dispatch_crossing_date
            ))
            or not isinstance(origin.source_sha256, str) or len(origin.source_sha256) != 64
            or any(c not in "0123456789abcdef" for c in origin.source_sha256)
            or not isinstance(origin.source_sheet, str) or not origin.source_sheet.strip()
            or type(origin.source_row) is not int or origin.source_row < 2
        ):
            raise ValueError("invalid existing archive row")
        rows.append(Candidate(str(UUID(row["company_id"])), origin, content))
    return rows


Outcome = Literal["apto", "ya_existe", "hold"]


def assess(sheets: dict[str, Sheet], existing: list[Candidate]) -> dict:
    by_business_key, by_origin = {}, {}
    for row in existing:
        if row.content is None:
            raise ValueError("existing history requires source content")
        key = (row.company_id, folio_key(row.content.reference_code))
        if key in by_business_key or row.origin in by_origin:
            raise ValueError("existing archive snapshot has conflicting identities")
        by_business_key[key] = row
        by_origin[row.origin] = key

    incoming_keys = {(row.company_id, key) for sheet in sheets.values() for key, row in sheet.candidates}
    spacing_review = keys_needing_spacing_review(by_business_key.keys() | incoming_keys)
    report = {}
    for name, sheet in sheets.items():
        counts: Counter[Outcome] = Counter()
        reasons = Counter()
        grouped = defaultdict(list)
        potential_continuations = defaultdict(list)
        for key, row in sheet.candidates:
            grouped[key].append(row)
        for line, candidate_key in sheet.continuations:
            if candidate_key is not None:
                potential_continuations[candidate_key].append(line)

        reviews = []
        for folio, rows in grouped.items():
            row = rows[0]
            key = (row.company_id, folio)
            previous = by_business_key.get(key)
            nearby = potential_continuations.get(folio, [])
            blockers = []
            if len(rows) > 1:
                blockers.append("folio_repetido_en_la_empresa")
            if previous is None and (not FOLIO_FORM.fullmatch(folio) or key in spacing_review):
                blockers.append("formato_de_folio_no_acreditado")
            if nearby:
                blockers.append("continuacion_sin_vinculo_acreditado")
            if any(item.content is None for item in rows):
                blockers.append("contenido_de_origen_no_conservable")
            if previous and any(item.content is not None and item.content != previous.content for item in rows):
                blockers.append("contenido_modificado")
            if any(by_origin.get(item.origin, key) != key for item in rows):
                blockers.append("procedencia_apunta_a_otro_registro")
            decision = "hold" if blockers else "ya_existe" if previous else "apto"
            counts[decision] += 1
            reasons.update(blockers)
            review = {
                "decision": decision,
                "filas_folio": [item.origin.source_row for item in rows],
            }
            if previous:
                review["procedencia_existente"] = asdict(previous.origin)
            if blockers:
                review["causas"] = blockers
            if nearby:
                review["filas_continuacion_sin_vinculo"] = nearby
            reviews.append(review)

        report[name] = {
            "folios_distintos": len(grouped),
            "aptos": counts["apto"],
            "ya_existen": counts["ya_existe"],
            "hold": counts["hold"],
            "causas_hold": dict(reasons),
            "filas_continuacion_hold": [line for line, _ in sheet.continuations],
            "filas_continuacion_sin_folio_candidato": [line for line, key in sheet.continuations if key is None],
            "filas_sin_folio_acreditado": sheet.invalid_rows,
            "revision": reviews,
        }
    return report


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--company-map", required=True, type=Path, help="JSON object of sheet name to vetted company UUID")
    parser.add_argument("--existing", type=Path, help="Optional isolated archive snapshot in JSON")
    parser.add_argument("--output", type=Path, help="New JSON evidence file with source locations, never raw cell values")
    args = parser.parse_args()
    try:
        mapping = load_mapping(json.loads(args.company_map.read_text(encoding="utf-8-sig")))
        existing = existing_rows(json.loads(args.existing.read_text(encoding="utf-8-sig"))) if args.existing else []
        digest, sheets = read_book(args.source, mapping)
        report = {
            "source_sha256": digest,
            "mode": "read_only",
            "existing_snapshot_rows": len(existing),
            "sheets": assess(sheets, existing),
        }
        if args.output:
            with args.output.open("x", encoding="utf-8") as out:
                json.dump(report, out, ensure_ascii=True, indent=2)
        summary = {
            name: {key: result[key] for key in ("folios_distintos", "aptos", "ya_existen", "hold", "causas_hold")}
            | {
                "continuaciones_hold": len(result["filas_continuacion_hold"]),
                "filas_sin_folio_acreditado": len(result["filas_sin_folio_acreditado"]),
            } for name, result in report["sheets"].items()
        }
        print(json.dumps({"source_sha256": digest, "existing_snapshot_rows": len(existing), "sheets": summary}))
    except (OSError, TypeError, AttributeError, ValueError, KeyError, IndexError, InvalidFileException,
            BadZipFile) as error:
        parser.exit(2, f"Archive preview stopped while validating inputs ({type(error).__name__}).\n")


if __name__ == "__main__":
    main()
