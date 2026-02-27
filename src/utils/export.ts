export function downloadCSV<T extends Record<string, any>>(data: T[], filename: string) {
    if (!data || data.length === 0) return;

    const headers = Object.keys(data[0]);

    const csvContent = [
        headers.join(','),
        ...data.map(row =>
            headers.map(header => {
                const val = row[header];
                const cleanVal = val === null || val === undefined ? '' : typeof val === 'object' ? JSON.stringify(val) : String(val);
                return `"${cleanVal.replace(/"/g, '""')}"`;
            }).join(',')
        )
    ].join('\n');

    // Add BOM for Excel UTF-8 compatibility
    const bom = new Uint8Array([0xEF, 0xBB, 0xBF]);
    const blob = new Blob([bom, csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);

    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `${filename}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}
