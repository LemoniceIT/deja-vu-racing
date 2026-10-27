path = '.godot/imported/vehicle-toyota-ae86.glb-5d0c6709772c670d4bad0fd318b1d936.scn'
data = open(path,'rb').read()
for kw in [b'Wheel', b'Car', b'RootNode', b'Camera']:
    idxs = []
    start = 0
    while True:
        i = data.find(kw, start)
        if i == -1: break
        idxs.append(i)
        start = i+1
    print(kw, 'count=', len(idxs))
    for i in idxs[:8]:
        seg = data[max(0,i-8):i+len(kw)+6]
        print('   off', i, 'hex', seg.hex(), 'repr', repr(seg))
