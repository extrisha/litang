import fs from 'fs';

const raw = JSON.parse(fs.readFileSync('tools/map/all_buildings_137.json', 'utf8'));

// Common aliases mapping
const aliasMap = {
  '第一教学楼': ['一教', '1教', '第一教', '东方泛血管器械创新学院', '教学楼（BCD区）'],
  '第三教学楼': ['三教', '3教', '第三教'],
  '第四教学楼（逸兴楼）': ['四教', '4教', '第四教', '逸兴楼', '第四教学楼'],
  '卓越楼': ['卓越工程大楼', '健康科学与工程学院', '出版学院'],
  '综合楼': ['综合A', '综合楼A区', '综合B', '综合楼B区', '综合C', '综合楼C区', '综合D', '综合楼D区'],
  '国合楼（中德国际学院）': ['国合楼', '中德', '中德国际学院'],
  '中德国际学院实验中心': ['中德实验中心'],
  '系统楼（公共实验中心）': ['公共实验楼', '公共实验中心', '系统楼'],
  '图文信息中心': ['图文', '图书馆', '档案馆', '计算中心'],
  '体育活动中心': ['新体育馆', '大体育馆'],
  '体育健身中心': ['旧体育馆', '小体育馆'],
  '大礼堂': ['礼堂'],
  '小礼堂（沪江大学体育馆）': ['小礼堂', '沪江大学体育馆'],
  '格致堂（沪江大学科学馆）': ['格致堂', '科学馆', '沪江大学科学馆'],
  '红塔（沪江大学水塔）': ['红塔', '水塔', '沪江大学水塔'],
  '勤业楼（行政楼）': ['行政楼', '勤业楼'],
  '第五食堂': ['五食', '第五教工食堂'],
  '第一食堂': ['一食'],
  '第二食堂': ['二食'],
  '思餐厅': ['四食堂', '南区食堂'],
  '能源与动力工程学院（动力馆）': ['动力馆', '能动学院', '动力一馆', '能源与动力工程学院动力馆'],
  '动力二馆': ['动力2馆'],
  '环境与建筑学院': ['环建学院', '环建楼'],
  '环境与建筑学院二号楼': ['环建二号楼'],
  '机械工程学院': ['机械学院', '机械楼'],
  '机械工程学院实验中心': ['机械实验中心'],
  '光电信息与计算机工程学院': ['光电大楼', '光电学院', '计算机学院', '电光大楼'],
  '菜鸟驿站': ['菜鸟', '快递点', '北区菜鸟'],
  '北区运动场': ['北操', '北操场', '北区操场'],
  '南区运动场': ['南操', '南操场', '南区操场'],
  '东堂（暖屋超市）': ['东堂', '暖屋超市', '教育超市', '教超', '上海教育超市'],
  '保卫处 校园110': ['保卫处', '校园110', '保卫处·校园110'],
  '校门诊部': ['门诊部', '校医院', '卫生所'],
  '军工路516号校门（正门）': ['正门', '516正门', '516大门', '校门'],
  '军工路580号校门': ['580门', '北门'],
  '军工路470号校门': ['470门', '地下通道门'],
  '军工路334号校门': ['334门', '南校门'],
  '第一学生公寓南楼': ['一公南', '一公'],
  '第一学生公寓北楼': ['一公北'],
  '第二学生公寓一号楼': ['二公一', '二公1号楼', '二公'],
  '第二学生公寓二号楼': ['二公二', '二公2号楼'],
  '第二学生公寓三号楼': ['二公三', '二公3号楼', '第二公寓三号楼'],
  '第三学生公寓一号楼': ['三公一', '三公1号楼', '三公'],
  '第三学生公寓二号楼': ['三公二', '三公2号楼'],
  '第三学生公寓三号楼': ['三公三', '三公3号楼'],
  '第四学生公寓一号楼': ['四公一', '四公1号楼', '四公'],
  '第四学生公寓二号楼': ['四公二', '四公2号楼'],
  '第四学生公寓三号楼': ['四公三', '四公3号楼'],
  '第四学生公寓四号楼': ['四公四', '四公4号楼'],
  '第五学生公寓一号楼': ['五公一', '五公1号楼', '五公'],
  '第五学生公寓二号楼': ['五公二', '五公2号楼'],
  '第五学生公寓三号楼': ['五公三', '五公3号楼'],
  '第五学生公寓四号楼': ['五公四', '五公4号楼'],
  '第六学生公寓一号楼': ['六公一', '六公1号楼', '六公'],
  '第六学生公寓二号楼': ['六公二', '六公2号楼'],
  '第六学生公寓三号楼': ['六公三', '六公3号楼'],
  '第七学生公寓': ['七公', '七公寓'],
  '启明楼': ['启明'],
  '先进制造大楼': ['先进制造'],
  '先进制造大楼辅楼': ['先进制造辅楼'],
  '继续教育学院': ['继教学院', '创新创业学院', '继续教育学院·创新创业学院'],
  '材料与化学学院材料楼': ['材化楼', '材料楼'],
  '理科实验中心': ['理科楼', '化学系'],
  '食品学院大楼': ['食品学院', '食品楼'],
};

