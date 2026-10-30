import glob
import os

tiles = glob.glob('assets/tiles/*.png')
keys = sorted([os.path.basename(t).replace('.png', '') for t in tiles])
print(f'Total tiles now in assets/tiles: {len(keys)}')

out_path = 'lib/data/geo/available_tiles.dart'
with open(out_path, 'w', encoding='utf-8') as f:
    f.write('/// 离线瓦片集合常量，自动生成\n')
    f.write('const Set<String> kAvailableTileKeys = <String>{\n')
    for k in keys:
        f.write(f"  '{k}',\n")
    f.write('};\n')
print(f'Updated {out_path}')
