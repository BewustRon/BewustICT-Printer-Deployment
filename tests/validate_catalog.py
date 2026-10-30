import json
import pathlib
import re
import sys

path = pathlib.Path(__file__).resolve().parents[1] / 'catalog' / 'drivers.json'
c = json.loads(path.read_text(encoding='utf-8'))
assert c['schemaVersion'] == 1
assert set(c['drivers']) == {'HP', 'Epson', 'Canon', 'Kyocera', 'Ricoh', 'Brother'}
for name, record in c['drivers'].items():
    assert record['status'] in {'pending', 'approved'}
    assert record['sourcePage'].startswith('https://')
    if record['status'] == 'approved':
        for k in ('driverName', 'downloadUrl', 'sha256', 'infRelativePath', 'catRelativePath', 'signerSubjectContains'):
            assert record.get(k), (name, k)
        assert record['downloadUrl'].startswith('https://')
        assert re.fullmatch(r'[A-Fa-f0-9]{64}', record['sha256'])
        assert record['downloadUrl'].lower().split('?')[0].endswith('.zip')
print('OK: drivercatalogus schema en goedkeuringsgates gecontroleerd')
