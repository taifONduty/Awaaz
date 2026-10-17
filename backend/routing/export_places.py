"""Offline, bounded OSM catalogue; no per-user provider requests or author data."""
import argparse
import hashlib
import json
import math
import os
import unicodedata
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def clean(value):
    text = unicodedata.normalize('NFC', value or '').strip()
    return text if 1 <= len(text) <= 160 and not any(unicodedata.category(c) == 'Cc' for c in text) else ''


def in_pilot(p):
    return 23.62 <= p[0] <= 24.02 and 90.20 <= p[1] <= 90.58


def kind(tags):
    if tags.get('access') in ('private', 'no') or tags.get('disused') == 'yes' or tags.get('abandoned') == 'yes':
        return None
    if tags.get('highway') == 'bus_stop': return 'transit'
    if tags.get('highway') not in (None, 'construction', 'proposed'):
        return 'road'
    amenity = tags.get('amenity')
    if amenity in ('school', 'college', 'university', 'library', 'kindergarten'): return 'education'
    if amenity in ('hospital', 'clinic', 'pharmacy', 'doctors'): return 'health'
    if tags.get('public_transport') or tags.get('railway') == 'station' or amenity in ('bus_station', 'ferry_terminal'): return 'transit'
    if tags.get('shop'): return 'shop'
    if tags.get('place'): return 'area'
    if amenity or tags.get('tourism') or tags.get('leisure'): return 'place'
    return None


def representative(points):
    # Use an actual mapped vertex nearest the feature's bounding-box centre.
    # It is a browse position, never an asserted public entrance or address.
    if not points: return None
    centre = ((min(p[0] for p in points) + max(p[0] for p in points)) / 2,
              (min(p[1] for p in points) + max(p[1] for p in points)) / 2)
    return min(points, key=lambda p: (p[0]-centre[0])**2 + ((p[1]-centre[1])*math.cos(math.radians(centre[0])))**2)


def extract(path):
    nodes, ways, pending_relations, entries = {}, {}, [], []
    source_time = None
    iterator = ET.iterparse(path, events=('start', 'end'))
    _, root = next(iterator)
    if root.tag != 'osm': raise ValueError('Not OSM XML')

    def entry(entity, tags, point):
        category = kind(tags)
        name = clean(tags.get('name', '').split(';')[0]) or clean(tags.get('name:en')) or clean(tags.get('name:bn'))
        if not category or not name or not point or not in_pilot(point): return
        aliases = []
        for key in ('name', 'name:en', 'name:bn', 'alt_name', 'local_name', 'short_name'):
            for value in tags.get(key, '').split(';'):
                value = clean(value)
                if value and value not in aliases: aliases.append(value)
        entries.append(dict(id=entity, name=name, nameEn=clean(tags.get('name:en')) or name,
                            nameBn=clean(tags.get('name:bn')) or name, aliases=aliases[:8], kind=category,
                            point=dict(latitude=point[0], longitude=point[1])))

    for event, element in iterator:
        if event != 'end': continue
        if element.tag == 'meta': source_time = element.get('osm_base')
        if element.tag == 'remark': raise ValueError('Incomplete extract')
        if element.tag not in ('node', 'way', 'relation'): continue
        tags = {t.get('k'): t.get('v', '') for t in element.findall('tag')}
        identifier = int(element.get('id'))
        if element.tag == 'node':
            point = (float(element.get('lat')), float(element.get('lon')))
            nodes[identifier] = point
            if len(nodes) > 2000000: raise ValueError('Node limit')
            entry('osm:node:' + str(identifier), tags, point)
        elif element.tag == 'way':
            refs = [int(n.get('ref')) for n in element.findall('nd')]
            points = [nodes[n] for n in refs if n in nodes]
            # Partial geometry cannot establish a representative mapped position.
            if len(points) == len(refs) and points:
                ways[identifier] = points
                entry('osm:way:' + str(identifier), tags, representative(points))
        else:
            refs = [(m.get('type'), int(m.get('ref'))) for m in element.findall('member') if m.get('role') != 'inner']
            pending_relations.append((identifier, tags, refs))
        element.clear()
        root.clear()
    for identifier, tags, refs in pending_relations:
        if any(t == 'relation' or (t == 'node' and n not in nodes) or (t == 'way' and n not in ways) for t, n in refs): continue
        points = [p for t, n in refs for p in ([nodes[n]] if t == 'node' else ways[n])]
        entry('osm:relation:' + str(identifier), tags, representative(points))
    if not source_time: raise ValueError('Missing source timestamp')
    return source_time, entries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = json.loads((root / '.local/routing/manifest.json').read_text(encoding='utf-8-sig'))
    roads = root / '.local/routing/dhaka.osm'
    pois = root / '.local/places/dhaka-poi.osm'
    road_digest, poi_digest = digest(roads), digest(pois)
    if road_digest != manifest['extractSha256']: raise ValueError('Road extract checksum mismatch')
    road_time, road_entries = extract(roads)
    poi_time, poi_entries = extract(pois)
    entries = {v['id']: v for v in road_entries + poi_entries}
    if not 10 <= len(entries) <= 50000: raise ValueError('Unexpected catalogue size')
    body = dict(format='awaaz-place-catalog-v1', graphVersion=manifest['graphVersion'],
                sourceTimestamp=min(road_time, poi_time), generatedAt=datetime.now(timezone.utc).isoformat(),
                extractDigests=dict(roads=road_digest, pois=poi_digest), items=sorted(entries.values(), key=lambda v: v['id']))
    target = root / '.local/places/catalog.json'
    partial = target.with_name(target.name + '.' + str(uuid.uuid4()) + '.partial')
    partial.write_text(json.dumps(body, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    checksum = digest(partial)
    os.replace(partial, target)
    target.with_suffix('.json.manifest.json').write_text(json.dumps(dict(format='awaaz-place-catalog-v1',
        graphVersion=manifest['graphVersion'], sha256=checksum, count=len(entries)), indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(count=len(entries), sha256=checksum, graphVersion=manifest['graphVersion'], sourceTimestamp=body['sourceTimestamp'])))


if __name__ == '__main__': main()
