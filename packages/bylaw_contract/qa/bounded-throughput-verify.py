"""Verify retained matrix integrity and equality among complete observations."""
import collections
import json
import sys

with open(sys.argv[1]) as source:
    rows = json.load(source)
assert len(rows) == 96
identities = set()
hashes = collections.defaultdict(set)
counts = collections.Counter()
for row in rows:
    assert row['exit_code'] == 0 and row['watchdog'] is None
    result = row['result']
    identity = tuple(result[key] for key in (
        'mode', 'producers', 'total', 'shape', 'size', 'pacing'))
    assert identity not in identities
    identities.add(identity)
    assert len(result['cycles']) == 2
    for cycle in result['cycles']:
        assert cycle['cleanup_verified'] and cycle['exact_when_complete']
        assert cycle['status'] in ('complete', 'incomplete')
        counts[result['total'], result['pacing'], cycle['status']] += 1
        if cycle['status'] == 'complete':
            key = result['mode'], result['total'], result['shape']
            hashes[key].add((cycle['coverage_hash'], cycle['report_hash']))
            assert not cycle['incomplete']
            if result['mode'] != 'structural':
                assert cycle['calls'] == cycle['returns'] == result['total']
            if result['mode'] != 'typespec':
                assert cycle['structural_calls'] == result['total']
        else:
            assert cycle['incomplete']
            assert all(reason['limit'] == 4096 and reason['observed'] > 4096
                       for reason in cycle['incomplete'])
assert hashes and all(len(values) == 1 for values in hashes.values())
for key, count in sorted(counts.items()):
    print(*key, count)
print('Complete coverage/report equality groups:', len(hashes))
