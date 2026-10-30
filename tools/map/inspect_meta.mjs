import fs from 'fs';

const blds = JSON.parse(fs.readFileSync('tools/map/target_buildings.json', 'utf8'));

console.log('--- 校园寻物局 Building Metadata ---');
console.log('Total buildings:', blds.length);

for (const b of blds) {
  console.log(`Building: ${b.name} (${b.category}) [code: ${b.code}]`);
  console.log(`  Flat label: x=${b.label_position?.x}, y=${b.label_position?.y}`);
  console.log(`  ISO label: x=${b.iso_label_position?.x}, y=${b.iso_label_position?.y}`);
  console.log(`  Flat points: ${b.click_region?.length}, ISO points: ${b.iso_hit_area?.length}`);
}
