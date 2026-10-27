import struct, json

filepath = 'models/vehicle-toyota-ae86.glb'
with open(filepath, 'rb') as f:
    data_all = f.read()

chunk1_length = struct.unpack_from('<I', data_all, 12)[0]
json_str = data_all[20:20+chunk1_length].decode('utf-8')
data = json.loads(json_str)

nodes = data.get('nodes', [])
print('=== NODE HIERARCHY ===')
for i, node in enumerate(nodes):
    name = node.get('name')
    children = node.get('children')
    mesh = node.get('mesh')
    trans = node.get('translation')
    rot = node.get('rotation')
    scale = node.get('scale')
    print(f'  idx {i}: name="{name}" mesh={mesh} children={children} translation={trans} rotation={rot} scale={scale}')

# Find root nodes (nodes not referenced as children of anyone)
all_children = set()
for node in nodes:
    for c in (node.get('children') or []):
        all_children.add(c)
roots = [i for i in range(len(nodes)) if i not in all_children]
print('roots:', roots)

# Build tree from roots
def print_tree(idx, depth=0):
    node = nodes[idx]
    name = node.get('name')
    print('  ' * depth + f'- {name} (idx {idx}) mesh={node.get("mesh")}')
    for c in (node.get('children') or []):
        print_tree(c, depth + 1)

print('=== TREE ===')
for r in roots:
    print_tree(r)

print('=== SCENE ===')
scenes = data.get('scenes', [])
for s in scenes:
    print('  scene:', s)
