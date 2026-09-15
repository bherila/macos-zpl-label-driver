#!/usr/bin/env python3
"""Standard-library fixture integrity/metadata checks. Does not parse/render PDFs."""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def validate(root=ROOT):
    manifest=json.loads((root/'Fixtures/generated/manifest.json').read_text())
    if manifest['schemaVersion'] != 1: raise ValueError('Unsupported fixture schema')
    seen=set();pdfs=pages=html=0
    for f in manifest['fixtures']:
        path=(root/f['path']).resolve()
        if not path.is_relative_to((root/'Fixtures/generated').resolve()) or f['id'] in seen:
            raise ValueError('Duplicate/escaping fixture')
        seen.add(f['id']);data=path.read_bytes()
        if len(data)!=f['bytes'] or hashlib.sha256(data).hexdigest()!=f['sha256']:
            raise ValueError('Fixture content differs from committed manifest')
        if f['license']!='MIT': raise ValueError('Unexpected generated fixture license')
        if path.suffix=='.pdf':
            pdfs+=1;pages+=f['pageCount']
            if not data.startswith(b'%PDF-') or b'%%EOF' not in data[-30:]: raise ValueError('PDF envelope mismatch')
            if len(f['pages'])!=f['pageCount']: raise ValueError('Page metadata mismatch')
            for p in f['pages']:
                if p['rotation'] not in [0,90,180,270] or p['userUnit'] not in [1,2]: raise ValueError('Unsupported synthetic geometry')
                for box in [p['mediaBox'],p['cropBox']]:
                    if len(box)!=4 or not all(math.isfinite(v) for v in box) or box[2]<=box[0] or box[3]<=box[1]: raise ValueError('Bad box')
                for r in p['regions']:
                    x,y,w,h=r['uprightNormalizedRect']
                    if not all(math.isfinite(v) for v in (x,y,w,h)) or x < -1e-9 or y < -1e-9 or w<=0 or h<=0 or x+w>1+1e-9 or y+h>1+1e-9: raise ValueError('Bad normalized region')
        elif path.suffix=='.html':
            html+=1
            if b'<script' in data or b'http://' in data.replace(b'http://www.w3.org/2000/svg',b'') or b'https://' in data: raise ValueError('Unexpected external/active fixture asset')
    if not pdfs or not html: raise ValueError('Missing concrete fixtures')
    return pdfs,pages,html
if __name__=='__main__':
    p,n,h=validate();print(f'Fixture integrity: {p} PDFs / {n} pages + {h} standalone HTML files')
