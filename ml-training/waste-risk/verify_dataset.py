#!/usr/bin/env python3
"""Verify synthetic split sizes, balanced classes and absence of exact feature leakage."""
import csv
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parent / 'datasets'
signatures = {}
for split, expected in [('train', 840), ('validation', 180), ('test', 180)]:
    with (root / f'{split}.csv').open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    values = {tuple(row[key] for key in row if key != 'riskLabel') for row in rows}
    counts = Counter(row['riskLabel'] for row in rows)
    assert len(rows) == expected and len(values) == expected, f'{split}: size or duplicate error'
    assert counts == {'Low': expected // 3, 'Medium': expected // 3, 'High': expected // 3}
    for earlier, earlier_values in signatures.items():
        assert not values & earlier_values, f'Feature leakage: {earlier}/{split}'
    signatures[split] = values
    print(f'{split}: {expected} unique rows, {dict(counts)}')
print('No exact feature-vector overlap between splits. Similar synthetic scenarios may still exist.')
