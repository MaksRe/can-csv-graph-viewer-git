from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ParsedSeries:
    """Хранит одну серию графика, подготовленную из CSV-файла."""

    node: str
    path: str
    points: list[dict[str, object]]


def _parse_number(raw_value: str) -> float | None:
    """Преобразует текст в число с поддержкой запятой в дробной части."""
    text = str(raw_value).strip().replace(" ", "")
    if not text:
        return None
    normalized = text.replace(",", ".")
    try:
        return float(normalized)
    except (TypeError, ValueError):
        return None


def _decode_signed(raw_value: int, bits: int) -> int:
    """Декодирует знаковое число заданной разрядности из беззнакового представления."""
    width = max(1, int(bits))
    mask = (1 << width) - 1
    sign_bit = 1 << (width - 1)
    value = int(raw_value) & mask
    if value & sign_bit:
        return value - (1 << width)
    return value


def _normalize_legacy_temperature(temperature_c: float) -> float:
    """Исправляет старый формат температуры из CSV, если значение сохранено как unsigned int16."""
    value = float(temperature_c)
    if value > 3276.7:
        raw_u16 = int(round(value * 10.0)) & 0xFFFF
        signed_value = _decode_signed(raw_u16, 16)
        return float(signed_value) / 10.0
    return value


def _is_header_row(row: list[str]) -> bool:
    """Определяет строку заголовка таблицы по наличию времени, температуры и топлива."""
    if len(row) == 0:
        return False
    joined = ";".join(str(value).strip() for value in row).casefold()
    has_time = ("время" in joined) or ("time" in joined)
    has_temp = ("температ" in joined) or ("temp" in joined)
    has_fuel = ("топлив" in joined) or ("fuel" in joined)
    return has_time and has_temp and has_fuel


def _resolve_indexes(header: list[str]) -> dict[str, int]:
    """Находит индексы колонок времени, температуры и топлива в строке заголовка."""
    idx_time = -1
    idx_temp = -1
    idx_fuel = -1

    for index, raw_name in enumerate(header):
        name = str(raw_name).strip().casefold()
        if not name:
            continue
        if idx_time < 0 and (("время" in name) or ("time" in name)):
            idx_time = index
            continue
        if idx_temp < 0 and (("температ" in name) or ("temp" in name)):
            idx_temp = index
            continue
        if idx_fuel < 0 and (("топлив" in name) or ("fuel" in name)):
            idx_fuel = index
            continue

    if idx_temp < 0 or idx_fuel < 0:
        if len(header) >= 4:
            if idx_time < 0:
                idx_time = 0
            idx_temp = 2 if idx_temp < 0 else idx_temp
            idx_fuel = 3 if idx_fuel < 0 else idx_fuel
        elif len(header) >= 3:
            idx_temp = 1 if idx_temp < 0 else idx_temp
            idx_fuel = 2 if idx_fuel < 0 else idx_fuel

    return {"time": idx_time, "temperature": idx_temp, "fuel": idx_fuel}


def _extract_node_sa(text: str) -> str | None:
    """Извлекает обозначение узла вида 0xNN из произвольной строки."""
    match = re.search(r"0x([0-9a-fA-F]{1,2})", str(text))
    if not match:
        return None
    return f"0x{int(match.group(1), 16):02x}"


def _detect_delimiter(file_path: Path) -> str:
    """Определяет разделитель CSV и возвращает ';' либо ','."""
    sample = file_path.read_text(encoding="utf-8-sig", errors="ignore")[:8192]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=";,")
        if dialect.delimiter in (";", ","):
            return dialect.delimiter
    except csv.Error:
        pass
    return ";" if sample.count(";") >= sample.count(",") else ","


def _read_rows(file_path: Path) -> list[list[str]]:
    """Читает CSV-файл и возвращает массив строк с выбранным разделителем."""
    delimiter = _detect_delimiter(file_path)
    with file_path.open("r", encoding="utf-8-sig", newline="") as file:
        return [list(map(str, row)) for row in csv.reader(file, delimiter=delimiter)]


def _cell_to_text(cell_value: object) -> str:
    """Преобразует значение ячейки XLSX в строку для унифицированного парсинга."""
    if cell_value is None:
        return ""
    return str(cell_value)


def _read_rows_xlsx(file_path: Path) -> list[list[str]]:
    """Читает XLSX-файл и возвращает его как список строковых строк таблицы."""
    try:
        import openpyxl
    except Exception as exc:
        raise RuntimeError("Для чтения XLSX установите пакет openpyxl.") from exc

    workbook = openpyxl.load_workbook(file_path, read_only=True, data_only=True)
    try:
        worksheet = workbook.worksheets[0]
        rows: list[list[str]] = []
        for row in worksheet.iter_rows(values_only=True):
            rows.append([_cell_to_text(value) for value in row])
        return rows
    finally:
        workbook.close()


def _read_rows_by_extension(file_path: Path) -> list[list[str]]:
    """Выбирает чтение CSV или XLSX в зависимости от расширения файла."""
    suffix = file_path.suffix.casefold()
    if suffix == ".csv":
        return _read_rows(file_path)
    if suffix == ".xlsx":
        return _read_rows_xlsx(file_path)
    return []


def _parse_points_from_columns(rows: list[list[str]], data_start: int, idx_time: int, idx_temp: int, idx_fuel: int) -> list[dict[str, object]]:
    """Формирует список точек графика из заданных колонок таблицы."""
    points: list[dict[str, object]] = []
    for row in rows[data_start:]:
        if max(idx_temp, idx_fuel) >= len(row):
            continue
        temperature_value = _parse_number(row[idx_temp])
        fuel_value = _parse_number(row[idx_fuel])
        if temperature_value is None or fuel_value is None:
            continue

        temperature_value = _normalize_legacy_temperature(temperature_value)
        if 0 <= idx_time < len(row):
            time_text = str(row[idx_time]).strip()
        else:
            time_text = str(len(points) + 1)

        points.append(
            {
                "fuel": float(fuel_value),
                "temperature": float(temperature_value),
                "time": time_text,
            }
        )
    return points


