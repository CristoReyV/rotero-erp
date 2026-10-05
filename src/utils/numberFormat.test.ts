import assert from 'node:assert/strict';
import { formatAverageHours } from './numberFormat';

assert.equal(formatAverageHours(71.41666666666667), 'Prom. 71.4 h');
assert.equal(formatAverageHours(71), 'Prom. 71 h');
assert.equal(formatAverageHours(0), 'Prom. 0 h');
assert.equal(formatAverageHours(71.96), 'Prom. 72 h');
for (const value of [NaN, Infinity, -Infinity, undefined, null, '', '71.4', -1]) {
    assert.equal(formatAverageHours(value), 'Prom. — h');
}
