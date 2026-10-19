"""Build the local extension as a VSIX so Code registers versions and metadata.
No marketplace upload, dependencies, or shell-generated JSON.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED
import json

root=Path(__file__).resolve().parents[1]
source=root/'extensions/vscode'
package=json.loads((source/'package.json').read_text())
ns='http://schemas.microsoft.com/developer/vsx-schema/2011'
ET.register_namespace('',ns)
def element(parent,name,attributes=None,text=None):
    node=ET.SubElement(parent,'{'+ns+'}'+name,attributes or {})
    node.text=text
    return node
manifest=ET.Element('{'+ns+'}PackageManifest',{'Version':'2.0.0'})
metadata=element(manifest,'Metadata')
element(metadata,'Identity',{'Language':'en-US','Id':package['name'],'Version':package['version'],'Publisher':package['publisher']})
element(metadata,'DisplayName',text=package['displayName'])
element(metadata,'Description',{'{http://www.w3.org/XML/1998/namespace}space':'preserve'},package['description'])
element(metadata,'Tags',text='desktop-pet,vscode')
element(metadata,'Categories',text='Other')
element(metadata,'GalleryFlags',text='Public')
properties=element(metadata,'Properties')
element(properties,'Property',{'Id':'Microsoft.VisualStudio.Code.Engine','Value':package['engines']['vscode']})
element(properties,'Property',{'Id':'Microsoft.VisualStudio.Code.ExtensionDependencies','Value':''})
element(properties,'Property',{'Id':'Microsoft.VisualStudio.Code.ExtensionPack','Value':''})
installation=element(manifest,'Installation')
element(installation,'InstallationTarget',{'Id':'Microsoft.VisualStudio.Code'})
element(manifest,'Dependencies')
assets=element(manifest,'Assets')
element(assets,'Asset',{'Type':'Microsoft.VisualStudio.Code.Manifest','Path':'extension/package.json','Addressable':'true'})
element(assets,'Asset',{'Type':'Microsoft.VisualStudio.Services.Content.Details','Path':'extension/README.md','Addressable':'true'})
types=ET.Element('Types',{'xmlns':'http://schemas.openxmlformats.org/package/2006/content-types'})
for ext,mime in [('json','application/json'),('js','application/javascript'),('cjs','application/javascript'),('png','image/png'),('md','text/markdown'),('vsixmanifest','text/xml')]:
    ET.SubElement(types,'Default',{'Extension':ext,'ContentType':mime})
dest=root/'dist'/f"{package['name']}-{package['version']}.vsix"
dest.parent.mkdir(exist_ok=True)
with ZipFile(dest,'w',ZIP_DEFLATED) as archive:
    archive.writestr('extension.vsixmanifest',ET.tostring(manifest,encoding='utf-8',xml_declaration=True))
    archive.writestr('[Content_Types].xml',ET.tostring(types,encoding='utf-8',xml_declaration=True))
    for name in ['package.json','extension.js','markers.cjs','README.md','assets/poop.png']:
        archive.write(source/name,'extension/'+name)
print(dest)
