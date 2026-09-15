#!/usr/bin/env python3
"""Optional deep fixture validation; dependencies described in README.md."""
from __future__ import annotations
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from PIL import Image
from pypdf import PdfReader
from pyzbar.pyzbar import decode

ROOT=Path(__file__).resolve().parents[2]
def main():
    renderer=shutil.which('pdftoppm')
    if renderer is None: raise RuntimeError('pdftoppm is required; no source-rendering pass claimed')
    manifest=json.loads((ROOT/'Fixtures/generated/manifest.json').read_text())
    pages=symbols=0
    with tempfile.TemporaryDirectory(prefix='label-fixture-source-') as tmp:
        for item in manifest['fixtures']:
            if not item['path'].endswith('.pdf'): continue
            path=ROOT/item['path'];reader=PdfReader(path)
            if len(reader.pages)!=item['pageCount']: raise ValueError('Page count mismatch')
            for page,expected in zip(reader.pages,item['pages']):
                for key,box in [('mediaBox',page.mediabox),('cropBox',page.cropbox)]:
                    if any(abs(float(a)-b)>1e-5 for a,b in zip(box,expected[key])): raise ValueError('Box mismatch')
                if page.rotation!=expected['rotation'] or page.get('/UserUnit',1)!=expected['userUnit']: raise ValueError('Page transform mismatch')
            prefix=Path(tmp)/item['id']
            subprocess.run([renderer,'-r','500','-png',str(path),str(prefix)],check=True,capture_output=True,timeout=60)
            files=sorted(Path(tmp).glob(item['id']+'-*.png'),key=lambda p:int(p.stem.rsplit('-',1)[1]))
            if len(files)!=item['pageCount']: raise ValueError('Rendered page count mismatch')
            for image,expected in zip(files,item['pages']):
                with Image.open(image) as im:
                    found=sorted((v.type,v.data.decode()) for v in decode(im))
                    pairs=sorted((kind,value) for value in expected['expectedBarcodePayloads'] for kind in ('CODE128','QRCODE'))
                    if found!=pairs: raise ValueError(f'Source barcode mismatch: {image.name}')
                    print(f'{image.name}: pixels={im.size}; symbols={len(found)}')
                pages+=1;symbols+=len(found);image.unlink()
    print(f'PASS: source structure/barcodes on {pages} pages; {symbols} symbols. NOT physical qualification.')
if __name__=='__main__':main()
