import 'dart:ui';

/// 官方校园地图地点（名称 + 归一化坐标）。
class CampusPlace {
  const CampusPlace({required this.name, required this.anchor});
  final String name;
  final Offset anchor;
}

const double kCampusMapWidth = 4500;
const double kCampusMapHeight = 5350;

const List<CampusPlace> kCampusPlaces = <CampusPlace>[
  CampusPlace(name: '继续教育学院·创新创业学院', anchor: Offset(0.1084, 0.5761)),
  CampusPlace(name: '分析测试中心', anchor: Offset(0.1362, 0.5480)),
  CampusPlace(name: '电镜影像分中心（一）', anchor: Offset(0.1362, 0.5570)),
  CampusPlace(name: '先进制造大楼辅楼', anchor: Offset(0.1464, 0.5963)),
  CampusPlace(name: '先进制造大楼', anchor: Offset(0.1584, 0.5673)),
  CampusPlace(name: '第七学生公寓', anchor: Offset(0.1891, 0.5320)),
  CampusPlace(name: '启明楼', anchor: Offset(0.1902, 0.6645)),
  CampusPlace(name: '体育活动中心', anchor: Offset(0.2511, 0.4813)),
  CampusPlace(name: '沪江美术馆（裴氏医院）', anchor: Offset(0.2724, 0.6484)),
  CampusPlace(name: '机械工程学院实验中心（二）', anchor: Offset(0.2764, 0.3953)),
  CampusPlace(name: '材料与化学学院材料楼', anchor: Offset(0.2933, 0.4127)),
  CampusPlace(name: '机械工程学院实验中心（二）', anchor: Offset(0.3058, 0.3658)),
  CampusPlace(name: '机械工程学院实验中心', anchor: Offset(0.3291, 0.3811)),
  CampusPlace(name: '工程实训中心', anchor: Offset(0.3293, 0.4445)),
  CampusPlace(name: '光仪所辅房', anchor: Offset(0.3438, 0.4077)),
  CampusPlace(name: '综合楼', anchor: Offset(0.3518, 0.6970)),
  CampusPlace(name: '能源与动力工程学院动力馆', anchor: Offset(0.3529, 0.6105)),
  CampusPlace(name: '机械工程学院', anchor: Offset(0.3627, 0.3436)),
  CampusPlace(name: '光仪所', anchor: Offset(0.3736, 0.4207)),
  CampusPlace(name: '收发室', anchor: Offset(0.3860, 0.6585)),
  CampusPlace(name: '环境与建筑学院二号楼', anchor: Offset(0.4053, 0.7434)),
  CampusPlace(name: '思鲁堂（能动学院一办）', anchor: Offset(0.4111, 0.6110)),
  CampusPlace(name: '校门诊部', anchor: Offset(0.4173, 0.4228)),
  CampusPlace(name: '刘湛恩烈士故居', anchor: Offset(0.4189, 0.4877)),
  CampusPlace(name: '光电大楼', anchor: Offset(0.4227, 0.3761)),
  CampusPlace(name: '图文信息中心', anchor: Offset(0.4324, 0.2572)),
  CampusPlace(name: '图书馆·档案馆', anchor: Offset(0.4324, 0.2617)),
  CampusPlace(name: '计算中心', anchor: Offset(0.4324, 0.2662)),
  CampusPlace(name: '经济管理实验中心', anchor: Offset(0.4429, 0.6512)),
  CampusPlace(name: '老干部办公室', anchor: Offset(0.4462, 0.4664)),
  CampusPlace(name: '基建处', anchor: Offset(0.4462, 0.4708)),
  CampusPlace(name: '大草坪', anchor: Offset(0.4458, 0.5482)),
  CampusPlace(name: '环境与建筑学院', anchor: Offset(0.4460, 0.6252)),
  CampusPlace(name: '保卫处·校园110', anchor: Offset(0.4480, 0.4026)),
  CampusPlace(name: '思孟堂（能动学院二办）', anchor: Offset(0.4482, 0.5860)),
  CampusPlace(name: '动力二馆', anchor: Offset(0.4489, 0.7419)),
  CampusPlace(name: '卓越楼', anchor: Offset(0.4656, 0.7832)),
  CampusPlace(name: '健康科学与工程学院', anchor: Offset(0.4656, 0.7921)),
  CampusPlace(name: '出版学院', anchor: Offset(0.4656, 0.7966)),
  CampusPlace(name: '勤业楼（行政楼）', anchor: Offset(0.4771, 0.3228)),
  CampusPlace(name: '系统楼（公共实验中心）', anchor: Offset(0.4840, 0.6368)),
  CampusPlace(name: '沪江文化园', anchor: Offset(0.4856, 0.5136)),
  CampusPlace(name: '菜鸟驿站', anchor: Offset(0.4862, 0.6964)),
  CampusPlace(name: '新专家楼', anchor: Offset(0.4876, 0.4677)),
  CampusPlace(name: '音乐堂', anchor: Offset(0.4929, 0.5993)),
  CampusPlace(name: '光子芯片研究院', anchor: Offset(0.4964, 0.4363)),
  CampusPlace(name: '招生办公室', anchor: Offset(0.5102, 0.4479)),
  CampusPlace(name: '第五学生公寓一号楼', anchor: Offset(0.5149, 0.7436)),
  CampusPlace(name: '第四学生公寓三号楼', anchor: Offset(0.5182, 0.2120)),
  CampusPlace(name: '沪江学院', anchor: Offset(0.5300, 0.5054)),
  CampusPlace(name: '第三教学楼', anchor: Offset(0.5447, 0.2905)),
  CampusPlace(name: '第一教学楼', anchor: Offset(0.5464, 0.5512)),
  CampusPlace(name: '第二学生公寓一号楼', anchor: Offset(0.5489, 0.6847)),
  CampusPlace(name: '第二食堂', anchor: Offset(0.5544, 0.3987)),
  CampusPlace(name: '思福堂', anchor: Offset(0.5636, 0.5026)),
  CampusPlace(name: '第四学生公寓二号楼', anchor: Offset(0.5653, 0.2314)),
  CampusPlace(name: '第五学生公寓二号楼', anchor: Offset(0.5696, 0.7198)),
  CampusPlace(name: '上海教育超市', anchor: Offset(0.5747, 0.7032)),
  CampusPlace(name: '学生发展中心', anchor: Offset(0.5853, 0.3082)),
  CampusPlace(name: '东堂（暖屋超市）', anchor: Offset(0.5856, 0.3585)),
  CampusPlace(name: '大礼堂', anchor: Offset(0.5864, 0.4607)),
  CampusPlace(name: '思晏堂', anchor: Offset(0.5911, 0.4086)),
  CampusPlace(name: '红塔（沪江大学水塔）', anchor: Offset(0.5927, 0.3921)),
  CampusPlace(name: '工会', anchor: Offset(0.5989, 0.3447)),
  CampusPlace(name: '小礼堂（沪江大学体育馆）', anchor: Offset(0.6000, 0.3759)),
  CampusPlace(name: '毛主席像广场', anchor: Offset(0.5998, 0.4867)),
  CampusPlace(name: '国合楼（中德国际学院）', anchor: Offset(0.6102, 0.8927)),
  CampusPlace(name: '第四学生公寓一号楼', anchor: Offset(0.6120, 0.2359)),
  CampusPlace(name: '北区运动场', anchor: Offset(0.6122, 0.5910)),
  CampusPlace(name: '南区第五学生宿舍', anchor: Offset(0.6124, 0.7323)),
  CampusPlace(name: '第四学生公寓四号楼', anchor: Offset(0.6133, 0.1938)),
  CampusPlace(name: '外语学院', anchor: Offset(0.6158, 0.9593)),
  CampusPlace(name: '灯光篮球场', anchor: Offset(0.6202, 0.5155)),
  CampusPlace(name: '第五学生公寓三号楼', anchor: Offset(0.6229, 0.7062)),
  CampusPlace(name: '教工之家', anchor: Offset(0.6233, 0.3346)),
  CampusPlace(name: '第二学生公寓二号楼', anchor: Offset(0.6291, 0.6561)),
  CampusPlace(name: '格致堂（沪江大学科学馆）', anchor: Offset(0.6324, 0.4557)),
  CampusPlace(name: '思裴堂（第三学生宿舍）', anchor: Offset(0.6382, 0.3779)),
  CampusPlace(name: '第三学生公寓一号楼', anchor: Offset(0.6393, 0.2559)),
  CampusPlace(name: '南区第四学生宿舍', anchor: Offset(0.6562, 0.7764)),
  CampusPlace(name: '南区体育馆', anchor: Offset(0.6564, 0.7871)),
  CampusPlace(name: '第九、十学生宿舍', anchor: Offset(0.6609, 0.3144)),
  CampusPlace(name: '老图书馆', anchor: Offset(0.6642, 0.4736)),
  CampusPlace(name: '怀德堂（第五学生宿舍）', anchor: Offset(0.6640, 0.5284)),
  CampusPlace(name: '分析测试中心·物性分析中心', anchor: Offset(0.6651, 0.4342)),
  CampusPlace(name: '第五学生公寓四号楼', anchor: Offset(0.6656, 0.6923)),
  CampusPlace(name: '创新创业中心', anchor: Offset(0.6671, 0.3297)),
  CampusPlace(name: '思餐厅', anchor: Offset(0.6716, 0.7342)),
  CampusPlace(name: '第五食堂', anchor: Offset(0.6729, 0.1703)),
  CampusPlace(name: '思伊堂（第四学生宿舍）', anchor: Offset(0.6738, 0.3563)),
  CampusPlace(name: '南区第二学生宿舍', anchor: Offset(0.6751, 0.8189)),
  CampusPlace(name: '南区第一学生宿舍', anchor: Offset(0.6762, 0.8407)),
  CampusPlace(name: '第三学生公寓二号楼', anchor: Offset(0.6782, 0.2665)),
  CampusPlace(name: '藏书楼', anchor: Offset(0.6784, 0.4830)),
  CampusPlace(name: '南区第九学生宿舍', anchor: Offset(0.6784, 0.8673)),
  CampusPlace(name: '大修中（原图未标楼名）', anchor: Offset(0.6804, 0.8966)),
  CampusPlace(name: '中德国际学院实验中心', anchor: Offset(0.6869, 0.7656)),
  CampusPlace(name: '第一食堂', anchor: Offset(0.6876, 0.3415)),
  CampusPlace(name: '第四教学楼（逸兴楼）', anchor: Offset(0.6878, 0.9735)),
  CampusPlace(name: '南区第三学生宿舍', anchor: Offset(0.6902, 0.7942)),
  CampusPlace(name: '沪江大学图书馆', anchor: Offset(0.6933, 0.4125)),
  CampusPlace(name: '第三学生公寓三号楼', anchor: Offset(0.6960, 0.2105)),
  CampusPlace(name: '分析测试中心·电镜影像分析中心（二）', anchor: Offset(0.7002, 0.4735)),
  CampusPlace(name: '艾德蒙堂（体育教学部）', anchor: Offset(0.7027, 0.5284)),
  CampusPlace(name: '第六学生公寓一号楼', anchor: Offset(0.7089, 0.6807)),
  CampusPlace(name: '第七学生宿舍', anchor: Offset(0.7122, 0.3290)),
  CampusPlace(name: '第二学生公寓三号楼', anchor: Offset(0.7127, 0.6305)),
  CampusPlace(name: '馥赉堂', anchor: Offset(0.7156, 0.4978)),
  CampusPlace(name: '南区浴室', anchor: Offset(0.7158, 0.7299)),
  CampusPlace(name: '仪表二馆（机械工程学院二号楼）', anchor: Offset(0.7244, 0.4378)),
  CampusPlace(name: '第一学生公寓北楼', anchor: Offset(0.7271, 0.3520)),
  CampusPlace(name: '体育健身中心', anchor: Offset(0.7300, 0.5690)),
  CampusPlace(name: '南区第十学生宿舍', anchor: Offset(0.7298, 0.7667)),
  CampusPlace(name: '第一学生公寓南楼', anchor: Offset(0.7398, 0.3822)),
  CampusPlace(name: '国际学生公寓二号楼', anchor: Offset(0.7433, 0.4622)),
  CampusPlace(name: '第十二学生宿舍', anchor: Offset(0.7482, 0.4899)),
  CampusPlace(name: '南区第八学生宿舍', anchor: Offset(0.7518, 0.7333)),
  CampusPlace(name: '北区浴室', anchor: Offset(0.7540, 0.4759)),
  CampusPlace(name: '南区第七学生宿舍', anchor: Offset(0.7538, 0.7550)),
  CampusPlace(name: '第十一学生宿舍', anchor: Offset(0.7560, 0.5118)),
  CampusPlace(name: '第六学生公寓二号楼', anchor: Offset(0.7569, 0.6682)),
  CampusPlace(name: '南区运动场', anchor: Offset(0.7578, 0.8262)),
  CampusPlace(name: '经管楼南楼', anchor: Offset(0.7596, 0.9434)),
  CampusPlace(name: '管理学院', anchor: Offset(0.7596, 0.9479)),
  CampusPlace(name: '第六学生公寓三号楼', anchor: Offset(0.7611, 0.7039)),
  CampusPlace(name: '理科实验中心', anchor: Offset(0.7611, 0.9794)),
  CampusPlace(name: '材料与化学学院', anchor: Offset(0.7611, 0.9839)),
  CampusPlace(name: '化学系', anchor: Offset(0.7611, 0.9884)),
  CampusPlace(name: '经管楼北楼', anchor: Offset(0.7642, 0.8940)),
  CampusPlace(name: '管理学院', anchor: Offset(0.7642, 0.8985)),
  CampusPlace(name: '马克思主义学院', anchor: Offset(0.7642, 0.9030)),
  CampusPlace(name: '南区图书馆', anchor: Offset(0.7642, 0.9075)),
  CampusPlace(name: '食品学院大楼', anchor: Offset(0.7991, 0.9649)),
  CampusPlace(name: '食品学院大楼辅楼', anchor: Offset(0.8033, 0.9407)),
  CampusPlace(name: '光电信息与计算机工程学院', anchor: Offset(0.4227, 0.3761)),
  CampusPlace(name: '智能科技学院', anchor: Offset(0.4227, 0.3761)),
  CampusPlace(name: '东方泛血管器械创新学院', anchor: Offset(0.5464, 0.5512)),
  CampusPlace(name: '教学楼（BCD区）', anchor: Offset(0.5464, 0.5512)),
  CampusPlace(name: '思雷堂', anchor: Offset(0.4116, 0.6080)),
];

