import struct, json, hashlib

for filepath in ['models/vehicle-toyota-ae86.glb', 'models_new/Toyota AE86 by IvOfficial - ZEFWmOPSgh.glb']:
    with open(filepath, 'rb') as f:
        data_all = f.read()
    md5 = hashlib.md5(data_all).hexdigest()
    chunk1_length = struct.unpack_from('<I', data_all, 12)[0]
    json_str = data_all[20:20+chunk1_length].decode('utf-8')
    data = json.loads(json_str)
    print(f'=== {filepath} === md5={md5} size={len(data_all)}')
    nodes = data.get('nodes', [])
    roots = set(range(len(nodes)))
    for node in nodes:
        for c in (node.get('children') or []):
            roots.discard(c)
    def tree(idx, depth=0):
        node = nodes[idx]
        print('  '*depth + f'- {node.get("name")} mesh={node.get("mesh")} trans={node.get("translation")} rot={node.get("rotation")} scale={node.get("scale")}')
        for c in (node.get("children") or []):
            tree(c, depth+1)
    print('roots:', sorted(roots))
    for r in sorted(roots):
        tree(r)
    print()
