import json
import pathlib
import re
from urllib.parse import urlparse

path = pathlib.Path(__file__).resolve().parents[1] / 'catalog' / 'drivers.json'
c = json.loads(path.read_text(encoding='utf-8'))
assert c['schemaVersion'] == 1
assert set(c['drivers']) == {'HP', 'Epson', 'Canon', 'Kyocera', 'Ricoh', 'Brother'}
for name, record in c['drivers'].items():
    assert record['status'] in {'pending', 'approved'}, name
    assert urlparse(record['sourcePage']).scheme == 'https', name
    assert record['sourceCheckedAt'] == '2026-10-30', name
    assert record.get('distributionAssessment'), name
    if record['status'] == 'pending':
        assert not any(record.get(k) for k in ('driverName','downloadUrl','sha256','infRelativePath','catRelativePath','signerSubjectContains')), name
    else:
        for k in ('driverName','downloadUrl','sha256','infRelativePath','catRelativePath','signerSubjectContains'):
            assert record.get(k), (name, k)
        assert urlparse(record['downloadUrl']).scheme == 'https', name
        assert record['downloadUrl'].lower().split('?')[0].endswith('.zip'), name
        assert re.fullmatch(r'[A-Fa-f0-9]{64}', record['sha256']), name
        assert record['distributionAssessment'] == 'approved-for-deployment', name
print('OK: drivercatalogus en fail-closed regels')
