import 'dart:convert';

import '../auth/cas_client.dart';
import 'classroom_data.dart';

/// 单个教室在某节次下的空闲与占用详情
class ClassroomInfo {
  const ClassroomInfo({
    required this.name,
    required this.building,
    required this.isFree,
    this.occupiedCourse = '',
    this.occupiedTeacher = '',
    this.timeRange = '',
  });

  final String name;
  final String building;
  final bool isFree;
  final String occupiedCourse;
  final String occupiedTeacher;
  final String timeRange;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'building': building,
    'isFree': isFree,
    'occupiedCourse': occupiedCourse,
    'occupiedTeacher': occupiedTeacher,
    'timeRange': timeRange,
  };

  static ClassroomInfo fromJson(Map<String, dynamic> json) => ClassroomInfo(
    name: json['name']?.toString() ?? '',
    building: json['building']?.toString() ?? '',
    isFree: json['isFree'] == true,
    occupiedCourse: json['occupiedCourse']?.toString() ?? '',
    occupiedTeacher: json['occupiedTeacher']?.toString() ?? '',
    timeRange: json['timeRange']?.toString() ?? '',
  );
}

/// 排课数据项（来自 lapp.usst.edu.cn 全校课表大数据库）
class LappScheduleItem {
  const LappScheduleItem({
    required this.id,
    required this.courseName,
    required this.teacherName,
    required this.dayOfWeek,
    required this.startPeriod,
    required this.periodLength,
    required this.classroom,
    required this.startWeek,
    required this.endWeek,
    required this.weeksText,
    required this.startTime,
    required this.endTime,
    this.courseCode = '',
    this.className = '',
    this.classCode = '',
    this.teacherCode = '',
    this.teacherTitle = '',
    this.college = '',
    this.credit = '',
    this.hours = '',
    this.courseType = '',
    this.classroomCode = '',
    this.academicYear = '',
    this.semester = '',
  });

  final String id;
  final String courseName;
  final String teacherName;
  final int dayOfWeek; // 1-7 (周一到周日)
  final int startPeriod; // 1..13
  final int periodLength; // 持续节数
  final String classroom;
  final int startWeek;
  final int endWeek;
  final String weeksText;
  final String startTime;
  final String endTime;
  final String courseCode;
  final String className;
  final String classCode;
  final String teacherCode;
  final String teacherTitle;
  final String college;
  final String credit;
  final String hours;
  final String courseType;
  final String classroomCode;
  final String academicYear;
  final String semester;

  /// 判断某门课程在目标教学周是否处于开课状态
  bool isActiveInWeek(int targetWeek) {
    if (targetWeek <= 0) return true;
    if (weeksText.isNotEmpty) {
      final parts = weeksText.split(',');
      final nums = <int>[];
      for (final p in parts) {
        final v = int.tryParse(p.trim());
        if (v != null) nums.add(v);
      }
      if (nums.isNotEmpty) {
        return nums.contains(targetWeek);
      }
    }
    if (startWeek >= 1 && startWeek <= 30 && endWeek >= startWeek) {
      return targetWeek >= startWeek && targetWeek <= endWeek;
    }
    return false;
  }

  /// 判断课程是否与指定查询节次发生重叠冲突
  bool matchesSection(int start, int end) {
    final cStart = startPeriod;
    final cEnd = periodLength > 0 ? startPeriod + periodLength - 1 : startPeriod;
    return (start <= cEnd) && (cStart <= end);
  }
}

/// 排课时间地点段
class CourseTimeSlot {
  const CourseTimeSlot({
    required this.dayOfWeek,
    required this.startPeriod,
    required this.periodLength,
    required this.classroom,
    required this.classroomCode,
    required this.weeksText,
    required this.startWeek,
    required this.endWeek,
    required this.startTime,
    required this.endTime,
  });

  final int dayOfWeek; // 1-7
  final int startPeriod; // 1-13
  final int periodLength;
  final String classroom;
  final String classroomCode;
  final String weeksText;
  final int startWeek;
  final int endWeek;
  final String startTime;
  final String endTime;

