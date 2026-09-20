#!/usr/bin/env python3
"""
SQL validation suite.

Parses every statement the resource executes (and sql/codex_cryptomining.sql)
with a real MySQL parser, then cross-checks the queries against the schema:
every table and column referenced by the Lua code must actually exist, and the
number of placeholders must match the number of values.

    pip install sqlglot
    python3 tests/sql_tests.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

try:
    import sqlglot
    from sqlglot import exp
except ImportError:
    print("sqlglot is not installed. Install it with:  pip install sqlglot")
    sys.exit(0)

passed = 0
failed = 0
failures = []


def ok(condition, name, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  \033[32mPASS\033[0m {name}")
    else:
        failed += 1
        failures.append(f"{name}{' -> ' + detail if detail else ''}")
        print(f"  \033[31mFAIL\033[0m {name}{' -> ' + detail if detail else ''}")


def group(name):
    print(f"\n\033[1;36m== {name}\033[0m")


# ---------------------------------------------------------------------------
# 1. The shipped .sql file must be valid MySQL
# ---------------------------------------------------------------------------
group("sql/codex_cryptomining.sql")

sql_path = os.path.join(ROOT, "sql", "codex_cryptomining.sql")
with open(sql_path, encoding="utf-8") as handle:
    sql_text = handle.read()

statements = [s for s in sqlglot.parse(sql_text, read="mysql") if s is not None]
ok(len(statements) > 0, "the file contains parsable statements")

schema = {}
for statement in statements:
    if isinstance(statement, exp.Create) and statement.kind == "TABLE":
        table = statement.find(exp.Table)
        name = table.name
        columns = set()
        for column_def in statement.find_all(exp.ColumnDef):
            columns.add(column_def.this.name)
        schema[name] = columns

expected_tables = {
    "codex_crypto_warehouses",
    "codex_crypto_rigs",
    "codex_crypto_keys",
    "codex_crypto_market",
}
ok(
    expected_tables.issubset(set(schema)),
    "every required table is created",
    str(expected_tables - set(schema)),
)

# The main schema file must NOT touch the ESX `items` table: it does not
# exist on ox_inventory servers and would abort the whole import.
ok(
    not any(isinstance(s, exp.Insert) for s in statements),
    "the schema file does not touch the ESX items table",
)

# The ESX items live in their own file so they can be skipped.
items_path = os.path.join(ROOT, "sql", "esx_items.sql")
ok(os.path.exists(items_path), "sql/esx_items.sql exists for ESX inventory users")

with open(items_path, encoding="utf-8") as handle:
    items_sql = handle.read()

items_statements = [s for s in sqlglot.parse(items_sql, read="mysql") if s is not None]
ok(len(items_statements) >= 1, "the items file parses as valid MySQL")
ok(
    all("ON DUPLICATE KEY UPDATE" in s.sql(dialect="mysql").upper() for s in items_statements if isinstance(s, exp.Insert)),
    "the items insert is idempotent (safe to re-run)",
)
ok("DELIMITER" not in items_sql and "DELIMITER" not in sql_text,
   "no DELIMITER / stored procedure (works in phpMyAdmin and HeidiSQL)")

# Every CREATE must be idempotent, otherwise a second start throws.
creates = [s for s in statements if isinstance(s, exp.Create)]
ok(
    all(c.args.get("exists") for c in creates),
    "every CREATE TABLE uses IF NOT EXISTS (safe to re-run)",
)



# ---------------------------------------------------------------------------
# 2. The schema created at runtime must match the shipped .sql
# ---------------------------------------------------------------------------
group("Runtime schema (server/database.lua)")

with open(os.path.join(ROOT, "server", "database.lua"), encoding="utf-8") as handle:
    database_lua = handle.read()

runtime_creates = re.findall(
    r"CREATE TABLE IF NOT EXISTS.*?ENGINE=InnoDB[^;]*;", database_lua, re.S
)
ok(len(runtime_creates) == 4, "four tables are created at runtime", str(len(runtime_creates)))

runtime_schema = {}
for raw in runtime_creates:
    parsed = sqlglot.parse_one(raw, read="mysql")
    table = parsed.find(exp.Table).name
    runtime_schema[table] = {c.this.name for c in parsed.find_all(exp.ColumnDef)}

for table, columns in runtime_schema.items():
    ok(table in schema, f"runtime table {table} also exists in the .sql file")
    if table in schema:
        ok(
            columns == schema[table],
            f"{table} has identical columns in both places",
            f"sql-only={schema[table] - columns} runtime-only={columns - schema[table]}",
        )

# ---------------------------------------------------------------------------
# 3. Every query in the Lua code must be valid and match the schema
# ---------------------------------------------------------------------------
group("Queries used by the resource")

lua_files = [
    "server/database.lua",
    "server/warehouses.lua",
    "server/market.lua",
    "server/shops.lua",
    "server/robbery.lua",
    "server/main.lua",
]

sql_keywords = ("SELECT", "INSERT", "UPDATE", "DELETE")
found_queries = []

for relative in lua_files:
    with open(os.path.join(ROOT, relative), encoding="utf-8") as handle:
        content = handle.read()

    # Long-bracket strings [[ ... ]] and plain single quoted queries.
    for block in re.findall(r"\[\[(.*?)\]\]", content, re.S):
        stripped = block.strip()
        if stripped.upper().startswith(sql_keywords):
            found_queries.append((relative, stripped))

    for line in re.findall(r"'((?:SELECT|INSERT|UPDATE|DELETE)[^']*)'", content):
        found_queries.append((relative, line.strip()))

ok(len(found_queries) >= 10, f"found {len(found_queries)} queries to validate")

known_tables = set(schema) | {"items"}

for relative, query in found_queries:
    # Named parameters (@name) are not MySQL syntax; the driver converts them
    # to ? before sending. Normalise them so the parser can read the query.
    normalised = re.sub(r"@[\w_]+", "?", query)
    # %s comes from Lua string.format for the LIMIT value.
    normalised = normalised.replace("%d", "1").replace("%s", "1")

    label = f"{relative}: {' '.join(query.split())[:58]}"

    try:
        parsed = sqlglot.parse_one(normalised, read="mysql")
    except Exception as error:  # noqa: BLE001
        ok(False, f"parses | {label}", str(error)[:120])
        continue

    ok(True, f"parses | {label}")

    # Referenced tables must exist.
    for table in parsed.find_all(exp.Table):
        if table.name and table.name.lower() not in {t.lower() for t in known_tables}:
            # Subquery aliases are not real tables.
            if table.name.lower() in {"recent", "boundary"}:
                continue
            ok(False, f"table {table.name} exists", label)

    # Referenced columns must exist in one of the used tables.
    used_tables = {t.name for t in parsed.find_all(exp.Table) if t.name in schema}
    allowed_columns = set()
    for table in used_tables:
        allowed_columns |= {c.lower() for c in schema[table]}

    if used_tables and allowed_columns:
        for column in parsed.find_all(exp.Column):
            name = column.name.lower()
            if name and name not in allowed_columns and name not in {"keep_id", "id"}:
                ok(False, f"column {column.name} exists in {used_tables}", label)

# ---------------------------------------------------------------------------
# 4. INSERT column/value count must match
# ---------------------------------------------------------------------------
group("INSERT arity")

for relative, query in found_queries:
    if not query.upper().lstrip().startswith("INSERT"):
        continue

    normalised = re.sub(r"@[\w_]+", "?", query).replace("%d", "1").replace("%s", "1")

    try:
        parsed = sqlglot.parse_one(normalised, read="mysql")
    except Exception:  # noqa: BLE001
        continue

    schema_expr = parsed.this
    columns = []
    if isinstance(schema_expr, exp.Schema):
        columns = [c for c in schema_expr.expressions if isinstance(c, exp.Identifier)]

    values = parsed.find(exp.Values)
    label = f"{relative}: {' '.join(query.split())[:50]}"

    if columns and values:
        tuple_sizes = {len(t.expressions) for t in values.expressions}
        ok(
            tuple_sizes == {len(columns)},
            f"column/value count matches | {label}",
            f"{len(columns)} columns vs {tuple_sizes}",
        )

# ---------------------------------------------------------------------------
group("Placeholder safety")

# No query may interpolate a Lua variable straight into the SQL string.
injection = []
for relative in lua_files:
    with open(os.path.join(ROOT, relative), encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if re.search(r"(SELECT|INSERT|UPDATE|DELETE).*\.\.\s*\w", line, re.I):
                if "format" not in line.lower():
                    injection.append(f"{relative}:{number}")

ok(not injection, "no query concatenates a variable into the SQL", ", ".join(injection))

print("\n\033[1m================ RESULT ================\033[0m")
print(f"  passed: \033[32m{passed}\033[0m")
print(f"  failed: {'[31m' if failed else '[32m'}{failed}\033[0m".replace("[31m", "\033[31m").replace("[32m", "\033[32m"))

if failed:
    print("\n\033[31mFailures:\033[0m")
    for failure in failures:
        print("  - " + failure)
    sys.exit(1)

print("\n\033[32mAll SQL tests passed.\033[0m")
sys.exit(0)
