// Regenerates condition_cases.json and payload_format_cases.json from the elly-admin sources (the tenant
// evaluator must agree). Run from this directory with the sibling repos checked out:
//   bun run gen_form_fixtures.ts
import { writeFileSync } from 'node:fs'
import { evaluateCondition as adminEval } from '../../../elly-admin/src/app/_utils/condition-evaluator.ts'
import { formatPayloadValue } from '../../../elly-admin/src/app/(baseLayout)/forms/[id]/submissions/_components/formatPayloadValue.ts'
import { evaluateCondition as tenantEval } from '../../../elly-tenant/src/lib/form/condition-evaluator.ts'

const currents: unknown[] = [undefined, null, '', 'a', 'A', '18', '18.0', ' 18 ', '17', '19', 18, 18.5, 0, -1, true, false, 'true', ['a', 'b'], [], [18], 'abc', '1e2', '0x10', '-5', '.5']
const expecteds: unknown[] = ['', 'a', '18', 18, 18.0, '18.5', true, 'true', 'false', 'a,b', 0, '0', '-1', 'abc', null]
const ops = ['EQUALS', 'NOT_EQUALS', 'GT', 'LT', 'UNKNOWN']
const conditions: unknown[] = []
for (const c of currents) for (const e of expecteds) for (const op of ops) {
  const a = adminEval(op as never, c, e)
  if (a !== tenantEval(op as never, c, e)) throw new Error(`admin/tenant differ: ${op} ${c} ${e}`)
  conditions.push([op, c === undefined ? '__undefined__' : c, e, a])
}
writeFileSync('condition_cases.json', JSON.stringify(conditions))

const fields = {
  options: { id: 'f', type: 'select', label: 'F', required: false, options: [{ label: 'Bir', value: '1' }, { label: 'Elma', value: 'a' }] },
  plain: { id: 'g', type: 'text', label: 'G', required: false },
  none: undefined,
}
const values: unknown[] = [null, '', [], ['a', '1'], ['a', 'zz'], [1], 'a', 'zz', 1, '1', true, false, 5, 5.5, 0, 'metin', ['x', 'y'], [true]]
const formats: unknown[] = []
for (const v of values) for (const [name, f] of Object.entries(fields)) formats.push([v, name, formatPayloadValue(v, f as never)])
writeFileSync('payload_format_cases.json', JSON.stringify({ fields, cases: formats }))