  String get dayOfWeekName {
    switch (dayOfWeek) {
      case 1:
        return '周一';
      case 2:
        return '周二';
      case 3:
        return '周三';
      case 4:
        return '周四';
      case 5:
        return '周五';
      case 6:
        return '周六';
      case 7:
        return '周日';
      default:
        return '周$dayOfWeek';
    }
  }

  String get sectionDesc {
    if (periodLength > 1) {
      return '第$startPeriod-${startPeriod + periodLength - 1}节';
    }
    return '第$startPeriod节';
  }

  String get timeRangeDesc {
    if (startTime.isNotEmpty && endTime.isNotEmpty) {
      return '$startTime-$endTime';
    }
    return '';
  }

  bool isActiveInWeek(int week) {
    if (week <= 0) return true;
    if (weeksText.isNotEmpty) {
      final parts = weeksText.split(',');
      for (final p in parts) {
        if (int.tryParse(p.trim()) == week) return true;
      }
    }
    if (startWeek >= 1 && endWeek >= startWeek) {
      return week >= startWeek && week <= endWeek;
    }
    return false;
  }
}

/// 全校课程实体（以班级 bjdm 或课程+教师为单位聚合）
class SchoolCourse {
  const SchoolCourse({
    required this.courseCode,
    required this.courseName,
    required this.className,
    required this.classCode,
    required this.teacherName,
    required this.teacherCode,
    required this.teacherTitle,
    required this.college,
    required this.credit,
    required this.hours,
    required this.courseType,
    required this.academicYear,
    required this.semester,
    required this.slots,
  });

  final String courseCode;
  final String courseName;
  final String className;
  final String classCode;
  final String teacherName;
  final String teacherCode;
  final String teacherTitle;
  final String college;
  final String credit;
  final String hours;
  final String courseType;
  final String academicYear;
  final String semester;
  final List<CourseTimeSlot> slots;

  /// 是否为研究生课程
  bool get isGraduate {
    final text = className.isNotEmpty ? className : classCode;
    return text.contains('-26271-') ||
        (text.endsWith('班') && !text.startsWith('(')) ||
        RegExp(r'^\d{6,10}-\d{4,6}-.+班$').hasMatch(text.trim());
  }

  /// 是否为本科生课程
  bool get isUndergraduate => !isGraduate;

  /// 格式化教师展示（含职称）
  String get teacherDisplay {
    if (teacherTitle.isNotEmpty && teacherTitle != '无') {
      return '$teacherName ($teacherTitle)';
    }
    return teacherName.isNotEmpty ? teacherName : '待定';
  }

  /// 格式化学分学时
  String get creditHoursDisplay {
    final parts = <String>[];
    if (credit.isNotEmpty) parts.add('$credit 学分');
    if (hours.isNotEmpty) parts.add('$hours 学时');
    return parts.join(' · ');
  }
}

/// 节次预设选项
class SectionOption {
  const SectionOption({
    required this.label,
    required this.queryJc,
    required this.range,
  });

  final String label;
  final String queryJc;
  final (int, int)? range;
}

const List<SectionOption> defaultSectionOptions = <SectionOption>[
  SectionOption(label: '1-2节 (08:00-09:25)', queryJc: '1-2', range: (1, 2)),
  SectionOption(label: '3-5节 (09:45-11:55)', queryJc: '3-5', range: (3, 5)),
  SectionOption(label: '6-7节 (13:00-14:25)', queryJc: '6-7', range: (6, 7)),
  SectionOption(label: '8-10节 (14:45-16:55)', queryJc: '8-9', range: (8, 10)),
  SectionOption(label: '11-13节 (18:00-20:15)', queryJc: '10-12', range: (11, 13)),
  SectionOption(label: '全部节次', queryJc: '-1', range: null),
];

/// 教室查询与全校课表 API（对接 lapp.usst.edu.cn 全校课表库）
class ClassroomApi {
  ClassroomApi(this.client);

  final CasClient client;

  static const String _lappBase = 'https://lapp.usst.edu.cn';
  static const String _entryUrl =
      '$_lappBase/_web/_customizes/usst/schoolTimetable/mobile/permit/pc/pub/index.html';
  static const String _scheduleUrl =
      '$_lappBase/_web/_lightapp/schedule/mobile/school/queryClassSchedule.rst';

