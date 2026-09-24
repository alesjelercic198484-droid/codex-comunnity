#!/usr/bin/env python3
"""
Runs the codex_bodyharvest Lua suite without needing a system Lua interpreter.

    pip install lupa
    python3 tests/run_lua_tests.py            # assertion suite
    python3 tests/run_lua_tests.py simulation # readable timeline simulation

If you already have Lua 5.4 installed you can simply run:

    lua tests/run_tests.lua
    lua tests/simulation.lua
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCE_ROOT = os.path.dirname(HERE)


def main():
    try:
        from lupa import LuaRuntime
    except ImportError:
        print("lupa is not installed. Install it with:  pip install lupa")
        print("Alternatively run:  lua tests/run_tests.lua")
        return 2

    script = "simulation.lua" if len(sys.argv) > 1 and sys.argv[1].startswith("sim") else "run_tests.lua"

    # The suite resolves its paths relative to the resource folder.
    os.chdir(RESOURCE_ROOT)

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().LUPA_HOST = True

    with open(os.path.join("tests", script), encoding="utf-8") as handle:
        source = handle.read()

    try:
        lua.execute(source)
    except Exception as error:  # noqa: BLE001 - we want to surface everything
        print("LUA ERROR:", error)
        return 1

    return int(lua.globals().TEST_FAILURES or 0) > 0


if __name__ == "__main__":
    sys.exit(main())