// Sort by drawOrder
raw.sort((a, b) => (a.draw_order || 0) - (b.draw_order || 0));

function r6(num) {
  return Number(num.toFixed(6));
}

let out = `import 'dart:ui';
import 'campus_building.dart';

/// 军工路 516 号校区全量 137 个已校准建筑与地标实体数据
/// 包含 2D 平面多边形、2.5D 立体多边形、中心标签锚点与教务别名匹配
class Campus516Data {
  Campus516Data._();

  static const double flatWidth = 1899.0;
  static const double flatHeight = 2400.0;
  static const double isoWidth = 2400.0;
  static const double isoHeight = 1842.0;

  static const List<CampusBuilding> buildings = <CampusBuilding>[
`;

for (const b of raw) {
  const aliases = aliasMap[b.name] || [];
  const flatPts = (b.click_region || []).map(p => `Offset(${r6(p.x)}, ${r6(p.y)})`).join(', ');
  const isoPts = (b.iso_hit_area || []).map(p => `Offset(${r6(p.x)}, ${r6(p.y)})`).join(', ');
  const fl = b.label_position || { x: 0.5, y: 0.5 };
  const il = b.iso_label_position || { x: 0.5, y: 0.5 };
  const aliasesStr = aliases.map(a => `'${a}'`).join(', ');

  out += `    CampusBuilding(
      id: '${b.id}',
      code: '${b.code || ''}',
      name: '${b.name}',
      category: '${b.category || '生活服务'}',
      floors: ${b.floors || 1},
      drawOrder: ${b.draw_order || 0},
      flatLabel: Offset(${r6(fl.x)}, ${r6(fl.y)}),
      isoLabel: Offset(${r6(il.x)}, ${r6(il.y)}),
      flatPolygon: <Offset>[${flatPts}],
      isoPolygon: <Offset>[${isoPts}],
      aliases: <String>[${aliasesStr}],
    ),
`;
}

out += `  ];

  /// 根据教室名/地点名/别名智能查找建筑
  static CampusBuilding? findBuilding(String query) {
    final q = query.trim();
    if (q.isEmpty) return null;

    // 1. 精确匹配名字
    for (final b in buildings) {
      if (b.name == q) return b;
    }

    // 2. 匹配别名
    for (final b in buildings) {
      if (b.aliases.contains(q)) return b;
    }

    // 3. 包含匹配 (以长名称优先)
    CampusBuilding? best;
    for (final b in buildings) {
      if (b.name != '未命名建筑') {
        if (q.contains(b.name) || b.name.contains(q)) {
          if (best == null || b.name.length > best.name.length) {
            best = b;
          }
        }
      }
      for (final a in b.aliases) {
        if (q.contains(a) || a.contains(q)) {
          if (best == null || a.length > (best.name.length)) {
            best = b;
          }
        }
      }
    }
    return best;
  }
}
`;

fs.writeFileSync('lib/data/illustrated_map/campus_516_buildings.dart', out, 'utf8');
console.log('Successfully generated lib/data/illustrated_map/campus_516_buildings.dart');