/// 楼名/教室名别名（教务排课系统的各种写法）。
/// 需要补别名时直接往这里加，例如 '二公三': '第二学生公寓三号楼'。
const Map<String, String> kBuildingAliases = <String, String>{
  '第一教学楼': '第一教学楼',
  '一教': '第一教学楼',
  '第三教学楼': '第三教学楼',
  '三教': '第三教学楼',
  '第四教学楼': '第四教学楼（逸兴楼）',
  '四教': '第四教学楼（逸兴楼）',
  '卓越工程大楼': '卓越楼',
  '卓越楼': '卓越楼',
  '综合A': '综合楼',
  '综合楼A区': '综合楼',
  '综合B': '综合楼',
  '综合楼B区': '综合楼',
  '综合C': '综合楼',
  '综合楼C区': '综合楼',
  '综合D': '综合楼',
  '综合楼D区': '综合楼',
  '国合楼': '国合楼（中德国际学院）',
  '中德': '国合楼（中德国际学院）',
  // 教务课表写「公共实验楼」，地图上叫「系统楼（公共实验中心）」
  '公共实验楼': '系统楼（公共实验中心）',
  '公共实验中心': '系统楼（公共实验中心）',
  '二公一': '第二学生公寓一号楼',
  '二公二': '第二学生公寓二号楼',
  '二公三': '第二学生公寓三号楼',
  '第二公寓三号楼': '第二学生公寓三号楼',
  '三公一': '第三学生公寓一号楼',
};

