#!/usr/bin/env python3
"""Validates tools/evo_data.py against the ability tables in gen_data.py.

Run from anywhere:  python tools/check_evo.py [--strict-icons]

Errors (exit code 1): wrong option counts, duplicate or malformed ids, ids that collide with existing branch
flag keys, card text over 110 chars, caps that name params an ability does not have or have min > max.
Icons: reports how many art/evo/<id>.png files exist; with --strict-icons a missing icon is an error.
"""
import copy
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import evo_data  # noqa: E402
import gen_data  # noqa: E402

MAX_DESC = 110
MAX_NAME = 24
ID_RE = re.compile(r'^[a-z][a-z0-9_]*$')


def main():
    strict_icons = '--strict-icons' in sys.argv
    abilities = copy.deepcopy(gen_data.ABILITIES)
    evo_data.apply(abilities)
    errors = []
    by_id = {a['id']: a for a in abilities}

    # every kit ability: 2 branches x 2 tiers x 2 options
    total = 0
    for a in abilities:
        for bi, b in enumerate(a['branches']):
            for tier_key in ('evo1', 'evo2'):
                opts = b.get(tier_key, [])
                if len(opts) != 2:
                    errors.append('%s branch %s %s: expected 2 options, found %d' % (a['id'], 'ab'[bi], tier_key, len(opts)))
                total += len(opts)
    if total != 160:
        errors.append('expected 160 options in total, found %d' % total)

    # ids and card text
    seen = {}
    flag_keys = set()
    for a in abilities:
        for b in a['branches']:
            flag_keys.update((b.get('flags') or {}).keys())
    for o in evo_data.OPTIONS:
        oid = o['id']
        if not ID_RE.match(oid):
            errors.append('%s: id must be snake_case' % oid)
        if oid in seen:
            errors.append('%s: duplicate id (also %s)' % (oid, seen[oid]))
        seen[oid] = '%s/%s/t%d' % (o['ability'], o['branch'], o['tier'])
        if oid in flag_keys:
            errors.append('%s: id collides with an existing branch flag key' % oid)
        if o['ability'] not in by_id:
            errors.append('%s: unknown ability %s' % (oid, o['ability']))
        if len(o['desc']) > MAX_DESC:
            errors.append('%s: desc is %d chars (max %d)' % (oid, len(o['desc']), MAX_DESC))
        if len(o['name']) > MAX_NAME:
            errors.append('%s: name is %d chars (max %d)' % (oid, len(o['name']), MAX_NAME))
        if not o['desc'].isascii() or not o['name'].isascii():
            errors.append('%s: keep name/desc ASCII (card font)' % oid)

    # caps
    for aid, caps in evo_data.CAPS.items():
        a = by_id.get(aid)
        if a is None:
            errors.append('caps for unknown ability %s' % aid)
            continue
        for param, c in caps.items():
            if param not in a['base']:
                errors.append('%s: cap on %s but the ability has no such base param' % (aid, param))
            if 'min' in c and 'max' in c and c['min'] > c['max']:
                errors.append('%s.%s: min > max' % (aid, param))
    for a in abilities:
        if a['id'] not in evo_data.CAPS:
            errors.append('%s: no caps entry' % a['id'])

    # icons
    missing = [o['id'] for o in evo_data.OPTIONS
               if not os.path.exists(os.path.join(ROOT, 'art', 'evo', o['id'] + '.png'))]
    print('options: %d   abilities: %d   icons present: %d / %d' % (total, len(abilities), len(evo_data.OPTIONS) - len(missing), len(evo_data.OPTIONS)))
    if missing and strict_icons:
        errors.extend('missing icon: art/evo/%s.png' % m for m in missing)

    if errors:
        print('\n%d problem(s):' % len(errors))
        for e in errors:
            print('  - ' + e)
        return 1
    print('OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
