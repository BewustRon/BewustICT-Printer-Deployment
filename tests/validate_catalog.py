import json
import pathlib
import re
from datetime import date
from urllib.parse import urlparse

path = pathlib.Path(__file__).resolve().parents[1] / 'catalog' / 'drivers.json'
catalog = json.loads(path.read_text(encoding='utf-8'))
assert catalog['schemaVersion'] == 1
assert set(catalog['drivers']) == {'HP', 'Epson', 'Canon', 'Kyocera', 'Ricoh', 'Brother'}

# Full candidate metadata is permitted while still pending; deployment must
# reject all pending records. Approval is an explicit, reviewed state change.
required = ('driverName', 'downloadUrl', 'sha256', 'signerThumbprint', 'infRelativePath',
            'catRelativePath', 'signerSubjectContains')
allowed_vendor_hosts = {
    'HP': {'ftp.hp.com'},
    'Kyocera': {'www.kyoceradocumentsolutions.eu'},
}
for name, record in catalog['drivers'].items():
    assert record['status'] in {'pending', 'approved'}, name
    assert urlparse(record['sourcePage']).scheme == 'https', name
    date.fromisoformat(record['sourceCheckedAt'])
    assert record.get('distributionAssessment'), name
    url = record.get('downloadUrl', '')
    if url:
        parsed = urlparse(url)
        assert parsed.scheme == 'https' and parsed.username is None, name
        assert parsed.path.lower().endswith('.zip'), name
        if name in allowed_vendor_hosts:
            assert parsed.hostname in allowed_vendor_hosts[name], (name, parsed.hostname)
    if record.get('sha256'):
        assert re.fullmatch(r'[A-Fa-f0-9]{64}', record['sha256']), name
    if record['status'] == 'approved':
        for key in required:
            assert record.get(key), (name, key)
        assert re.fullmatch(r'[0-9A-Fa-f]{40}', record['signerThumbprint']), name
        assert record['distributionAssessment'] in {
            'approved-for-deployment',
            'official-vendor-direct-download-no-redistribution'
        }, name
        assert '..' not in pathlib.PurePosixPath(record['infRelativePath']).parts, name
        assert '..' not in pathlib.PurePosixPath(record['catRelativePath']).parts, name
    else:
        # A half-filled candidate must never be silently promoted to approved.
        # Actual PowerShell runtime checks status before reading candidate data.
        assert record['status'] == 'pending', name
print('OK: pending candidates and approved vendor driver constraints validated')
