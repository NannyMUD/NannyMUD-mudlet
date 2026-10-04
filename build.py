"""Build NannyBasics.xml, an installable Mudlet package, from nannybasics.lua.

Run from anywhere:  python nannybasics/build.py
"""
import os
from xml.sax.saxutils import escape

here = os.path.dirname(os.path.abspath(__file__))
lua = open(os.path.join(here, 'nannybasics.lua'), encoding='utf-8').read()

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
print('build: %s (%d bytes of Lua)' % (out, len(lua)))
