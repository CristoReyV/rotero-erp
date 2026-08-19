import assert from 'node:assert/strict';
import { calculateMargin } from './commercialCalculations';

assert.deepEqual(calculateMargin(800, 1000), { amount: 200, percentage: 20 });
assert.deepEqual(calculateMargin(1200, 1000), { amount: -200, percentage: -20 });
assert.deepEqual(calculateMargin(0, 0), { amount: 0, percentage: null });
assert.deepEqual(calculateMargin(Number.NaN, 500), { amount: 500, percentage: 100 });
