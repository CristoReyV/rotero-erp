import type { CsvField, ImportEntity, ImportValidationItem } from '@/types/dataOperations';
import { IMPORT_FIELDS } from '@/types/dataOperations';

export interface ParsedCsv { headers: string[]; rows: string[][]; delimiter: ',' | ';' }
const FORMULA_PREFIX = /^\s*[=+\-@]/;

function parseWithDelimiter(input: string, delimiter: ',' | ';'): string[][] {
    const rows: string[][] = []; let row: string[] = []; let cell = ''; let quoted = false;
    for (let index = 0; index < input.length; index += 1) {
        const char = input[index];
        if (char === '"') {
            if (quoted && input[index + 1] === '"') { cell += '"'; index += 1; } else quoted = !quoted;
        } else if (char === delimiter && !quoted) { row.push(cell); cell = ''; }
        else if ((char === '\n' || char === '\r') && !quoted) {
            if (char === '\r' && input[index + 1] === '\n') index += 1;
            row.push(cell); if (row.some((value) => value.trim() !== '')) rows.push(row); row = []; cell = '';
        } else cell += char;
    }
    if (quoted) throw new Error('csv_unclosed_quote');
    row.push(cell); if (row.some((value) => value.trim() !== '')) rows.push(row);
    return rows;
}

function delimiterScore(input: string, delimiter: ',' | ';'): number {
    try { const rows = parseWithDelimiter(input, delimiter).slice(0, 10); return rows.reduce((score, row) => score + Math.max(row.length - 1, 0), 0); }
    catch { return -1; }
}

export function parseCsv(content: string): ParsedCsv {
    const clean = content.replace(/^\uFEFF/, '');
    const delimiter: ',' | ';' = delimiterScore(clean, ';') > delimiterScore(clean, ',') ? ';' : ',';
    const matrix = parseWithDelimiter(clean, delimiter);
    if (!matrix.length) throw new Error('csv_empty');
    const headers = matrix[0].map((value) => value.trim());
    if (headers.some((value) => !value) || new Set(headers.map(normalizeHeader)).size !== headers.length) throw new Error('csv_invalid_headers');
    return { headers, rows: matrix.slice(1), delimiter };
}

export function normalizeHeader(value: string): string {
    return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
}

export function suggestMapping(headers: string[], fields: CsvField[]): Record<string, string> {
    const normalized = new Map(headers.map((header) => [normalizeHeader(header), header])); const mapping: Record<string, string> = {};
    fields.forEach((field) => {
        const names = [field.key, field.label, ...(field.aliases ?? [])].map(normalizeHeader);
        const match = names.map((name) => normalized.get(name)).find(Boolean); if (match) mapping[field.key] = match;
    });
    return mapping;
}

export function mapCsvRows(parsed: ParsedCsv, mapping: Record<string, string>): Array<Record<string, string | number>> {
    const indexes = new Map(parsed.headers.map((header, index) => [header, index]));
    return parsed.rows.map((row, rowIndex) => {
        const result: Record<string, string | number> = { row_number: rowIndex + 2 };
        Object.entries(mapping).forEach(([target, source]) => { const index = indexes.get(source); if (index !== undefined) result[target] = (row[index] ?? '').trim(); });
        return result;
    });
}

function safeCell(value: unknown): string {
    let text = value == null ? '' : typeof value === 'object' ? JSON.stringify(value) : String(value);
    if (FORMULA_PREFIX.test(text)) text = `'${text}`;
    return `"${text.replace(/"/g, '""')}"`;
}

export function serializeCsv(rows: Array<Record<string, unknown>>, headers?: string[]): string {
    const columns = headers ?? Object.keys(rows[0] ?? {}); const lines = [columns.map(safeCell).join(',')];
    rows.forEach((row) => lines.push(columns.map((header) => safeCell(row[header])).join(',')));
    return `\uFEFF${lines.join('\r\n')}`;
}

export function downloadCsvContent(content: string, filename: string): void {
    const blob = new Blob([content], { type: 'text/csv;charset=utf-8' }); const url = URL.createObjectURL(blob);
    const link = document.createElement('a'); link.href = url; link.download = filename; document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
}

export function templateCsv(entity: ImportEntity): string {
    const fields = IMPORT_FIELDS[entity]; const example = Object.fromEntries(fields.map((field) => [field.key, field.example ?? '']));
    return serializeCsv([example], fields.map((field) => field.key));
}

export function validationErrorsCsv(items: ImportValidationItem[]): string {
    return serializeCsv(items.filter((item) => item.errors.length).map((item) => ({
        row_number: item.row_number, external_key: item.external_key ?? '', action: item.action, status: item.status ?? 'error',
        error_codes: item.errors.map((issue) => issue.code).join('|'), message: item.errors.map((issue) => issue.message).join(' | '),
    })), ['row_number', 'external_key', 'action', 'status', 'error_codes', 'message']);
}

export async function sha256Hex(content: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(content));
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}
