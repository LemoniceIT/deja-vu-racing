import struct, json

def parse_glb(filepath):
    with open(filepath, 'rb') as f:
        data_all = f.read()

    chunk1_length = struct.unpack_from('<I', data_all, 12)[0]
    json_str = data_all[20:20+chunk1_length].decode('utf-8')
    data = json.loads(json_str)

    chunk2_start = 20 + chunk1_length
    chunk2_length = struct.unpack_from('<I', data_all, chunk2_start)[0]
    binary_data = data_all[chunk2_start+8:chunk2_start+8+chunk2_length]

    print(f'=== {filepath} ===')
    print('Nodes:')
    for i, node in enumerate(data.get('nodes', [])):
        name = node.get('name')
        mesh = node.get('mesh')
        trans = node.get('translation')
        scale = node.get('scale')
        print(f'  {i}: name={name}, mesh={mesh}, translation={trans}, scale={scale}')

    print('Meshes:')
    for i, mesh in enumerate(data.get('meshes', [])):
        name = mesh.get('name')
        for j, prim in enumerate(mesh.get('primitives', [])):
            attrs = prim.get('attributes', {})
            pos_idx = attrs.get('POSITION', -1)
            if pos_idx >= 0 and pos_idx < len(data.get('accessors', [])):
                acc = data['accessors'][pos_idx]
                bv = data['bufferViews'][acc['bufferView']]
                byte_off = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
                count = acc['count']
                y_min = float('inf')
                y_max = float('-inf')
                x_min = float('inf')
                x_max = float('-inf')
                z_min = float('inf')
                z_max = float('-inf')
                for k in range(count):
                    off = byte_off + k * 12
                    x, y, z = struct.unpack_from('<fff', binary_data, off)
                    y_min = min(y_min, y)
                    y_max = max(y_max, y)
                    x_min = min(x_min, x)
                    x_max = max(x_max, x)
                    z_min = min(z_min, z)
                    z_max = max(z_max, z)
                print(f'  Mesh {i} ({name}): Y=[{y_min:.4f}, {y_max:.4f}] size={y_max-y_min:.4f}')

    import_path = filepath + '.import'
    print(f'Import settings:')
    with open(import_path, 'r') as f:
        for line in f:
            if 'root_scale' in line or 'apply_root_scale' in line:
                print(f'  {line.strip()}')
    print()

parse_glb('models/vehicle-truck-yellow.glb')
parse_glb('models/vehicle-toyota-ae86.glb')
