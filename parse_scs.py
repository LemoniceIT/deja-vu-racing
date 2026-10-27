import re

path = '.godot/imported/vehicle-toyota-ae86.glb-5d0c6709772c670d4bad0fd318b1d936.scn'
with open(path, 'rb') as f:
    data = f.read()

text = data.decode('latin-1')
for match in re.finditer(r'(Transform3D|scale|position|origin|0\.346|1\.809|100\.0)', text):
    start = max(0, match.start() - 30)
    end = min(len(text), match.end() + 80)
    context = text[start:end].replace('\n', '\\n').replace('\r', '')
    print(f"Pos {match.start()}: {context}")
