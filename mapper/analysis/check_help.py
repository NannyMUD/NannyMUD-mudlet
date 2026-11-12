#!/usr/bin/env python3
"""Compare map_helper.xml's aliases against the rows in lua/help.lua.

An alias with no help row is invisible; a help row with no alias is a lie. A row's command
word and its `also` words count as documented; a command named only inside some text does not,
since 'maphelp <command>' could not find it.

Run from the client dir:  python analysis/check_help.py
"""
import io
import os
import re
import sys

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
xml = io.open(os.path.join(base, 'map_helper.xml'), encoding='utf-8-sig').read()
help_lua = io.open(os.path.join(base, 'lua', 'help.lua'), encoding='utf-8').read()

aliases = set(re.findall(r'<regex>\^([a-z_]+)', xml))

documented = set(re.findall(r'^\s*\{\s*"(map[a-z]+)', help_lua, re.M))
for block in re.findall(r'also\s*=\s*\{([^}]*)\}', help_lua):
    documented.update(re.findall(r'"([a-z]+)"', block))

missing = sorted(a for a in aliases if a not in documented)
extra = sorted(d for d in documented if d not in aliases)

print('aliases %d, documented words %d' % (len(aliases), len(documented)))
if missing:
    print('ALIAS WITH NO HELP  :', ', '.join(missing))
if extra:
    print('HELP WITH NO ALIAS  :', ', '.join(extra))
if not missing and not extra:
    print('check_help: OK, every alias has a help row and every row has an alias')
sys.exit(1 if (missing or extra) else 0)
