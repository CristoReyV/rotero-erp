import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
    resolveTrackingCredential,
    TRACKING_CREDENTIAL_ERROR,
} from "../../../supabase/functions/_shared/tracking-credential.ts";

const validNamed = `sb_secret_${"a".repeat(32)}`;
const unrelatedServiceRole = `eyJ${"b".repeat(64)}`;

function reader(values: Record<string, string | undefined>) {
    return (name: string) => values[name];
}

function assertFailsClosed(values: Record<string, string | undefined>) {
    assert.throws(
        () => resolveTrackingCredential(reader(values)),
        (error: unknown) =>
            error instanceof Error && error.message === TRACKING_CREDENTIAL_ERROR,
    );
}

test("CASE A: named trackingedge valid passes", () => {
    const result = resolveTrackingCredential(reader({
        SUPABASE_SECRET_KEYS: JSON.stringify({ trackingedge: validNamed }),
    }));
    assert.equal(result.source, "trackingedge");
    assert.equal(result.credential, validNamed);
});

test("CASE B: removed singular compatibility key fails closed", () => {
    assertFailsClosed({ SUPABASE_SECRET_KEY: validNamed });
});

test("CASE C: no dedicated credential fails closed", () => {
    assertFailsClosed({});
});

test("CASE D: service_role alone is ignored and fails closed", () => {
    assertFailsClosed({ SUPABASE_SERVICE_ROLE_KEY: unrelatedServiceRole });
});

test("CASE E: malformed dedicated credentials fail closed", () => {
    for (const malformed of [
        "",
        "   ",
        "not-a-secret",
        "sb_publishable_public",
        "sb_secret_short",
        `sb_secret_${"x".repeat(10)} whitespace`,
    ]) {
        assertFailsClosed({
            SUPABASE_SECRET_KEYS: JSON.stringify({ trackingedge: malformed }),
        });
    }
    assertFailsClosed({ SUPABASE_SECRET_KEYS: "not-json" });
});

test("CASE F: named dedicated credential wins with unrelated service_role present", () => {
    const result = resolveTrackingCredential(reader({
        SUPABASE_SECRET_KEYS: JSON.stringify({ trackingedge: validNamed }),
        SUPABASE_SERVICE_ROLE_KEY: unrelatedServiceRole,
    }));
    assert.equal(result.source, "trackingedge");
    assert.equal(result.credential, validNamed);
});

const repositoryRoot = fileURLToPath(new URL("../../../", import.meta.url));
const runtimeFiles = [
    "supabase/functions/_shared/supabase-admin.ts",
    "supabase/functions/_shared/tracking-credential.ts",
    "supabase/functions/driver-view/index.ts",
    "supabase/functions/track-public/index.ts",
    "supabase/functions/track-driver/index.ts",
];

test("static gate: Tracking runtime cannot reintroduce legacy credential sources", () => {
    const forbidden = [
        /SUPABASE_SERVICE_ROLE_KEY/,
        /SUPABASE_SECRET_KEY(?!S)/,
    ];
    for (const relativePath of runtimeFiles) {
        const source = readFileSync(repositoryRoot + relativePath, "utf8");
        for (const pattern of forbidden) {
            assert.equal(
                pattern.test(source),
                false,
                `${relativePath} contains forbidden credential source`,
            );
        }
    }
});

const edgeContracts = [
    {
        name: "driver-view",
        path: "supabase/functions/driver-view/index.ts",
        capabilityMarkers: [
            'status === "success" ? 200',
            'status === "revoked" ? 403',
            'status === "expired" ? 403',
            ": 404",
        ],
    },
    {
        name: "track-public",
        path: "supabase/functions/track-public/index.ts",
        capabilityMarkers: [
            "success: 200",
            "soft_expired: 200",
            "not_found: 404",
            "revoked: 403",
            "hard_expired: 410",
        ],
    },
    {
        name: "track-driver",
        path: "supabase/functions/track-driver/index.ts",
        capabilityMarkers: [
            'driverToken.length < 30',
            'errorResponse(404, "not_found"',
            'data as { http?: number }',
        ],
    },
];

for (const contract of edgeContracts) {
    test(`${contract.name}: credential success/failure and capability outcomes remain wired`, () => {
        const source = readFileSync(repositoryRoot + contract.path, "utf8");
        assert.match(source, /createSupabaseAdminClient\(\)/);
        assert.match(source, /errorResponse\(503, "tracking_service_unavailable"/);
        assert.match(source, /isTrackingCredentialError/);
        assert.doesNotMatch(source, /error\.message/);
        for (const marker of contract.capabilityMarkers) {
            assert.equal(source.includes(marker), true, `${contract.name}: ${marker}`);
        }
        assert.doesNotMatch(source, /Authorization|console\.(?:log|info|warn|error)\([^\n]*(?:token|headers|credential)[^\n]*,/i);
    });
}

test("Edge config keeps capability authentication with verify_jwt=false", () => {
    const config = readFileSync(repositoryRoot + "supabase/config.toml", "utf8");
    for (const functionName of ["driver-view", "track-public", "track-driver"]) {
        const section = new RegExp(
            `\\[functions\\.${functionName}\\]\\s+verify_jwt\\s*=\\s*false`,
        );
        assert.match(config, section);
    }
});
