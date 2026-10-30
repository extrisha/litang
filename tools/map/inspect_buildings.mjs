import fs from 'fs';

const blds = JSON.parse(fs.readFileSync('tools/map/target_buildings.json', 'utf8'));
console.log('Total buildings:', blds.length);
blds.forEach(b => {
  console.log(`- [${b.code}] ${b.name} (${b.category}), click_region points: ${b.click_region?.length}, iso_hit_area: ${b.iso_hit_area?.length}`);
  console.log(`  label_pos: (${b.label_position?.x}, ${b.label_position?.y}), iso_label: (${b.iso_label_position?.x}, ${b.iso_label_position?.y})`);
});