def _parse_per_node_csv(file_path: Path, rows: list[list[str]]) -> list[ParsedSeries]:
    """Разбирает CSV одного узла и возвращает единственную серию точек."""
    header_index = -1
    header: list[str] = []
    for index, row in enumerate(rows):
        normalized = [str(value).strip() for value in row]
        if _is_header_row(normalized):
            header_index = index
            header = normalized
            break

    if header_index < 0:
        return []

    indexes = _resolve_indexes(header)
    idx_temp = int(indexes.get("temperature", -1))
    idx_fuel = int(indexes.get("fuel", -1))
    idx_time = int(indexes.get("time", 0))
    if idx_temp < 0 or idx_fuel < 0:
        return []

    points = _parse_points_from_columns(rows, header_index + 1, idx_time, idx_temp, idx_fuel)
    if len(points) <= 0:
        return []

    node_label = _extract_node_sa(file_path.stem) or f"csv:{file_path.stem}"
    return [ParsedSeries(node=node_label, path=str(file_path), points=points)]


def _parse_all_nodes_csv(file_path: Path, rows: list[list[str]]) -> list[ParsedSeries]:
    """Разбирает all_nodes CSV с несколькими узлами и возвращает набор серий по узлам."""
    if len(rows) < 2:
        return []

    node_row_index = -1
    header_row_index = -1

    for index, row in enumerate(rows[:8]):
        joined = ";".join(str(cell).strip() for cell in row).casefold()
        if node_row_index < 0 and (("узел" in joined) or ("node" in joined)):
            node_row_index = index
        if header_row_index < 0 and (("период" in joined) or ("period" in joined)) and (("температ" in joined) or ("temp" in joined)):
            header_row_index = index

    if node_row_index < 0 or header_row_index < 0:
        return []

    node_row = rows[node_row_index]
    header_row = rows[header_row_index]
    node_starts: list[tuple[int, str]] = []
    for index, cell in enumerate(node_row):
        node_label = _extract_node_sa(cell)
        if node_label is None:
            continue
        node_starts.append((index, node_label))

    if len(node_starts) <= 0:
        return []

    result: list[ParsedSeries] = []
    for idx, (start, node_label) in enumerate(node_starts):
        end = node_starts[idx + 1][0] - 1 if idx + 1 < len(node_starts) else len(header_row) - 1
        if end < start:
            continue

        local_headers = [str(value).strip() for value in header_row[start : end + 1]]
        local_indexes = _resolve_indexes(local_headers)
        local_temp = int(local_indexes.get("temperature", -1))
        local_fuel = int(local_indexes.get("fuel", -1))
        local_time = int(local_indexes.get("time", -1))
        if local_temp < 0 or local_fuel < 0:
            continue

        idx_temp = start + local_temp
        idx_fuel = start + local_fuel
        idx_time = 0 if local_time < 0 else start + local_time

        points = _parse_points_from_columns(rows, header_row_index + 1, idx_time, idx_temp, idx_fuel)
        if len(points) <= 0:
            continue

        result.append(ParsedSeries(node=node_label, path=str(file_path), points=points))

    return result


def _is_all_nodes_layout(rows: list[list[str]]) -> bool:
    """Определяет, является ли CSV групповым форматом all_nodes."""
    head = rows[:5]
    for row in head:
        joined = ";".join(str(cell).strip() for cell in row).casefold()
        if (("узел" in joined) or ("node" in joined)) and (("период" in joined) or ("period" in joined) or len(head) > 1):
            return True
    return False


def parse_csv_file(file_path: Path) -> list[ParsedSeries]:
    """Читает CSV/XLSX и возвращает одну или несколько серий графиков."""
    rows = _read_rows_by_extension(file_path)
    if len(rows) <= 0:
        return []

    if _is_all_nodes_layout(rows):
        grouped = _parse_all_nodes_csv(file_path, rows)
        if len(grouped) > 0:
            return grouped

    return _parse_per_node_csv(file_path, rows)


def parse_many_csv_files(paths: list[Path]) -> list[ParsedSeries]:
    """Разбирает список CSV/XLSX-файлов и объединяет все найденные серии."""
    parsed: list[ParsedSeries] = []
    for path in paths:
        if path.suffix.casefold() not in (".csv", ".xlsx"):
            continue
        parsed.extend(parse_csv_file(path))

    if len(parsed) <= 0:
        return []

    # Цель блока в устранении конфликтов имен узлов при загрузке нескольких файлов.
    # Он добавляет имя файла к label только когда label уже встречался ранее.
    label_counts: dict[str, int] = {}
    for item in parsed:
        key = str(item.node)
        label_counts[key] = label_counts.get(key, 0) + 1

    normalized: list[ParsedSeries] = []
    label_seen: dict[str, int] = {}
    for item in parsed:
        base_label = str(item.node)
        if label_counts.get(base_label, 0) <= 1:
            normalized.append(item)
            continue

        sequence = label_seen.get(base_label, 0) + 1
        label_seen[base_label] = sequence
        file_stem = Path(item.path).stem
        unique_label = f"{base_label} [{file_stem} #{sequence}]"
        normalized.append(ParsedSeries(node=unique_label, path=item.path, points=list(item.points)))

    return normalized