String _aliasTarget(String input) {
  final r = input.trim();
  if (r.isEmpty) return r;
  final keys = kBuildingAliases.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (r == key || r.startsWith(key)) {
      return kBuildingAliases[key]!;
    }
  }
  return r;
}

CampusPlace? nearestPlace(Offset normalized, {double maxDistance = 0.06}) {
  CampusPlace? best;
  var bestD = maxDistance;
  for (final p in kCampusPlaces) {
    final d = (p.anchor - normalized).distance;
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
}

/// 把教务课表的教室名（如「三教106」「一教146」）解析成地图地点。
CampusPlace? placeForRoom(String room) {
  final raw = room.trim();
  if (raw.isEmpty) return null;
  // 先做别名归一化，例如 卓越工程大楼118 → 卓越楼118，综合A101 → 综合楼101
  final r = _aliasTarget(raw);

  CampusPlace? best;
  for (final p in kCampusPlaces) {
    if (p.name.length >= 2 && r.contains(p.name)) {
      if (best == null || p.name.length > best.name.length) best = p;
    }
  }
  if (best != null) return best;

  final m = RegExp(r'([一二三四五六七八九十])\s*教').firstMatch(r);
  if (m != null) {
    final full = '第${m.group(1)}教学楼';
    for (final p in kCampusPlaces) {
      if (p.name.contains(full)) return p;
    }
  }

  const keys = <String, String>{
    '图文': '图文信息中心',
    '图书馆': '图文信息中心',
    '综合楼': '综合楼',
    '大礼堂': '大礼堂',
    '体育': '体育健身中心',
    '经管': '经管楼',
    '管理': '管理学院',
    '卓越': '卓越楼',
    '国合': '国合楼',
    '中德': '国合楼',
    '外语': '外语学院',
  };
  for (final entry in keys.entries) {
    if (r.contains(entry.key)) {
      for (final p in kCampusPlaces) {
        if (p.name.contains(entry.value)) return p;
      }
    }
  }
  return null;
}
