import type { DocumentUploadContract } from '@/types/documents';

const EXTENSIONS_BY_MIME: Record<string, readonly string[]> = {
    'application/pdf': ['pdf'], 'application/xml': ['xml'], 'text/xml': ['xml'],
    'text/plain': ['txt', 'csv'], 'text/html': ['html', 'htm'], 'image/png': ['png'],
    'image/jpeg': ['jpg', 'jpeg'], 'image/webp': ['webp'],
};

export function formatFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
}

export function validateDocumentFile(file: Pick<File, 'name' | 'type' | 'size'>, contract: DocumentUploadContract): string | null {
    const mime = file.type.toLowerCase();
    const extension = file.name.split('.').pop()?.toLowerCase() ?? '';
    if (!contract.allowed_mime_types.includes(mime) || !EXTENSIONS_BY_MIME[mime]?.includes(extension)) {
        return 'El tipo o la extensión del archivo no están permitidos.';
    }
    if (file.size <= 0) return 'El archivo está vacío.';
    if (file.size > contract.max_file_size) return `El archivo excede el límite de ${formatFileSize(contract.max_file_size)}.`;
    return null;
}

export async function registerWithCompensation<T>(register: () => Promise<T>, remove: () => Promise<void>): Promise<T> {
    try { return await register(); }
    catch {
        try { await remove(); } catch { /* keep the user-facing error sanitized */ }
        throw new Error('No fue posible registrar el archivo. Se intentó revertir la carga de Storage.');
    }
}
