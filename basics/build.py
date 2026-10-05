"""Build NannyBasics.mpackage (config.lua + NannyBasics.xml) from nannybasics.lua.

The shared border coordinator (border.lua) is vendored identically with the mapper and
prepended into the single shipped script, so an installed copy carries it without needing
a separate file. It is wrapped in an immediately-called function because border.lua ends
with `return B`, which would otherwise abort the combined chunk. In the monorepo the
mapper's copy is diffed against ours to catch drift.

Run from anywhere:  python basics/build.py
"""
import os
import sys
from xml.sax.saxutils import escape

here = os.path.dirname(os.path.abspath(__file__))

border = open(os.path.join(here, 'border.lua'), encoding='utf-8').read()

# Vendoring discipline: the two copies must stay byte-identical. The mapper's copy is at
# ../nmp/client/lua in the MUD repo and at ../mapper/lua in the public NannyMUD-mudlet repo.
for mirror in (os.path.join(here, '..', 'nmp', 'client', 'lua', 'border.lua'),
               os.path.join(here, '..', 'mapper', 'lua', 'border.lua')):
    mirror = os.path.normpath(mirror)
    if os.path.isfile(mirror) and open(mirror, encoding='utf-8').read() != border:
        sys.exit('build: border.lua has drifted from\n  %s\nresync the two copies before building.' % mirror)

# The newest border.lua wins at load by its REV, so a changed file must carry a higher REV than
# the committed one, or an older copy in another package could beat it. Checked against git HEAD
# when there is one.
import re
import subprocess

def rev_of(src):
    m = re.search(r'^local REV = (\d+)$', src, re.M)
    return int(m.group(1)) if m else 0

try:
    # HEAD:./ is relative to cwd, so this works wherever the folder sits in its repo
    committed = subprocess.run(['git', 'show', 'HEAD:./border.lua'], cwd=here,
                               capture_output=True, text=True, encoding='utf-8')
except OSError:
    committed = None
if committed and committed.returncode == 0 and committed.stdout.replace('\r\n', '\n') != border.replace('\r\n', '\n'):
    if rev_of(border) <= rev_of(committed.stdout):
        sys.exit('build: border.lua changed since the last commit but its REV is still %d; raise it.'
                 % rev_of(border))

body = open(os.path.join(here, 'nannybasics.lua'), encoding='utf-8').read()
lua = '-- vendored border coordinator (see border.lua); shared byte-for-byte with the mapper.\n' \
      '(function()\n' + border + '\nend)()\n\n' + body

xml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE MudletPackage>
<MudletPackage version="1.001">
\t<ScriptPackage>
\t\t<Script isActive="yes" isFolder="no">
\t\t\t<name>NannyBasics</name>
\t\t\t<packageName></packageName>
\t\t\t<script>%s</script>
\t\t\t<eventHandlerList />
\t\t</Script>
\t</ScriptPackage>
</MudletPackage>
''' % escape(lua)

out = os.path.join(here, 'NannyBasics.xml')
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write(xml)

# The .mpackage is what ships: the script plus a config.lua, whose version is what Mudlet's
# package manager (mpkg) compares. That version is N.VERSION, so it lives in one place.
import zipfile
m = re.search(r'^N\.VERSION = "([^"]+)"', body, re.M)
if not m:
    sys.exit('build: no N.VERSION = "..." line in nannybasics.lua')
config = '''mpackage = "NannyBasics"
title = "NannyBasics: gauges, score card, party, guild and chat panes for NannyMUD"
description = [[Draws NannyMUD's GMCP data: HP/SP and foe gauges, a score card, your party, your
guild, and a tabbed chat window. Shares one layout with the ElrohirMapper map. Type `nanny` once
installed, and `nanny update` to get a newer version.]]
version = "%s"
author = "Elrohir"
''' % m.group(1)
pkg = os.path.join(here, 'NannyBasics.mpackage')
with zipfile.ZipFile(pkg, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('config.lua', config)
    z.writestr('NannyBasics.xml', xml)
print('build: %s (version %s; %d bytes of Lua: %d border + %d body)'
      % (pkg, m.group(1), len(lua), len(border), len(body)))
