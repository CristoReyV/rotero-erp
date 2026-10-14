import assert from 'node:assert/strict';
import { test } from 'node:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { MemoryRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthGuardView } from './AuthGuardView';
import type { AuthAccessState } from '../services/authAccess';

const renderGuard = (state: AuthAccessState) => renderToStaticMarkup(
    <MemoryRouter initialEntries={['/reports']}>
        <Routes>
            <Route element={<AuthGuardView state={state} onRetry={() => {}} onSignOut={() => {}} />}>
                <Route path="/reports" element={<p>Protected reports</p>} />
            </Route>
            <Route path="/login" element={<p>Login</p>} />
        </Routes>
    </MemoryRouter>,
);

test('authorized access renders the protected /reports outlet', () => {
    assert.ok(renderGuard({ status: 'authorized', userId: 'user-a' }).includes('Protected reports'));
});
test('loading shows a status and never exposes reports', () => {
    const html = renderGuard({ status: 'loading', userId: null });
    assert.ok(html.includes('Verificando acceso')); assert.ok(!html.includes('Protected reports'));
});
for (const status of ['error', 'disabled'] as const) test(`${status} renders recovery instead of a spinner or redirect`, () => {
    const html = renderGuard({ status, userId: null, message: 'Safe message' });
    assert.ok(html.includes('Reintentar')); assert.ok(html.includes('Cerrar sesión'));
    if (status === 'error') assert.ok(html.includes('Recargar página'));
    assert.ok(!html.includes('Verificando acceso')); assert.ok(!html.includes('Protected reports'));
});
test('no session has exactly one replace redirect to an unprotected login route', () => {
    const element = AuthGuardView({ state: { status: 'unauthenticated', userId: null }, onRetry() {}, onSignOut() {} });
    assert.equal(element.type, Navigate); assert.equal(element.props.to, '/login'); assert.equal(element.props.replace, true);
});
