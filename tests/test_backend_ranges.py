import tempfile
import unittest
from pathlib import Path

from PySide6.QtCore import QUrl

from backend import CsvTrendBackend


class BackendThresholdRangesTests(unittest.TestCase):
    """Проверяет расчет температурных диапазонов превышения порога в backend."""

    def _write_node_csv(self, folder: Path, filename: str, rows: list[tuple[float, float]]) -> Path:
        """Создает тестовый CSV одного узла с температурой и уровнем топлива."""
        content_lines = ["Время;Период;Температура (°C);Топливо (%)"]
        for index, (temp, fuel) in enumerate(rows):
            content_lines.append(f"12:00:{index:02d};10000;{str(temp).replace('.', ',')};{str(fuel).replace('.', ',')}")
        path = folder / filename
        path.write_text("\n".join(content_lines) + "\n", encoding="utf-8")
        return path

    def test_builds_merged_ranges_for_selected_nodes(self) -> None:
        """Должен объединять температурные диапазоны превышения порога по выбранным узлам."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            p1 = self._write_node_csv(
                root,
                "0x8a.csv",
                [(-20.0, 1.0), (-10.0, 3.0), (0.0, 4.0), (10.0, 1.0), (20.0, 0.5)],
            )
            p2 = self._write_node_csv(
                root,
                "0x8b.csv",
                [(-20.0, 0.7), (-10.0, 1.5), (0.0, 3.0), (10.0, 3.0), (20.0, 1.0)],
            )

            backend = CsvTrendBackend()
            backend.loadCsvFiles([QUrl.fromLocalFile(str(p1)), QUrl.fromLocalFile(str(p2))])
            backend.setViewMode(1)
            backend.setAllNodesVisible(True)
            backend.setFuelDeviationThreshold(2.0)

            ranges = backend.criticalTemperatureRanges
            summary = backend.selectedSummaryMetrics

        self.assertEqual(1, len(ranges))
        self.assertAlmostEqual(-10.0, float(ranges[0]["startTemp"]))
        self.assertAlmostEqual(10.0, float(ranges[0]["endTemp"]))
        self.assertEqual(1, int(summary["rangeCount"]))
        self.assertEqual("0x8a", str(summary["worstNode"]))
        self.assertAlmostEqual(4.0, float(summary["worstAbsFuel"]), places=3)

    def test_node_metrics_include_threshold_ranges(self) -> None:
        """Должен включать диапазоны превышения порога в метрики узла."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            p1 = self._write_node_csv(
                root,
                "0x6a.csv",
                [(-5.0, 0.5), (0.0, 2.5), (5.0, 2.8), (10.0, 0.2)],
            )

            backend = CsvTrendBackend()
            backend.loadCsvFiles([QUrl.fromLocalFile(str(p1))])
            backend.setFuelDeviationThreshold(2.0)
            metrics = backend.nodeMetricsRows

        self.assertEqual(1, len(metrics))
        self.assertEqual(1, int(metrics[0]["thresholdRangeCount"]))
        self.assertIn("0.0..5.0", str(metrics[0]["thresholdRangesText"]))

    def test_filters_out_point_like_temperature_ranges(self) -> None:
        """Должен исключать короткие диапазоны вида 3.8..3.8 из текстовых метрик."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            p1 = self._write_node_csv(
                root,
                "0x6c.csv",
                [(-10.0, 0.2), (3.8, 3.2), (3.8, 3.4), (12.0, 0.1)],
            )

            backend = CsvTrendBackend()
            backend.loadCsvFiles([QUrl.fromLocalFile(str(p1))])
            backend.setFuelDeviationThreshold(2.0)
            metrics = backend.nodeMetricsRows
            summary = backend.selectedSummaryMetrics

        self.assertEqual(1, len(metrics))
        self.assertEqual(0, int(metrics[0]["thresholdRangeCount"]))
        self.assertIn("Нет диапазонов", str(metrics[0]["thresholdRangesText"]))
        self.assertEqual(0, int(summary["rangeCount"]))


if __name__ == "__main__":
    unittest.main()
