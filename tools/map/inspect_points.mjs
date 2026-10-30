import fs from 'fs';

const pFlat = JSON.parse(fs.readFileSync('tools/map/points_530b488c-2bd3-4c7a-9576-33928a1cbc52.json', 'utf8'));
console.log('Flat points count:', pFlat.points?.length);
console.log('Sample flat points:', JSON.stringify(pFlat.points?.slice(0, 5), null, 2));

const kinds = [...new Set(pFlat.points?.map(p => p.kind))];
console.log('Point kinds:', kinds);
