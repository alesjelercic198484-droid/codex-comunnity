#!/usr/bin/env python3
"""
Runs the Lua test suite without needing a system Lua interpreter.

    pip install lupa
    python3 tests/run_lua_tests.py

If you already have Lua 5.4 installed you can simply run:

    lua tests/run_tests.lua
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

    # The suite resolves its paths relative to the resource folder.
    os.chdir(RESOURCE_ROOT)

    lua = LuaRuntime(unpack_returned_tuples=True)

    with open(os.path.join("tests", "run_tests.lua"), encoding="utf-8") as handle:
        source = handle.read()

    try:
        lua.execute(source)
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001 - we want to surface everything
        message = str(error)

        # os.exit(0) from Lua surfaces as a normal shutdown in some builds.
        if "exit" in message.lower() and "0" in message:
            return 0

        print("LUA ERROR:", message)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
