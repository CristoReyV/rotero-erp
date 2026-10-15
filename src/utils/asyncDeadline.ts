export class RequestTimeoutError extends Error {
    constructor() { super('request_timeout'); }
}

export class RequestCancelledError extends Error {
    constructor() { super('request_cancelled'); }
}

/** Bound an individual request; cancellation never turns into a successful result. */
export async function withDeadline<T>(
    task: (signal: AbortSignal) => PromiseLike<T>,
    timeoutMs: number,
    parent?: AbortSignal,
): Promise<T> {
    if (parent?.aborted) throw new RequestCancelledError();
    const abort = new AbortController();
    let timer: ReturnType<typeof setTimeout>;
    let cancel: () => void;
    const deadline = new Promise<never>((_, reject) => {
        timer = setTimeout(() => { reject(new RequestTimeoutError()); abort.abort(); }, timeoutMs);
        cancel = () => { reject(new RequestCancelledError()); abort.abort(); };
        parent?.addEventListener('abort', cancel, { once: true });
    });
    try {
        return await Promise.race([
            Promise.resolve().then(() => {
                if (abort.signal.aborted) throw new RequestCancelledError();
                return task(abort.signal);
            }),
            deadline,
        ]);
    } finally {
        clearTimeout(timer!);
        parent?.removeEventListener('abort', cancel!);
    }
}
