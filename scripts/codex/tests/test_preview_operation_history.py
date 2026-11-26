"""Synthetic regressions for the historical workbook preflight."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys
import unittest

from openpyxl import Workbook


SPEC = spec_from_file_location(
    "preview_operation_history",
    Path(__file__).resolve().parents[1] / "preview-operation-history.py",
)
preview = module_from_spec(SPEC)
sys.modules[SPEC.name] = preview
SPEC.loader.exec_module(preview)

COMPANY_A = "10101010-1010-4010-8010-101010101010"
COMPANY_B = "20202020-2020-4020-8020-202020202020"
ORIGINAL = "a" * 64
REORDERED = "b" * 64


def sheet(name, company, digest, entries):
    book = Workbook()
    worksheet = book.active
    worksheet.title = name
    for index, header in preview.ARCHIVE_HEADERS.items():
        worksheet.cell(1, index + 1, header)
    for row, folio, customer in entries:
        worksheet.cell(row, 1, folio)
        worksheet.cell(row, 30, customer)
    return preview.read_sheet(worksheet, company, digest)


class HistoryPreviewTest(unittest.TestCase):
    def setUp(self):
        archived = sheet("A", COMPANY_A, ORIGINAL, [(2, "QA-001", "Cliente sintético")])
        self.existing = [archived.candidates[0][1]]

    def test_reordered_row_keeps_existing_origin(self):
        a = sheet("A", COMPANY_A, REORDERED, [(9, " QA-001 ", "Cliente sintético")])
        result = preview.assess({"A": a}, self.existing)["A"]
        self.assertEqual((result["aptos"], result["ya_existen"], result["hold"]), (0, 1, 0))
        self.assertEqual(result["revision"][0]["filas_folio"], [9])
        self.assertEqual(result["revision"][0]["procedencia_existente"], {
            "source_sha256": ORIGINAL, "source_sheet": "A", "source_row": 2,
        })
        self.assertNotIn("QA-001", str(result))
        self.assertNotIn("Cliente sintético", str(result))

    def test_changed_content_is_not_inserted_or_overwritten(self):
        a = sheet("A", COMPANY_A, REORDERED, [(9, "QA-001", "Dato cambiado")])
        result = preview.assess({"A": a}, self.existing)["A"]
        self.assertEqual((result["aptos"], result["ya_existen"], result["hold"]), (0, 0, 1))
        self.assertEqual(result["causas_hold"], {"contenido_modificado": 1})
        self.assertEqual(self.existing[0].content.source_customer_name, "Cliente sintético")

    def test_equal_folio_in_another_company_has_independent_identity(self):
        a = sheet("A", COMPANY_A, REORDERED, [(3, "QA-001", "Cliente sintético")])
        b = sheet("B", COMPANY_B, REORDERED, [(3, "QA-001", "Otro cliente sintético")])
        result = preview.assess({"A": a, "B": b}, self.existing)
        self.assertEqual((result["A"]["ya_existen"], result["B"]["aptos"]), (1, 1))
        self.assertEqual(result["B"]["ya_existen"], 0)

    def test_repeat_and_continuation_are_held_without_counting_empty_folio(self):
        a = sheet("A", COMPANY_A, REORDERED, [
            (2, None, "Sin folio"),
            (3, "QA-001", "Cliente sintético"),
            (4, None, "Continuación sin acreditar"),
            (5, "qa-001", "Cliente sintético"),
            (6, "QA-002", "Cliente sintético"),
        ])
        result = preview.assess({"A": a}, self.existing)["A"]
        self.assertEqual((result["folios_distintos"], result["hold"], result["aptos"]), (2, 1, 1))
        self.assertEqual(result["filas_continuacion_hold"], [2, 4])
        self.assertEqual(result["filas_continuacion_sin_folio_candidato"], [2])
        self.assertEqual(set(result["causas_hold"]), {
            "folio_repetido_en_la_empresa", "continuacion_sin_vinculo_acreditado", "contenido_modificado",
        })

    def test_same_source_position_cannot_move_to_another_company(self):
        a = sheet("A", COMPANY_B, ORIGINAL, [(2, "QA-001", "Cliente sintético")])
        result = preview.assess({"A": a}, self.existing)["A"]
        self.assertEqual(result["causas_hold"], {"procedencia_apunta_a_otro_registro": 1})

    def test_formula_in_literal_field_goes_to_review(self):
        a = sheet("A", COMPANY_A, REORDERED, [(2, "QA-002", "=1+1")])
        result = preview.assess({"A": a}, self.existing)["A"]
        self.assertEqual(result["causas_hold"], {"contenido_de_origen_no_conservable": 1})

    def test_labels_and_uncertain_formats_never_become_ready(self):
        a = sheet("A", COMPANY_A, REORDERED, [
            (2, "Cancelado", "Etiqueta sintética"),
            (3, "QA-001 / 5", "Referencia múltiple sintética"),
            (4, "QA-002", "Cliente sintético"),
            (5, "QA-001/5", "Posible variante de la referencia"),
        ])
        result = preview.assess({"A": a}, [])
        self.assertEqual(result["A"]["filas_sin_folio_acreditado"], [2])
        self.assertEqual(result["A"]["folios_distintos"], 3)
        self.assertEqual((result["A"]["aptos"], result["A"]["hold"]), (1, 2))
        self.assertEqual(result["A"]["causas_hold"], {"formato_de_folio_no_acreditado": 2})

    def test_verified_archived_reference_keeps_literal_spacing(self):
        archived = sheet("A", COMPANY_A, ORIGINAL, [(2, "QA-001 / 5", "Cliente sintético")])
        moved = sheet("A", COMPANY_A, REORDERED, [(3, "QA-001 / 5", "Cliente sintético")])
        result = preview.assess({"A": moved}, [archived.candidates[0][1]])["A"]
        self.assertEqual((result["aptos"], result["ya_existen"], result["hold"]), (0, 1, 0))


if __name__ == "__main__":
    unittest.main()
