from __future__ import annotations

import math
import re
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from PySide6.QtCore import QObject, Property, QUrl, Signal, Slot

from app.csv_series_parser import ParsedSeries, parse_many_csv_files


class CsvTrendBackend(QObject):
    """Управляет состоянием UI и предоставляет данные серий для построения графиков."""

    dataChanged = Signal()
    statusChanged = Signal()
    busyChanged = Signal()
    xlsxSupportChanged = Signal()

    def __init__(self) -> None:
        """Инициализирует коллекции серий, фильтры отображения и статус загрузки."""
        super().__init__()
        self._status_text = "CSV-файлы не загружены."
        self._series: list[ParsedSeries] = []
        self._selected_node_index = -1
        self._view_mode = 0
        self._show_labels = False
        self._swap_axes = False
        self._node_visible: dict[str, bool] = {}
        self._node_colors: dict[str, str] = {}
        self._visible_series_cache: list[dict[str, object]] = []
        self._node_visibility_rows_cache: list[dict[str, object]] = []
        self._node_metrics_rows_cache: list[dict[str, object]] = []
        self._fuel_deviation_threshold = 2.0
        self._critical_ranges_cache: list[dict[str, object]] = []
        self._selected_summary_metrics_cache: dict[str, object] = {}
        self._min_temp_range_span_c = 1.0
        self._palette = [
            "#2563eb", "#10b981", "#f97316", "#8b5cf6", "#ef4444", "#14b8a6", "#0ea5e9", "#a855f7",
            "#f59e0b", "#22c55e", "#3b82f6", "#e11d48",
        ]
        self._busy = False
        self._xlsx_supported = self._detect_xlsx_support()
        self._status_text = self._build_initial_status_text()

    @staticmethod
    def _detect_xlsx_support() -> bool:
        """Определяет, доступно ли чтение XLSX через установленный пакет openpyxl."""
        try:
            import openpyxl  # noqa: F401
        except Exception:
            return False
        return True

    def _build_initial_status_text(self) -> str:
        """Формирует стартовый статус с подсказкой по доступности XLSX."""
        if self._xlsx_supported:
            return "CSV-файлы не загружены. Формат XLSX поддерживается."
        return "CSV-файлы не загружены. XLSX недоступен: установите пакет openpyxl."

    @staticmethod
    def _normalize_qml_url(raw_path: Any) -> Path | None:
        """Преобразует значение из QML FileDialog в локальный путь файла на диске."""
        if isinstance(raw_path, QUrl):
            local_file = str(raw_path.toLocalFile()).strip()
            if local_file:
                path = Path(local_file)
                if path.exists() and path.is_file():
                    return path

            text_url = str(raw_path.toString()).strip()
        else:
            text_url = str(raw_path or "").strip()

        if not text_url:
            return None

        if text_url.startswith("file:"):
            parsed = urlparse(text_url)
            decoded_path = unquote(parsed.path or "")

            # Цель блока в нормализации Windows-пути из URL вида /D:/folder/file.csv.
            # Он убирает ведущий слэш перед буквой диска.
            if len(decoded_path) >= 3 and decoded_path[0] == "/" and decoded_path[2] == ":":
                decoded_path = decoded_path[1:]

            if parsed.netloc:
                decoded_path = f"//{parsed.netloc}{decoded_path}"

            normalized = decoded_path.replace("/", "\\")
        else:
            normalized = text_url.replace("/", "\\")

        path = Path(normalized)
        if not path.exists() or not path.is_file():
            return None
        return path

    def _emit_all(self) -> None:
        """Обновляет интерфейс после изменения данных или статуса."""
        self.dataChanged.emit()
        self.statusChanged.emit()
        self.busyChanged.emit()
        self.xlsxSupportChanged.emit()

    def _reset_visibility(self) -> None:
        """Пересоздает карту видимости узлов после новой загрузки данных."""
        self._node_visible = {}
        self._node_colors = {}
        for index, item in enumerate(self._series):
            node_label = str(item.node)
            self._node_visible[node_label] = False
            self._node_colors[node_label] = self._palette[index % len(self._palette)]
        self._rebuild_node_visibility_rows_cache()
        self._rebuild_node_metrics_rows_cache()
        self._rebuild_visible_series_cache()

    @staticmethod
    def _normalize_color_hex(value: str) -> str:
        """Нормализует входной цвет к формату #RRGGBB для безопасного применения в UI."""
        text = str(value or "").strip()
        if not text:
            return ""
        if re.fullmatch(r"#[0-9A-Fa-f]{6}", text):
            return text.upper()
        if re.fullmatch(r"#[0-9A-Fa-f]{8}", text):
            return f"#{text[1:7]}".upper()
        return ""

    @staticmethod
    def _mean(values: list[float]) -> float:
        """Возвращает среднее арифметическое для списка чисел."""
        if len(values) <= 0:
            return 0.0
        return float(sum(values)) / float(len(values))

    @staticmethod
    def _std(values: list[float], mean_value: float) -> float:
        """Возвращает стандартное отклонение для списка значений."""
        if len(values) <= 1:
            return 0.0
        variance = sum((value - mean_value) * (value - mean_value) for value in values) / float(len(values) - 1)
        if variance < 0.0:
            return 0.0
        return math.sqrt(variance)

    @staticmethod
    def _format_float(value: float, digits: int = 2) -> str:
        """Форматирует число для отображения в UI."""
        return f"{float(value):.{int(digits)}f}"

    @staticmethod
    def _compute_threshold_ranges(points: list[dict[str, object]], threshold: float) -> list[dict[str, float]]:
        """Находит температурные диапазоны, где модуль уровня топлива превышает заданный порог."""
        if len(points) <= 0:
            return []

        sorted_points = sorted(points, key=lambda item: float(item["temp"]))
        threshold_abs = abs(float(threshold))
        ranges: list[dict[str, float]] = []

        current_start: float | None = None
        current_end: float | None = None
        current_max_abs = 0.0

        for point in sorted_points:
            temp = float(point["temp"])
            fuel_abs = abs(float(point["fuel"]))
            is_above = fuel_abs >= threshold_abs

            if is_above:
                if current_start is None:
                    current_start = temp
                    current_end = temp
                    current_max_abs = fuel_abs
                else:
                    current_end = temp
                    if fuel_abs > current_max_abs:
                        current_max_abs = fuel_abs
            elif current_start is not None and current_end is not None:
                ranges.append(
                    {
                        "startTemp": float(current_start),
                        "endTemp": float(current_end),
                        "maxAbsFuel": float(current_max_abs),
                    }
                )
                current_start = None
                current_end = None
                current_max_abs = 0.0

        if current_start is not None and current_end is not None:
            ranges.append(
                {
                    "startTemp": float(current_start),
                    "endTemp": float(current_end),
                    "maxAbsFuel": float(current_max_abs),
                }
            )

        return ranges

    @staticmethod
    def _merge_temperature_ranges(
        source_ranges: list[dict[str, float]],
        merge_tolerance_c: float = 0.2,
    ) -> list[dict[str, float]]:
        """Объединяет пересекающиеся и близкие температурные диапазоны в общий список."""
        if len(source_ranges) <= 0:
            return []

        sorted_ranges = sorted(source_ranges, key=lambda item: float(item["startTemp"]))
        merged: list[dict[str, float]] = []

        for item in sorted_ranges:
            start_temp = float(item["startTemp"])
            end_temp = float(item["endTemp"])
            if end_temp < start_temp:
                start_temp, end_temp = end_temp, start_temp
            max_abs_fuel = abs(float(item.get("maxAbsFuel", 0.0)))

            if len(merged) <= 0:
                merged.append({"startTemp": start_temp, "endTemp": end_temp, "maxAbsFuel": max_abs_fuel})
                continue

            tail = merged[-1]
            if start_temp <= float(tail["endTemp"]) + float(merge_tolerance_c):
                tail["endTemp"] = max(float(tail["endTemp"]), end_temp)
                tail["maxAbsFuel"] = max(abs(float(tail["maxAbsFuel"])), max_abs_fuel)
            else:
                merged.append({"startTemp": start_temp, "endTemp": end_temp, "maxAbsFuel": max_abs_fuel})

        return merged

    @staticmethod
    def _filter_by_min_span(ranges: list[dict[str, float]], min_span_c: float) -> list[dict[str, float]]:
        """Оставляет только протяженные температурные диапазоны и исключает точечные выбросы."""
        if len(ranges) <= 0:
            return []
        min_span = max(0.0, float(min_span_c))
        filtered: list[dict[str, float]] = []
        for item in ranges:
            span = abs(float(item["endTemp"]) - float(item["startTemp"]))
            if span + 1e-9 >= min_span:
                filtered.append(item)
        return filtered

    def _get_long_threshold_ranges(self, points: list[dict[str, object]], threshold: float) -> list[dict[str, float]]:
        """Собирает диапазоны выше порога, объединяет соседние и оставляет только протяженные участки."""
        raw_ranges = self._compute_threshold_ranges(points, threshold)
        merged_ranges = self._merge_temperature_ranges(raw_ranges)
        return self._filter_by_min_span(merged_ranges, self._min_temp_range_span_c)

    @staticmethod
    def _format_ranges_short(ranges: list[dict[str, float]]) -> str:
        """Формирует короткий текст диапазонов для вывода в метриках."""
        if len(ranges) <= 0:
            return "Нет диапазонов выше порога."
        parts: list[str] = []
        for item in ranges:
            parts.append(
                f"{float(item['startTemp']):.1f}..{float(item['endTemp']):.1f} °C"
                f" (до {abs(float(item['maxAbsFuel'])):.2f} %)"
            )
        return "; ".join(parts)

    def _compute_node_metrics(self, node_label: str, points: list[dict[str, object]]) -> dict[str, object]:
        """Рассчитывает ключевые метрики одного узла по его точкам графика."""
        if len(points) <= 0:
            return {
                "node": node_label,
                "count": 0,
                "tempMin": 0.0,
                "tempMax": 0.0,
                "tempRange": 0.0,
                "fuelMin": 0.0,
                "fuelMax": 0.0,
                "fuelRange": 0.0,
                "fuelMean": 0.0,
                "fuelStd": 0.0,
                "driftFuel": 0.0,
                "driftSlope": 0.0,
                "minPointText": "Нет данных",
                "maxPointText": "Нет данных",
                "thresholdRangeCount": 0,
                "thresholdRangesText": "Нет диапазонов выше порога.",
            }

        normalized: list[dict[str, object]] = []
        for index, point in enumerate(points):
            temp = float(point.get("temperature", 0.0))
            fuel = float(point.get("fuel", 0.0))
            time_text = str(point.get("time", index))
            normalized.append({"temp": temp, "fuel": fuel, "time": time_text})

        by_temp = sorted(normalized, key=lambda item: float(item["temp"]))
        by_fuel = sorted(normalized, key=lambda item: float(item["fuel"]))

        min_fuel_point = by_fuel[0]
        max_fuel_point = by_fuel[-1]
        min_temp_point = by_temp[0]
        max_temp_point = by_temp[-1]

        temp_min = float(min_temp_point["temp"])
        temp_max = float(max_temp_point["temp"])
        fuel_min = float(min_fuel_point["fuel"])
        fuel_max = float(max_fuel_point["fuel"])
        fuel_values = [float(item["fuel"]) for item in normalized]

        fuel_mean = self._mean(fuel_values)
        fuel_std = self._std(fuel_values, fuel_mean)
        temp_range = temp_max - temp_min
        fuel_range = fuel_max - fuel_min
        drift_fuel = float(max_temp_point["fuel"]) - float(min_temp_point["fuel"])
        drift_slope = (drift_fuel / temp_range) if abs(temp_range) > 1e-9 else 0.0

        min_point_text = (
            f"Мин: {self._format_float(fuel_min)}% "
            f"при T={self._format_float(float(min_fuel_point['temp']))}°C, t={min_fuel_point['time']}"
        )
        max_point_text = (
            f"Макс: {self._format_float(fuel_max)}% "
            f"при T={self._format_float(float(max_fuel_point['temp']))}°C, t={max_fuel_point['time']}"
        )
        threshold_ranges = self._get_long_threshold_ranges(normalized, self._fuel_deviation_threshold)

        return {
            "node": node_label,
            "count": len(points),
            "tempMin": temp_min,
            "tempMax": temp_max,
            "tempRange": temp_range,
            "fuelMin": fuel_min,
            "fuelMax": fuel_max,
            "fuelRange": fuel_range,
            "fuelMean": fuel_mean,
            "fuelStd": fuel_std,
            "driftFuel": drift_fuel,
            "driftSlope": drift_slope,
            "minPointText": min_point_text,
            "maxPointText": max_point_text,
            "thresholdRangeCount": len(threshold_ranges),
            "thresholdRangesText": self._format_ranges_short(threshold_ranges),
        }

    def _rebuild_node_metrics_rows_cache(self) -> None:
        """Пересчитывает кэш метрик по каждому узлу на основе загруженных данных."""
        rows: list[dict[str, object]] = []
        for item in self._series:
            rows.append(self._compute_node_metrics(str(item.node), item.points))
        self._node_metrics_rows_cache = rows

    def _rebuild_critical_ranges_cache(self) -> None:
        """Пересчитывает агрегированные диапазоны превышения порога для выбранных серий."""
        all_ranges: list[dict[str, float]] = []
        threshold = abs(float(self._fuel_deviation_threshold))

        for series_item in self._visible_series_cache:
            points = list(series_item.get("points", []))
            if len(points) <= 0:
                continue
            normalized_points: list[dict[str, object]] = []
            for point in points:
                normalized_points.append(
                    {
                        "temp": float(point.get("temperature", 0.0)),
                        "fuel": float(point.get("fuel", 0.0)),
                    }
                )
            all_ranges.extend(self._compute_threshold_ranges(normalized_points, threshold))

        merged = self._merge_temperature_ranges(all_ranges)
        merged = self._filter_by_min_span(merged, self._min_temp_range_span_c)
        output: list[dict[str, object]] = []
        for item in merged:
            output.append(
                {
                    "startTemp": float(item["startTemp"]),
                    "endTemp": float(item["endTemp"]),
                    "maxAbsFuel": abs(float(item["maxAbsFuel"])),
                    "label": (
                        f"{float(item['startTemp']):.1f}..{float(item['endTemp']):.1f} °C"
                        f" | до {abs(float(item['maxAbsFuel'])):.2f} %"
                    ),
                }
            )
        self._critical_ranges_cache = output

    def _rebuild_selected_summary_metrics_cache(self) -> None:
        """Пересчитывает общие метрики по выбранным узлам и текущему порогу отклонения."""
        total_series = len(self._visible_series_cache)
        total_points = 0
        worst_abs_fuel = 0.0
        worst_temp = 0.0
        worst_node = "-"

        for series_item in self._visible_series_cache:
            node_label = str(series_item.get("node", "-"))
            for point in list(series_item.get("points", [])):
                total_points += 1
                fuel_value = float(point.get("fuel", 0.0))
                abs_fuel = abs(fuel_value)
                if abs_fuel > worst_abs_fuel:
                    worst_abs_fuel = abs_fuel
                    worst_temp = float(point.get("temperature", 0.0))
                    worst_node = node_label

        self._selected_summary_metrics_cache = {
            "seriesCount": total_series,
            "pointCount": total_points,
            "threshold": float(self._fuel_deviation_threshold),
            "rangeCount": len(self._critical_ranges_cache),
            "rangesText": self._format_ranges_short(self._critical_ranges_cache),
            "worstAbsFuel": float(worst_abs_fuel),
            "worstTemp": float(worst_temp),
            "worstNode": worst_node,
        }

    def _rebuild_visible_series_cache(self) -> None:
        """Пересчитывает кэш отображаемых серий без копирования массивов точек."""
        if len(self._series) <= 0:
            self._visible_series_cache = []
            return

        selected: list[ParsedSeries]
        if self._view_mode == 0:
            if self._selected_node_index < 0 or self._selected_node_index >= len(self._series):
                selected = []
            else:
                selected = [self._series[self._selected_node_index]]
        else:
            selected = [item for item in self._series if self._node_visible.get(str(item.node), True)]

        result: list[dict[str, object]] = []
        for index, item in enumerate(selected):
            node_label = str(item.node)
            fallback_color = self._palette[index % len(self._palette)]
            result.append(
                {
                    "node": node_label,
                    "color": self._node_colors.get(node_label, fallback_color),
                    "points": item.points,
                    "path": str(item.path),
                    "count": len(item.points),
                }
            )
        self._visible_series_cache = result
        self._rebuild_critical_ranges_cache()
        self._rebuild_selected_summary_metrics_cache()

    def _rebuild_node_visibility_rows_cache(self) -> None:
        """Пересчитывает кэш строк для панели видимости узлов и легенды."""
        rows: list[dict[str, object]] = []
        for index, item in enumerate(self._series):
            label = str(item.node)
            fallback_color = self._palette[index % len(self._palette)]
            rows.append(
                {
                    "node": label,
                    "visible": bool(self._node_visible.get(label, True)),
                    "color": self._node_colors.get(label, fallback_color),
                    "path": str(item.path),
                    "count": len(item.points),
                }
            )
        self._node_visibility_rows_cache = rows

    @Slot("QVariantList")
    def loadCsvFiles(self, qml_paths: list[Any]) -> None:
        """Загружает выбранные CSV-файлы и подготавливает серии для отображения."""
        if not qml_paths:
            self._status_text = "Файлы не выбраны."
            self._emit_all()
            return

        local_paths: list[Path] = []
        for raw in qml_paths:
            path = self._normalize_qml_url(raw)
            if path is None:
                continue
            local_paths.append(path)

        if len(local_paths) <= 0:
            if self._xlsx_supported:
                self._status_text = "Не удалось прочитать выбранные пути файлов."
            else:
                self._status_text = "Не удалось прочитать выбранные пути файлов. XLSX недоступен: установите openpyxl."
            self._emit_all()
            return

        self._busy = True
        self._status_text = "Загрузка CSV..."
        self._emit_all()
        try:
            self._series = parse_many_csv_files(local_paths)
        except Exception as exc:
            self._series = []
            self._busy = False
            self._status_text = f"Ошибка чтения CSV: {exc}"
            self._emit_all()
            return

        self._selected_node_index = -1
        self._reset_visibility()
        self._busy = False

        if len(self._series) <= 0:
            self._status_text = "В выбранных CSV не найдены данные для построения графиков."
        else:
            points_total = sum(len(item.points) for item in self._series)
            self._status_text = (
                f"Загружено файлов: {len(local_paths)}. Серий: {len(self._series)}. Точек: {points_total}."
            )
        self._emit_all()

    @Slot()
    def clearData(self) -> None:
        """Очищает загруженные серии и возвращает интерфейс в исходное состояние."""
        self._series = []
        self._selected_node_index = -1
        self._node_visible = {}
        self._visible_series_cache = []
        self._node_visibility_rows_cache = []
        self._node_metrics_rows_cache = []
        self._critical_ranges_cache = []
        self._selected_summary_metrics_cache = {}
        self._status_text = self._build_initial_status_text().replace("CSV-файлы не загружены.", "Данные очищены. CSV-файлы не загружены.")
        self._emit_all()

    @Slot(float)
    def setFuelDeviationThreshold(self, threshold: float) -> None:
        """Обновляет порог отклонения топлива и пересчитывает диапазоны для графика и метрик."""
        value = max(0.0, float(threshold))
        if abs(value - self._fuel_deviation_threshold) < 1e-9:
            return
        self._fuel_deviation_threshold = value
        self._rebuild_node_metrics_rows_cache()
        self._rebuild_critical_ranges_cache()
        self._rebuild_selected_summary_metrics_cache()
        self._status_text = f"Порог отклонения обновлён: {value:.2f}%."
        self._emit_all()

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        """Возвращает признак активной загрузки CSV и обработки данных."""
        return bool(self._busy)

    @Property(bool, notify=xlsxSupportChanged)
    def xlsxSupported(self) -> bool:
        """Возвращает признак доступности чтения XLSX в текущем окружении."""
        return bool(self._xlsx_supported)

    @Slot(int)
    def setSelectedNodeIndex(self, index: int) -> None:
        """Переключает активную серию в режиме отображения одного узла."""
        idx = int(index)
        if idx == -1:
            if self._selected_node_index != -1:
                self._selected_node_index = -1
                self._rebuild_visible_series_cache()
                self.dataChanged.emit()
            return
        if idx < 0 or idx >= len(self._series):
            return
        if idx == self._selected_node_index:
            return
        self._selected_node_index = idx
        self._rebuild_visible_series_cache()
        self.dataChanged.emit()

    @Slot(int)
    def setViewMode(self, mode: int) -> None:
        """Переключает режим между отображением одного узла и всех узлов."""
        normalized = 1 if int(mode) == 1 else 0
        if normalized == self._view_mode:
            return
        self._view_mode = normalized
        self._rebuild_visible_series_cache()
        self.dataChanged.emit()

    @Slot(bool)
    def setShowLabels(self, enabled: bool) -> None:
        """Включает и отключает подписи времени на графике."""
        value = bool(enabled)
        if value == self._show_labels:
            return
        self._show_labels = value
        self.dataChanged.emit()

    @Slot(bool)
    def setSwapAxes(self, enabled: bool) -> None:
        """Включает и отключает перестановку осей X и Y."""
        value = bool(enabled)
        if value == self._swap_axes:
            return
        self._swap_axes = value
        self.dataChanged.emit()

    @Slot(str, bool)
    def setNodeVisible(self, node_label: str, visible: bool) -> None:
        """Управляет видимостью выбранной серии в режиме всех узлов."""
        key = str(node_label)
        if key not in self._node_visible:
            return
        value = bool(visible)
        if self._node_visible[key] == value:
            return
        self._node_visible[key] = value
        self._rebuild_node_visibility_rows_cache()
        self._rebuild_visible_series_cache()
        self.dataChanged.emit()

    @Slot(str, str)
    def setNodeColor(self, node_label: str, color_hex: str) -> None:
        """Назначает пользовательский цвет для выбранного узла в режиме всех узлов."""
        key = str(node_label)
        if key not in self._node_visible:
            return
        normalized = self._normalize_color_hex(color_hex)
        if not normalized:
            return
        if self._node_colors.get(key, "") == normalized:
            return
        self._node_colors[key] = normalized
        self._rebuild_node_visibility_rows_cache()
        self._rebuild_visible_series_cache()
        self.dataChanged.emit()

    @Slot(bool)
    def setAllNodesVisible(self, visible: bool) -> None:
        """Массово включает или отключает отображение всех узлов."""
        if len(self._series) <= 0:
            return
        value = bool(visible)
        changed = False
        for item in self._series:
            key = str(item.node)
            if self._node_visible.get(key, True) != value:
                self._node_visible[key] = value
                changed = True
        if not changed:
            return
        self._rebuild_node_visibility_rows_cache()
        self._rebuild_visible_series_cache()
        self.dataChanged.emit()

    @Property(str, notify=statusChanged)
    def statusText(self) -> str:
        """Возвращает текстовый статус загрузки и обработки файлов."""
        return self._status_text

    @Property("QStringList", notify=dataChanged)
    def nodeOptions(self) -> list[str]:
        """Возвращает список доступных серий для селектора узлов."""
        return [str(item.node) for item in self._series]

    @Property(int, notify=dataChanged)
    def selectedNodeIndex(self) -> int:
        """Возвращает индекс текущей серии в селекторе узлов."""
        return int(self._selected_node_index)

    @Property(int, notify=dataChanged)
    def viewMode(self) -> int:
        """Возвращает текущий режим отображения графиков."""
        return int(self._view_mode)

    @Property(bool, notify=dataChanged)
    def showLabels(self) -> bool:
        """Возвращает флаг отображения подписей точек на графике."""
        return bool(self._show_labels)

    @Property(bool, notify=dataChanged)
    def swapAxes(self) -> bool:
        """Возвращает флаг перестановки осей графика."""
        return bool(self._swap_axes)

    @Property("QVariantList", notify=dataChanged)
    def visibleSeries(self) -> list[dict[str, object]]:
        """Возвращает серии, которые должны быть отрисованы в текущем режиме."""
        return self._visible_series_cache

    @Property("QVariantList", notify=dataChanged)
    def nodeVisibilityRows(self) -> list[dict[str, object]]:
        """Возвращает строки управления видимостью и легендой по узлам."""
        return self._node_visibility_rows_cache

    @Property("QVariantList", notify=dataChanged)
    def nodeMetricsRows(self) -> list[dict[str, object]]:
        """Возвращает вычисленные метрики узлов для аналитического блока в UI."""
        return self._node_metrics_rows_cache

    @Property(float, notify=dataChanged)
    def fuelDeviationThreshold(self) -> float:
        """Возвращает текущий порог отклонения топлива для выделения температурных диапазонов."""
        return float(self._fuel_deviation_threshold)

    @Property("QVariantList", notify=dataChanged)
    def criticalTemperatureRanges(self) -> list[dict[str, object]]:
        """Возвращает объединённые диапазоны температур, где отклонение выше порога."""
        return self._critical_ranges_cache

    @Property("QVariantMap", notify=dataChanged)
    def selectedSummaryMetrics(self) -> dict[str, object]:
        """Возвращает сводные метрики по текущему набору отображаемых узлов."""
        return self._selected_summary_metrics_cache
