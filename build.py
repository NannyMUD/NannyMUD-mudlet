"""Build NannyBasics.xml, an installable Mudlet package, from nannybasics.lua.

The shared border coordinator (border.lua) is vendored identically with the mapper and
prepended into the single shipped script, so an installed copy carries it without needing
a separate file. It is wrapped in an immediately-called function because border.lua ends
with `return B`, which would otherwise abort the combined chunk. In the monorepo the
mapper's copy is diffed against ours to catch drift.

Run from anywhere:  python nannybasics/build.py
"""
import os
import sys
from xml.sax.saxutils import escape

here = os.path.dirname(os.path.abspath(__file__))

border = open(os.path.join(here, 'border.lua'), encoding='utf-8').read()

# Vendoring discipline: the two copies must stay byte-identical. Only checked when the
# mapper tree is present; the published NannyBasics repo has no such sibling.
mirror = os.path.normpath(os.path.join(here, '..', 'nmp', 'client', 'lua', 'border.lua'))
if os.path.isfile(mirror):
    if open(mirror, encoding='utf-8').read() != border:
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
    committed = subprocess.run(['git', 'show', 'HEAD:nannybasics/border.lua'], cwd=here,
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
print('build: %s (%d bytes of Lua: %d border + %d body)' % (out, len(lua), len(border), len(body)))
