#!/usr/bin/env python3
"""Dependency-free structural checks for the CodeX Banking resource."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
manifest = (ROOT / 'fxmanifest.lua').read_text(encoding='utf-8')
schema = (ROOT / 'sql/codex_banking.sql').read_text(encoding='utf-8')

required_tables = {
    'codex_bank_accounts', 'codex_bank_account_members', 'codex_bank_transactions',
    'codex_bank_cards', 'codex_bank_loans', 'codex_bank_invoices', 'codex_bank_cheques',
    'codex_bank_daily_usage', 'codex_bank_vaults', 'codex_bank_legacy_sync',
    'codex_bank_credit_scores', 'codex_bank_activity', 'codex_bank_atm_owners',
    'codex_bank_safe_boxes', 'codex_bank_safe_box_members', 'codex_bank_repossessions',
    'codex_bank_settings'
}
created_tables = set(re.findall(r'CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+`([^`]+)`', schema, re.I))
missing_tables = required_tables - created_tables
assert not missing_tables, f'Missing SQL tables: {sorted(missing_tables)}'
assert 'ENGINE=InnoDB' in schema, 'Financial tables must use InnoDB transactions.'
for index in ('uq_codex_bank_account_no', 'idx_codex_bank_owner', 'idx_codex_bank_tx_from', 'idx_codex_bank_card_holder'):
    assert f'`{index}`' in schema, f'Missing database index {index}'
assert "'qb-core'" in manifest and "'oxmysql'" in manifest, 'Required FiveM dependencies are missing.'

# Every local file referenced by the manifest must be present. Glob patterns are
# expanded manually so a typo in the NUI or Lua path is caught before install.
refs = []
for section in ('shared_scripts', 'client_scripts', 'server_scripts', 'files'):
    match = re.search(rf'{section}\s*\{{(.*?)\}}', manifest, re.S)
    if not match:
        continue
    refs.extend(re.findall(r"'([^']+)'", match.group(1)))
for ref in refs:
    if ref.startswith('@'):
        continue
    if '*' in ref:
        parent = ROOT / ref.split('*', 1)[0].rstrip('/')
        assert parent.exists(), f'Missing manifest glob parent: {ref}'
    else:
        assert (ROOT / ref).is_file(), f'Missing manifest file: {ref}'

# Check the security-critical database fields and callback boundary exist.
for column in ('balance', 'owner_cid', 'daily_limit', 'max_balance'):
    assert f'`{column}`' in schema, f'Missing account column {column}'
for event in ('openBranch', 'openATM', 'openAdmin', 'action', 'adminAction'):
    assert f'codex_banking:server:{event}' in ''.join(p.read_text(encoding='utf-8') for p in (ROOT / 'server').glob('*.lua')), f'Missing callback {event}'
assert '`pin_digest` CHAR(64)' in schema, 'Card PIN verifier must store a full SHA-256 digest.'
core = (ROOT / 'server/core.lua').read_text(encoding='utf-8')
assert 'SHA2(CONCAT(' in core, 'PIN verifier must use SHA-256.'
assert ":sub(1, 8)" in core and "'%s-%x-%x-%04x'" in core, 'Transaction references must fit the SQL column limit.'

config = (ROOT / 'config.lua').read_text(encoding='utf-8')
ui = (ROOT / 'html/app.js').read_text(encoding='utf-8')
html = (ROOT / 'html/index.html').read_text(encoding='utf-8')
assert "Config.Locale = 'en'" in config and '<html lang="en">' in html, 'The resource UI must default to English.'
assert not re.search(r'(?m)^\s*sl\s*:', ui), 'The NUI must not contain non-English locale dictionaries.'
assert "action === 'openSavings'" in ui and "var numeric = ['accountId', 'amount', 'loanId'" in ui, 'Card tier strings must not be coerced to numbers.'
assert "DATE_ADD(GREATEST(rent_expires_at, NOW()), INTERVAL" in ''.join((ROOT / 'server/actions.lua').read_text(encoding='utf-8').splitlines()), 'Safe-box renewals must extend from the current expiry.'

print(f'CodeX Banking structural checks passed ({len(required_tables)} tables, {len(refs)} manifest paths).')