  /// 缓存排课数据，避免重复请求
  static final Map<String, List<LappScheduleItem>> _cache =
      <String, List<LappScheduleItem>>{};

  /// 预设学院列表
  static const List<String> defaultColleges = <String>[
    '光电信息与计算机工程学院',
    '能源与动力工程学院',
    '管理学院',
    '机械工程学院',
    '材料与化学学院',
    '环境与建筑学院',
    '健康科学与工程学院',
    '理学院',
    '外语学院',
    '马克思主义学院',
    '体育教学部',
    '中英国际学院',
    '中德国际学院',
    '卓越工程师学院',
    '创新创业学院',
  ];

  /// 确保获取到 lapp.usst.edu.cn 的已登录 SSO 会话
  Future<bool> ensureSession() async {
    try {
      final resp = await client.getApi(
        Uri.parse(_entryUrl),
        headers: const <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取学院列表
  Future<List<String>> fetchColleges() async {
    try {
      await ensureSession();
      final uri = Uri.parse(
        '$_lappBase/_web/_lightapp/schedule/mobile/school/queryClassXy.rst',
      );
      final resp = await client.getApi(
        uri,
        headers: const <String, String>{
          'Referer': _entryUrl,
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );
      if (resp.statusCode == 200 && resp.data != null) {
        final json = jsonDecode(resp.data!) as Map<String, dynamic>;
        final data = json['result']?['data'] as List<dynamic>?;
        if (data != null && data.isNotEmpty) {
          final list = <String>[];
          for (final item in data) {
            final xy = (item as Map<String, dynamic>)['xy']?.toString().trim() ?? '';
            if (xy.isNotEmpty && !list.contains(xy)) {
              list.add(xy);
            }
          }
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}
    return defaultColleges;
  }

  /// 获取全校排课项
  Future<List<LappScheduleItem>> fetchSchedule({
    String xn = '',
    String xq = '',
    int week = -1,
    int zj = -1,
    String jc = '-1',
    String kcmc = '',
    String kcdm = '',
    String lsmc = '',
    String college = '',
    int page = 0,
    int rows = 1000,
    bool forceRefresh = false,
  }) async {
    final cacheKey =
        '$xn|$xq|$week|$zj|$jc|$kcmc|$kcdm|$lsmc|$college|$page|$rows';
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    await ensureSession();

    final queryMap = <String, String>{
      'week': week.toString(),
      'zj': zj.toString(),
      'jc': jc,
      'page': page.toString(),
      'rows': rows.toString(),
    };
    if (xn.isNotEmpty) queryMap['xn'] = xn;
    if (xq.isNotEmpty) queryMap['xq'] = xq;
    if (kcmc.isNotEmpty) queryMap['kcmc'] = kcmc;
    if (kcdm.isNotEmpty) queryMap['kcdm'] = kcdm;
    if (lsmc.isNotEmpty) queryMap['lsmc'] = lsmc;
    if (college.isNotEmpty) queryMap['xy'] = college;

    final uri = Uri.parse(_scheduleUrl).replace(queryParameters: queryMap);

    final resp = await client.getApi(
      uri,
      headers: const <String, String>{
        'Referer': _entryUrl,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    final raw = resp.data ?? '';
    if (!raw.trim().startsWith('{')) {
      return const <LappScheduleItem>[];
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const <LappScheduleItem>[];
    }

    if (json['resultCode'] != 0) {
      return const <LappScheduleItem>[];
    }

    final result = json['result'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final data = result['data'] as List<dynamic>? ?? <dynamic>[];

    final list = <LappScheduleItem>[];
    for (final item in data) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      list.add(
        LappScheduleItem(
          id: (m['id'] ?? '').toString(),
          courseName: (m['kcmc'] ?? '').toString().trim(),
          teacherName: (m['lsmc'] ?? '').toString().trim(),
          dayOfWeek: (m['zj'] as num?)?.toInt() ?? 1,
          startPeriod: (m['jc'] as num?)?.toInt() ?? 1,
          periodLength: (m['jccd'] as num?)?.toInt() ?? 2,
          classroom: (m['jsdd'] ?? '').toString().trim(),
          startWeek: (m['qsz'] as num?)?.toInt() ?? 1,
          endWeek: (m['jsz'] as num?)?.toInt() ?? 18,
          weeksText: (m['zc'] ?? '').toString().trim(),
          startTime: (m['classTimeBegin'] ?? '').toString().trim(),
          endTime: (m['classTimeEnd'] ?? '').toString().trim(),
          courseCode: (m['kcdm'] ?? '').toString().trim(),
          className: (m['bjmc'] ?? '').toString().trim(),
          classCode: (m['bjdm'] ?? '').toString().trim(),
          teacherCode: (m['lsgh'] ?? '').toString().trim(),
          teacherTitle: (m['lszc'] ?? '').toString().trim(),
          college: (m['xy'] ?? '').toString().trim(),
          credit: (m['xf'] ?? '').toString().trim(),
          hours: (m['xs'] ?? '').toString().trim(),
          courseType: (m['kclx'] ?? '').toString().trim(),
          classroomCode: (m['jsbh'] ?? '').toString().trim(),
          academicYear: (m['xn'] ?? '').toString().trim(),
          semester: (m['xq'] ?? '').toString().trim(),
        ),
      );
    }

    _cache[cacheKey] = list;
    return list;
  }

  /// 查询全校课程（支持课程名、教师名、课程代码及学院筛选），聚合为 SchoolCourse
  Future<List<SchoolCourse>> queryCourses({
    String keyword = '',
    String college = '',
    int week = -1,
    int dayOfWeek = -1,
    String section = '-1',
    String xn = '',
    String xq = '',
    bool forceRefresh = false,
  }) async {
    final trimmedKeyword = keyword.trim();
    final tasks = <Future<List<LappScheduleItem>>>[];

    if (trimmedKeyword.isNotEmpty) {
      final isCode = RegExp(r'^\d{8}$').hasMatch(trimmedKeyword);
      if (isCode) {
        tasks.add(
          fetchSchedule(
            xn: xn,
            xq: xq,
            week: week,
            zj: dayOfWeek,
            jc: section,
            kcdm: trimmedKeyword,
            college: college,
            forceRefresh: forceRefresh,
          ),
        );
      } else {
        tasks.add(
          fetchSchedule(
            xn: xn,
            xq: xq,
            week: week,
            zj: dayOfWeek,
            jc: section,
            kcmc: trimmedKeyword,
            college: college,
            forceRefresh: forceRefresh,
          ),
        );
        tasks.add(
          fetchSchedule(
            xn: xn,
            xq: xq,
            week: week,
            zj: dayOfWeek,
            jc: section,
            lsmc: trimmedKeyword,
            college: college,
            forceRefresh: forceRefresh,
          ),
        );
      }
    } else {
      tasks.add(
        fetchSchedule(
          xn: xn,
          xq: xq,
          week: week,
          zj: dayOfWeek,
          jc: section,
          college: college,
          forceRefresh: forceRefresh,
        ),
      );
    }

    final results = await Future.wait(tasks);
    final seenIds = <String>{};
    final combined = <LappScheduleItem>[];
    for (final list in results) {
      for (final item in list) {
        if (seenIds.add(item.id)) {
          combined.add(item);
        }
      }
    }

    return groupIntoSchoolCourses(combined);
  }

  /// 将扁平的排课记录按教学班聚合为 SchoolCourse
  static List<SchoolCourse> groupIntoSchoolCourses(List<LappScheduleItem> items) {
    final map = <String, List<LappScheduleItem>>{};
    for (final item in items) {
      final key = item.classCode.isNotEmpty
          ? item.classCode
          : '${item.courseCode}_${item.teacherName}_${item.className}';
      map.putIfAbsent(key, () => <LappScheduleItem>[]).add(item);
    }

    final courses = <SchoolCourse>[];
    for (final entry in map.entries) {
      final group = entry.value;
      if (group.isEmpty) continue;
      final first = group.first;

      final slots = <CourseTimeSlot>[];
      final seenSlotKeys = <String>{};
      for (final item in group) {
        final slotKey =
            '${item.dayOfWeek}_${item.startPeriod}_${item.periodLength}_${item.classroom}_${item.weeksText}';
        if (seenSlotKeys.add(slotKey)) {
          slots.add(
            CourseTimeSlot(
              dayOfWeek: item.dayOfWeek,
              startPeriod: item.startPeriod,
              periodLength: item.periodLength,
              classroom: item.classroom,
              classroomCode: item.classroomCode,
              weeksText: item.weeksText,
              startWeek: item.startWeek,
              endWeek: item.endWeek,
              startTime: item.startTime,
              endTime: item.endTime,
            ),
          );
        }
      }

      slots.sort((a, b) {
        final cmpDay = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (cmpDay != 0) return cmpDay;
        return a.startPeriod.compareTo(b.startPeriod);
      });

      courses.add(
        SchoolCourse(
          courseCode: first.courseCode,
          courseName: first.courseName,
          className: first.className,
          classCode: first.classCode,
          teacherName: first.teacherName,
          teacherCode: first.teacherCode,
          teacherTitle: first.teacherTitle,
          college: first.college,
          credit: first.credit,
          hours: first.hours,
          courseType: first.courseType,
          academicYear: first.academicYear,
          semester: first.semester,
          slots: slots,
        ),
      );
    }

    courses.sort((a, b) => a.courseName.compareTo(b.courseName));
    return courses;
  }

  /// 计算指定楼栋、周次、星期、节次范围下的教室空闲与占用情况
  Future<List<ClassroomInfo>> queryClassrooms({
    required String building,
    required int week,
    required int dayOfWeek,
    required (int, int)? sectionRange,
    String queryJc = '1-2',
    String xn = '',
    String xq = '',
    bool forceRefresh = false,
  }) async {
    final schedule = await fetchSchedule(
      xn: xn,
      xq: xq,
      week: week,
      zj: dayOfWeek,
      jc: queryJc,
      forceRefresh: forceRefresh,
    );

    // 记录发生占用的教室
    final occupiedMap = <String, LappScheduleItem>{};
    for (final item in schedule) {
      if (item.classroom.isEmpty) continue;
      if (dayOfWeek > 0 && item.dayOfWeek != dayOfWeek) continue;
      if (!item.isActiveInWeek(week)) continue;
      if (sectionRange != null &&
          !item.matchesSection(sectionRange.$1, sectionRange.$2)) {
        continue;
      }
      occupiedMap[item.classroom] = item;
      occupiedMap[normalizeClassroomName(item.classroom)] = item;
    }

    // 确定查询的楼栋范围
    final targetBuildings = <String>[];
    if (building == '全部教学楼' || building.isEmpty) {
      targetBuildings.addAll(knownClassroomsByBuilding.keys);
    } else {
      for (final k in knownClassroomsByBuilding.keys) {
        if (k.contains(building) || building.contains(k)) {
          targetBuildings.add(k);
        }
      }
      if (targetBuildings.isEmpty) {
        targetBuildings.add(building);
      }
    }

    final out = <ClassroomInfo>[];
    for (final b in targetBuildings) {
      final rooms = knownClassroomsByBuilding[b] ?? const <String>[];
      for (final room in rooms) {
        final occupied =
            occupiedMap[room] ?? occupiedMap[normalizeClassroomName(room)];
        if (occupied != null) {
          final timeStr = occupied.startTime.isNotEmpty &&
                  occupied.endTime.isNotEmpty
              ? '${occupied.startTime}-${occupied.endTime}'
              : '第 ${occupied.startPeriod}-${occupied.startPeriod + occupied.periodLength - 1} 节';
          out.add(
            ClassroomInfo(
              name: room,
              building: b,
              isFree: false,
              occupiedCourse: occupied.courseName,
              occupiedTeacher: occupied.teacherName,
              timeRange: timeStr,
            ),
          );
        } else {
          out.add(
            ClassroomInfo(
              name: room,
              building: b,
              isFree: true,
            ),
          );
        }
      }
    }

    return out;
  }
}
