import tempfile
import unittest
from pathlib import Path

from PySide6.QtCore import QUrl

from backend import CsvTrendBackend
from app.csv_series_parser import parse_csv_file, parse_many_csv_files


class CsvSeriesParserTests(unittest.TestCase):
    """Проверяет разбор CSV форматов коллектора на тестовых данных."""

    def test_parse_per_node_csv(self) -> None:
        """Должен разбирать CSV отдельного узла и извлекать корректные точки."""
        content = (
            "Время;Период;Температура (°C);Топливо (%);Топливо из периода (x0.1%)\n"
            "12:00:00;12345;25,5;12,3;123\n"
            "12:00:01;12346;26,0;12,5;125\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "0x6a.csv"
            path.write_text(content, encoding="utf-8")
            parsed = parse_csv_file(path)

        self.assertEqual(1, len(parsed))
        self.assertEqual("0x6a", parsed[0].node)
        self.assertEqual(2, len(parsed[0].points))
        self.assertAlmostEqual(25.5, float(parsed[0].points[0]["temperature"]))
        self.assertAlmostEqual(12.5, float(parsed[0].points[1]["fuel"]))

    def test_parse_all_nodes_csv(self) -> None:
        """Должен разбирать all_nodes CSV и выделять серии по каждому узлу."""
        content = (
            "Время;Узел 0x8c;;;;Узел 0x8a;;;;\n"
            ";empty=11793;full=24075;Топливо из периода (%);;empty=11743;full=23973;Топливо из периода (%);\n"
            ";Период;Топливо (%);Температура (°C);Топливо из периода (%);Период;Топливо (%);Температура (°C);Топливо из периода (%)\n"
            "10:33:14.537;11768;0,0;31,2;-0,2;11578;1,0;30,5;-1,3\n"
            "10:33:15.036;11769;0,1;31,3;-0,1;11579;1,1;30,6;-1,2\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "all_nodes.csv"
            path.write_text(content, encoding="utf-8")
            parsed = parse_csv_file(path)

        labels = sorted(item.node for item in parsed)
        self.assertEqual(["0x8a", "0x8c"], labels)
        by_node = {item.node: item for item in parsed}
        self.assertEqual(2, len(by_node["0x8c"].points))
        self.assertEqual(2, len(by_node["0x8a"].points))
        self.assertAlmostEqual(31.2, float(by_node["0x8c"].points[0]["temperature"]))
        self.assertAlmostEqual(1.1, float(by_node["0x8a"].points[1]["fuel"]))

    def test_parse_many_files_with_duplicate_nodes(self) -> None:
        """Должен уникализировать label, если одинаковый узел встречается в нескольких файлах."""
        content = (
            "Время;Период;Температура (°C);Топливо (%)\n"
            "12:00:00;10000;20,0;10,0\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            p1 = Path(tmp) / "0x6a.csv"
            p2 = Path(tmp) / "copy_0x6a.csv"
            p1.write_text(content, encoding="utf-8")
            p2.write_text(content, encoding="utf-8")
            parsed = parse_many_csv_files([p1, p2])

        self.assertEqual(2, len(parsed))
        labels = [item.node for item in parsed]
        self.assertNotEqual(labels[0], labels[1])

    def test_normalize_qml_url_for_file_scheme(self) -> None:
        """Должен корректно конвертировать file URL из QML в локальный путь."""
        with tempfile.TemporaryDirectory() as tmp:
            csv_path = Path(tmp) / "0x6a.csv"
            csv_path.write_text("Время;Период;Температура (°C);Топливо (%)\n", encoding="utf-8")
            qurl = QUrl.fromLocalFile(str(csv_path))
            normalized = CsvTrendBackend._normalize_qml_url(qurl)

        self.assertIsNotNone(normalized)
        self.assertEqual(str(csv_path), str(normalized))

    def test_parse_all_nodes_xlsx(self) -> None:
        """Должен разбирать XLSX формата all_nodes и извлекать серии узлов."""
        try:
            import openpyxl
        except Exception:
            self.skipTest("openpyxl не установлен")

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "all_nodes.xlsx"
            workbook = openpyxl.Workbook()
            worksheet = workbook.active
            worksheet.title = "all_nodes"
            worksheet.append(["Время", "Узел 0x8d", "", "", "", "", "Узел 0x8e", "", "", "", ""])
            worksheet.append(["", "empty=11862", "full=24241", "k1=704", "k0=342", "", "empty=12002", "full=24432", "k1=800", "k0=98", ""])
            worksheet.append(["", "Период", "Топливо (%)", "Топл.(J1939)", "Температура (°C)", "Топливо из периода (%)",
                              "Период", "Топливо (%)", "Топл.(J1939)", "Температура (°C)", "Топливо из периода (%)"])
            worksheet.append(["17:07:12.896", 11462, -0.7, 0, 25.1, -3.2, 11831, -0.9, 0, 24.8, -1.3])
            worksheet.append(["17:07:13.023", 11463, -0.6, 0, 25.2, -3.1, 11832, -0.8, 0, 24.9, -1.2])
            workbook.save(path)

            parsed = parse_csv_file(path)

        labels = sorted(item.node for item in parsed)
        self.assertEqual(["0x8d", "0x8e"], labels)
        by_node = {item.node: item for item in parsed}
        self.assertEqual(2, len(by_node["0x8d"].points))
        self.assertAlmostEqual(25.2, float(by_node["0x8d"].points[1]["temperature"]))


if __name__ == "__main__":
    unittest.main()
