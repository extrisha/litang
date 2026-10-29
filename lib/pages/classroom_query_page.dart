import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/calendar/calendar_service.dart';
import '../data/jwc/classroom_api.dart';
import '../data/jwc/classroom_data.dart';
import 'simple_web_page.dart';

/// 教室查询与全校排课一览页（双 Tab：空教室检索 + 全校课表检索）
class ClassroomQueryPage extends StatefulWidget {
  const ClassroomQueryPage({super.key});

  @override
  State<ClassroomQueryPage> createState() => _ClassroomQueryPageState();
}

class _ClassroomQueryPageState extends State<ClassroomQueryPage> {
  // === Tab 1: 空教室状态 ===
  String _selectedBuilding = '全部教学楼';
  int _selectedWeek = 1;
  int _selectedDay = 1; // 1-7
  int _selectedSectionIndex = 0;
  bool _onlyFree = true;
  String _classroomKeyword = '';

  bool _classroomLoading = false;
  String? _classroomError;
  List<ClassroomInfo> _allRooms = const <ClassroomInfo>[];
  final TextEditingController _classroomSearchController = TextEditingController();

  // === Tab 2: 全校课表状态 ===
  final TextEditingController _courseSearchController = TextEditingController();
  bool _courseLoading = false;
  bool _courseSearched = false;
  String? _courseError;
  List<SchoolCourse> _schoolCourses = const <SchoolCourse>[];
  List<String> _colleges = ClassroomApi.defaultColleges;

  String _selectedCollege = '全部学院';
  String _selectedLevel = 'ALL'; // 'ALL', 'UNDERGRADUATE', 'GRADUATE'
  int _selectedCourseDay = -1; // -1: 全部, 1-7
  int _selectedCourseWeek = -1; // -1: 全部, 0: 当前周, 1-20

  static const List<({String name, int day})> _days = <({String name, int day})>[
    (name: '周一', day: 1),
    (name: '周二', day: 2),
    (name: '周三', day: 3),
    (name: '周四', day: 4),
    (name: '周五', day: 5),
    (name: '周六', day: 6),
    (name: '周日', day: 7),
  ];

  @override
  void initState() {
    super.initState();
    _initDefaults();
    _classroomSearchController.addListener(() {
      setState(() {
        _classroomKeyword = _classroomSearchController.text.trim();
      });
    });
    _loadClassrooms();
    _loadColleges();
  }

  @override
  void dispose() {
    _classroomSearchController.dispose();
    _courseSearchController.dispose();
    super.dispose();
  }

  void _initDefaults() {
    final now = DateTime.now();

    // 默认周次
    final currentWeek = CalendarService.instance.currentWeek ?? 1;
    _selectedWeek = currentWeek.clamp(1, 20);

    // 默认星期
    _selectedDay = now.weekday;

    // 默认时段
    final hour = now.hour;
    if (hour < 10) {
      _selectedSectionIndex = 0; // 1-2节
    } else if (hour < 12) {
      _selectedSectionIndex = 1; // 3-5节
    } else if (hour < 15) {
      _selectedSectionIndex = 2; // 6-7节
    } else if (hour < 17) {
      _selectedSectionIndex = 3; // 8-10节
    } else {
      _selectedSectionIndex = 4; // 11-13节
    }
  }

  Future<void> _loadColleges() async {
    final client = JwglAuth.instance.client;
    if (client == null) return;
    final api = ClassroomApi(client);
    final res = await api.fetchColleges();
    if (mounted && res.isNotEmpty) {
      setState(() {
        _colleges = res;
      });
    }
  }

  Future<void> _loadClassrooms({bool forceRefresh = false}) async {
    setState(() {
      _classroomLoading = true;
      _classroomError = null;
    });

    final client = JwglAuth.instance.client;
    if (client == null) {
      // 未登录时，至少展示静态教室列表
      final rooms = <ClassroomInfo>[];
      final targetBuildings = _selectedBuilding == '全部教学楼'
          ? knownClassroomsByBuilding.keys
          : <String>[_selectedBuilding];
      for (final b in targetBuildings) {
        for (final r in knownClassroomsByBuilding[b] ?? const <String>[]) {
          rooms.add(ClassroomInfo(name: r, building: b, isFree: true));
        }
      }
      setState(() {
        _allRooms = rooms;
        _classroomLoading = false;
      });
      return;
    }

    try {
      final api = ClassroomApi(client);
      final opt = defaultSectionOptions[_selectedSectionIndex];
      final termId = CalendarService.instance.termId;
      String xn = '';
      String xq = '';
      if (termId.contains('-')) {
        final lastIdx = termId.lastIndexOf('-');
        xn = termId.substring(0, lastIdx);
        xq = termId.substring(lastIdx + 1);
      }

      final result = await api.queryClassrooms(
        building: _selectedBuilding,
        week: _selectedWeek,
        dayOfWeek: _selectedDay,
        sectionRange: opt.range,
        queryJc: opt.queryJc,
        xn: xn,
        xq: xq,
        forceRefresh: forceRefresh,
      );

      setState(() {
        _allRooms = result;
        _classroomLoading = false;
      });
    } catch (e) {
      setState(() {
        _classroomError = '教室数据加载失败：$e';
        _classroomLoading = false;
      });
    }
  }

  Future<void> _searchSchoolCourses({bool forceRefresh = false}) async {
    final keyword = _courseSearchController.text.trim();
    if (keyword.isEmpty && _selectedCollege == '全部学院') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入课程名、老师姓名、课程代码，或选择一个开课学院'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _courseLoading = true;
      _courseError = null;
      _courseSearched = true;
    });

    final client = JwglAuth.instance.client;
    if (client == null) {
      setState(() {
        _courseError = '请先登录统一身份认证后查询全校排课';
        _courseLoading = false;
      });
      return;
    }

    try {
      final api = ClassroomApi(client);
      final termId = CalendarService.instance.termId;
      String xn = '';
      String xq = '';
      if (termId.contains('-')) {
        final lastIdx = termId.lastIndexOf('-');
        xn = termId.substring(0, lastIdx);
        xq = termId.substring(lastIdx + 1);
      }
      final collegeArg = _selectedCollege == '全部学院' ? '' : _selectedCollege;

      final courses = await api.queryCourses(
        keyword: keyword,
        college: collegeArg,
        xn: xn,
        xq: xq,
        forceRefresh: forceRefresh,
      );

      setState(() {
        _schoolCourses = courses;
        _courseLoading = false;
      });
    } catch (e) {
      setState(() {
        _courseError = '全校排课查询失败：$e';
        _courseLoading = false;
      });
    }
  }

  List<ClassroomInfo> get _filteredClassrooms {
    return _allRooms.where((room) {
      if (_onlyFree && !room.isFree) return false;
      if (_classroomKeyword.isNotEmpty) {
        final kw = _classroomKeyword.toLowerCase();
        final matchName = room.name.toLowerCase().contains(kw);
        final matchCourse = room.occupiedCourse.toLowerCase().contains(kw);
        final matchTeacher = room.occupiedTeacher.toLowerCase().contains(kw);
        if (!matchName && !matchCourse && !matchTeacher) return false;
      }
      return true;
    }).toList();
  }

  List<SchoolCourse> get _filteredCourses {
    final currentWeek = CalendarService.instance.currentWeek ?? 1;

    return _schoolCourses.where((c) {
      // 1. 本研筛选
      if (_selectedLevel == 'UNDERGRADUATE' && !c.isUndergraduate) return false;
      if (_selectedLevel == 'GRADUATE' && !c.isGraduate) return false;

      // 2. 学院筛选 (若搜索时已带学院参数，前端进一步保障)
      if (_selectedCollege != '全部学院' && c.college != _selectedCollege) {
        return false;
      }

      // 3. 星期筛选
      if (_selectedCourseDay > 0) {
        final hasDay = c.slots.any((s) => s.dayOfWeek == _selectedCourseDay);
        if (!hasDay) return false;
      }

      // 4. 周次筛选
      if (_selectedCourseWeek == 0) {
        // 仅看当前教学周
        final hasWeek = c.slots.any((s) => s.isActiveInWeek(currentWeek));
        if (!hasWeek) return false;
      } else if (_selectedCourseWeek > 0) {
        final hasWeek = c.slots.any((s) => s.isActiveInWeek(_selectedCourseWeek));
        if (!hasWeek) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('教室与排课'),
          actions: <Widget>[
            IconButton(
              tooltip: '原网页课表',
              icon: const Icon(Icons.language_outlined, size: 20),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SimpleWebPage(
                      title: '全校排课查询',
                      url:
                          'https://lapp.usst.edu.cn/_web/_customizes/usst/schoolTimetable/mobile/permit/pc/pub/index.html',
                    ),
                  ),
                );
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: AppColors.usstRed,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.usstRed,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle:
                TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
            tabs: <Widget>[
              Tab(
                icon: Icon(Icons.meeting_room_outlined, size: 20),
                text: '空教室',
              ),
              Tab(
                icon: Icon(Icons.calendar_view_week_outlined, size: 20),
                text: '全校课表',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _buildClassroomTab(),
            _buildCourseScheduleTab(),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 1: 空教室
  // =========================================================================

  Widget _buildClassroomTab() {
    final filtered = _filteredClassrooms;
    final total = _allRooms.length;
    final freeCount = _allRooms.where((r) => r.isFree).length;

    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _loadClassrooms(forceRefresh: true),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildClassroomFilterHeader(),
                _buildClassroomSummary(total, freeCount),
              ],
            ),
          ),
          if (_classroomLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.usstRed),
              ),
            )
          else if (_classroomError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(Icons.error_outline,
                          color: AppColors.textSecondary, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _classroomError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.usstRed,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _loadClassrooms(forceRefresh: true),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (filtered.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.inbox_outlined,
                        color: AppColors.textSecondary, size: 48),
                    SizedBox(height: 12),
                    Text(
                      '没有找到匹配的教室',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildClassroomCard(filtered[i]),
                  childCount: filtered.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  String get _displayBuilding {
    if (_selectedBuilding == '全部教学楼') return '全部楼栋';
    return _selectedBuilding
        .replaceAll('第一教学楼', '一教')
        .replaceAll('第三教学楼', '三教')
        .replaceAll('第四教学楼', '四教');
  }

  String get _displaySection {
    final opt = defaultSectionOptions[_selectedSectionIndex];
    return opt.label;
  }

  bool get _isDateFiltered {
    final now = DateTime.now();
    final currentWeek = CalendarService.instance.currentWeek ?? 1;
    return _selectedWeek != currentWeek || _selectedDay != now.weekday;
  }

  Widget _buildFilterPill({
    required IconData icon,
    required String label,
    required bool isFiltered,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isFiltered ? const Color(0xFFFEF2F2) : const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFiltered ? const Color(0xFFFECACA) : const Color(0xFFE5E7EB),
                width: isFiltered ? 1 : 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 14,
                  color: isFiltered ? AppColors.usstRed : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isFiltered ? FontWeight.bold : FontWeight.w500,
                      color: isFiltered ? AppColors.usstRed : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: isFiltered ? AppColors.usstRed : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassroomFilterHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: <Widget>[
          // Top Row: 搜索框 + "仅看空闲" 切换胶囊
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.search, size: 17, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _classroomSearchController,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: '搜索教室名或占用课程',
                            hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_classroomKeyword.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _classroomSearchController.clear();
                          },
                          child: const Icon(Icons.cancel, size: 16, color: Color(0xFF9CA3AF)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // "仅看空闲" 切换胶囊
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _onlyFree = !_onlyFree),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _onlyFree ? const Color(0xFFECFDF5) : const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _onlyFree ? const Color(0xFFA7F3D0) : const Color(0xFFE5E7EB),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _onlyFree ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        size: 15,
                        color: _onlyFree ? const Color(0xFF059669) : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '仅看空闲',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _onlyFree ? FontWeight.bold : FontWeight.normal,
                          color: _onlyFree ? const Color(0xFF059669) : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom Row: 3 个并排简洁优雅筛选胶囊 (楼栋 / 节次 / 周次星期)
          Row(
            children: <Widget>[
              _buildFilterPill(
                icon: Icons.apartment_outlined,
                label: _displayBuilding,
                isFiltered: _selectedBuilding != '全部教学楼',
                onTap: _showBuildingPickerModal,
              ),
              const SizedBox(width: 8),
              _buildFilterPill(
                icon: Icons.schedule_outlined,
                label: _displaySection,
                isFiltered: _selectedSectionIndex != 0,
                onTap: _showSectionPickerModal,
              ),
              const SizedBox(width: 8),
              _buildFilterPill(
                icon: Icons.calendar_today_outlined,
                label: '第$_selectedWeek周·${_days[_selectedDay - 1].name}',
                isFiltered: _isDateFiltered,
                onTap: _showDatePickerModal,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClassroomSummary(int total, int freeCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              children: <TextSpan>[
                const TextSpan(text: '检索统计：'),
                TextSpan(
                  text: '$freeCount ',
                  style: const TextStyle(
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(text: '间空闲 / 共 '),
                TextSpan(
                  text: '$total ',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: '间教室'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBuildingPickerModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        '选择教学楼',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.6, color: Color(0xFFF3F4F6)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: allKnownBuildings.map((b) {
                      final isSelected = _selectedBuilding == b;
                      final displayName = b == '全部教学楼'
                          ? '全部教学楼'
                          : b
                              .replaceAll('第一教学楼', '一教')
                              .replaceAll('第三教学楼', '三教')
                              .replaceAll('第四教学楼', '四教');
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          if (_selectedBuilding != b) {
                            setState(() => _selectedBuilding = b);
                            _loadClassrooms();
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFEF2F2) : const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.usstRed : const Color(0xFFE5E7EB),
                              width: isSelected ? 1.4 : 0.8,
                            ),
                          ),
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSectionPickerModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        '选择时段节次',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.6, color: Color(0xFFF3F4F6)),
                ...List<Widget>.generate(defaultSectionOptions.length, (i) {
                  final opt = defaultSectionOptions[i];
                  final isSelected = _selectedSectionIndex == i;
                  return InkWell(
                    onTap: () {
                      if (_selectedSectionIndex != i) {
                        setState(() => _selectedSectionIndex = i);
                        _loadClassrooms();
                      }
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent,
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.6),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 18,
                            color: isSelected ? AppColors.usstRed : const Color(0xFFD1D5DB),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  opt.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                                  ),
                                ),
                                if (opt.range != null) ...<Widget>[
                                  const SizedBox(height: 2),
                                  Text(
                                    _getSectionTimeDesc(opt),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isSelected
                                          ? AppColors.usstRed.withValues(alpha: 0.8)
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getSectionTimeDesc(SectionOption opt) {
    switch (opt.label) {
      case '1-2节 (上午)':
        return '08:00 - 09:35 · 上午第1大节';
      case '3-5节 (上午)':
        return '09:55 - 12:20 · 上午第2大节';
      case '6-7节 (下午)':
        return '13:30 - 15:05 · 下午第1大节';
      case '8-10节 (下午)':
        return '15:25 - 17:50 · 下午第2大节';
      case '11-13节 (晚上)':
        return '18:30 - 20:55 · 晚间课程';
      default:
        return '全天课表及教室占用';
    }
  }

  void _showDatePickerModal() {
    final currentWeek = CalendarService.instance.currentWeek ?? 1;
    final nowWeekday = DateTime.now().weekday;

    int tempWeek = _selectedWeek;
    int tempDay = _selectedDay;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1D5DB),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          const Text(
                            '选择周次与星期',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.usstRed,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: const Icon(Icons.restore, size: 16),
                            label: const Text('今天与当前周', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              setModalState(() {
                                tempWeek = currentWeek.clamp(1, 20);
                                tempDay = nowWeekday;
                              });
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 16, thickness: 0.6),
                      const Text(
                        '教学周',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: 20,
                          itemBuilder: (context, i) {
                            final w = i + 1;
                            final isSel = tempWeek == w;
                            final isCur = w == currentWeek;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  isCur ? '第$w周(本周)' : '第$w周',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                    color: isSel ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                                selected: isSel,
                                selectedColor: AppColors.usstRed,
                                backgroundColor: const Color(0xFFF3F4F6),
                                showCheckmark: false,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSel ? AppColors.usstRed : Colors.transparent,
                                  ),
                                ),
                                onSelected: (_) {
                                  setModalState(() => tempWeek = w);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '星期',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: _days.map((d) {
                          final isSel = tempDay == d.day;
                          final isToday = d.day == nowWeekday;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setModalState(() => tempDay = d.day),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? AppColors.usstRed
                                        : (isToday ? const Color(0xFFFEF2F2) : const Color(0xFFF7F8FA)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSel
                                          ? AppColors.usstRed
                                          : (isToday ? const Color(0xFFFECACA) : const Color(0xFFE5E7EB)),
                                      width: isSel ? 1.2 : 0.8,
                                    ),
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      Text(
                                        d.name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              (isSel || isToday) ? FontWeight.bold : FontWeight.normal,
                                          color: isSel
                                              ? Colors.white
                                              : (isToday ? AppColors.usstRed : AppColors.textPrimary),
                                        ),
                                      ),
                                      if (isToday)
                                        Text(
                                          '今天',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            color: isSel ? Colors.white70 : AppColors.usstRed,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.usstRed,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedWeek = tempWeek;
                              _selectedDay = tempDay;
                            });
                            _loadClassrooms();
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('确定',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClassroomCard(ClassroomInfo room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: room.isFree
              ? const Color(0xFFBBF7D0)
              : const Color(0xFFE5E7EB),
          width: room.isFree ? 1 : 0.8,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: room.isFree
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              room.isFree ? Icons.meeting_room_outlined : Icons.lock_clock_outlined,
              size: 20,
              color: room.isFree ? const Color(0xFF16A34A) : AppColors.usstRed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        room.building,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (room.isFree)
                  const Text(
                    '当前时段空闲 · 可自习',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Text(
                    '占用：${room.occupiedCourse} (${room.occupiedTeacher}) · ${room.timeRange}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.usstRed,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: room.isFree
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              room.isFree ? '可自习' : '有课',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: room.isFree
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB91C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 2: 全校课表
  // =========================================================================

  Widget _buildCourseScheduleTab() {
    final filtered = _filteredCourses;
    final currentWeek = CalendarService.instance.currentWeek ?? 1;

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildCourseSearchBar(),
              _buildCourseFiltersRow(currentWeek),
              if (_courseSearched) _buildCourseSearchSummary(filtered.length),
            ],
          ),
        ),
        if (_courseLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  CircularProgressIndicator(color: AppColors.usstRed),
                  SizedBox(height: 16),
                  Text(
                    '正在查询全校排课库...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else if (_courseError != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.error_outline,
                        color: AppColors.textSecondary, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _courseError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.usstRed,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _searchSchoolCourses(forceRefresh: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (!_courseSearched)
          SliverToBoxAdapter(
            child: _buildCourseInitialGuide(),
          )
        else if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.search_off_outlined,
                      color: AppColors.textSecondary, size: 48),
                  SizedBox(height: 12),
                  Text(
                    '未找到符合条件的课程排课',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '请尝试更换关键词、学院或放宽筛选条件',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildSchoolCourseCard(filtered[i], currentWeek),
                childCount: filtered.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildCourseSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _courseSearchController,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '搜索课程名、教师或8位课程代码',
                        hintStyle: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchSchoolCourses(),
                    ),
                  ),
                  if (_courseSearchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _courseSearchController.clear();
                        setState(() {});
                      },
                      child: const Icon(Icons.cancel,
                          size: 16, color: Color(0xFF9CA3AF)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.usstRed,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _searchSchoolCourses(),
              child: const Text('查询',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  String get _displayLevel {
    switch (_selectedLevel) {
      case 'UNDERGRADUATE':
        return '仅本科';
      case 'GRADUATE':
        return '仅研究生';
      default:
        return '本研不限';
    }
  }

  String _displayCourseWeek(int currentWeek) {
    if (_selectedCourseWeek == 0) return '本周(第$currentWeek周)';
    if (_selectedCourseWeek > 0) return '第$_selectedCourseWeek周';
    return '全部周次';
  }

  bool get _hasActiveCourseFilters =>
      _selectedCollege != '全部学院' ||
      _selectedLevel != 'ALL' ||
      _selectedCourseDay != -1 ||
      _selectedCourseWeek != -1;

  void _resetCourseFilters() {
    setState(() {
      _selectedCollege = '全部学院';
      _selectedLevel = 'ALL';
      _selectedCourseDay = -1;
      _selectedCourseWeek = -1;
    });
    if (_courseSearched) {
      _searchSchoolCourses();
    }
  }

  Widget _buildActiveFilterChip(String label, VoidCallback onDeleted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFECACA), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.usstRed,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDeleted,
            child: const Icon(Icons.close, size: 13, color: AppColors.usstRed),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseFiltersRow(int currentWeek) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _buildFilterPill(
                icon: Icons.apartment_outlined,
                label: _selectedCollege == '全部学院' ? '全部学院' : _selectedCollege,
                isFiltered: _selectedCollege != '全部学院',
                onTap: _showCollegePickerModal,
              ),
              const SizedBox(width: 6),
              _buildFilterPill(
                icon: Icons.school_outlined,
                label: _displayLevel,
                isFiltered: _selectedLevel != 'ALL',
                onTap: _showLevelPickerModal,
              ),
              const SizedBox(width: 6),
              _buildFilterPill(
                icon: Icons.calendar_today_outlined,
                label: _selectedCourseDay == -1
                    ? '全部星期'
                    : _days[_selectedCourseDay - 1].name,
                isFiltered: _selectedCourseDay != -1,
                onTap: _showCourseDayPickerModal,
              ),
              const SizedBox(width: 6),
              _buildFilterPill(
                icon: Icons.date_range_outlined,
                label: _displayCourseWeek(currentWeek),
                isFiltered: _selectedCourseWeek != -1,
                onTap: () => _showCourseWeekPickerModal(currentWeek),
              ),
            ],
          ),
          if (_hasActiveCourseFilters) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      if (_selectedCollege != '全部学院')
                        _buildActiveFilterChip('学院: $_selectedCollege', () {
                          setState(() => _selectedCollege = '全部学院');
                          if (_courseSearched) _searchSchoolCourses();
                        }),
                      if (_selectedLevel != 'ALL')
                        _buildActiveFilterChip(_displayLevel,
                            () => setState(() => _selectedLevel = 'ALL')),
                      if (_selectedCourseDay != -1)
                        _buildActiveFilterChip(
                            _days[_selectedCourseDay - 1].name,
                            () => setState(() => _selectedCourseDay = -1)),
                      if (_selectedCourseWeek != -1)
                        _buildActiveFilterChip(
                            _displayCourseWeek(currentWeek),
                            () => setState(() => _selectedCourseWeek = -1)),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    foregroundColor: AppColors.usstRed,
                  ),
                  onPressed: _resetCourseFilters,
                  child: const Text('重置筛选', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showLevelPickerModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final options = <({String value, String label, String desc})>[
          (value: 'ALL', label: '本研不限', desc: '显示本科生与研究生全部课程'),
          (value: 'UNDERGRADUATE', label: '仅本科生', desc: '仅检索本科培养计划课程'),
          (value: 'GRADUATE', label: '仅研究生', desc: '仅检索硕士及博士研究生课程'),
        ];
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        '选择培养层次',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 20, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(
                    height: 1, thickness: 0.6, color: Color(0xFFF3F4F6)),
                ...options.map((opt) {
                  final isSel = _selectedLevel == opt.value;
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedLevel = opt.value);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFFFEF2F2)
                            : Colors.transparent,
                        border: const Border(
                            bottom: BorderSide(
                                color: Color(0xFFF3F4F6), width: 0.6)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            isSel
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: isSel
                                ? AppColors.usstRed
                                : const Color(0xFFD1D5DB),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  opt.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSel
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isSel
                                        ? AppColors.usstRed
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  opt.desc,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isSel
                                        ? AppColors.usstRed
                                            .withValues(alpha: 0.8)
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCourseDayPickerModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final options = <({int value, String label})>[
          (value: -1, label: '全部星期 (周一至周日)'),
          ..._days.map((d) => (value: d.day, label: d.name)),
        ];
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        '选择星期几',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 20, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(
                    height: 1, thickness: 0.6, color: Color(0xFFF3F4F6)),
                ...options.map((opt) {
                  final isSel = _selectedCourseDay == opt.value;
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedCourseDay = opt.value);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFFFEF2F2)
                            : Colors.transparent,
                        border: const Border(
                            bottom: BorderSide(
                                color: Color(0xFFF3F4F6), width: 0.6)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            isSel
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: isSel
                                ? AppColors.usstRed
                                : const Color(0xFFD1D5DB),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            opt.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isSel ? FontWeight.bold : FontWeight.w500,
                              color: isSel
                                  ? AppColors.usstRed
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCourseWeekPickerModal(int currentWeek) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          '选择教学周',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 20, color: AppColors.textSecondary),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.6),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _selectedCourseWeek == -1
                                ? const Color(0xFFFEF2F2)
                                : Colors.white,
                            side: BorderSide(
                              color: _selectedCourseWeek == -1
                                  ? AppColors.usstRed
                                  : const Color(0xFFE5E7EB),
                            ),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            setState(() => _selectedCourseWeek = -1);
                            Navigator.of(ctx).pop();
                          },
                          child: Text(
                            '全部周次',
                            style: TextStyle(
                              color: _selectedCourseWeek == -1
                                  ? AppColors.usstRed
                                  : AppColors.textPrimary,
                              fontWeight: _selectedCourseWeek == -1
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _selectedCourseWeek == 0
                                ? const Color(0xFFFEF2F2)
                                : Colors.white,
                            side: BorderSide(
                              color: _selectedCourseWeek == 0
                                  ? AppColors.usstRed
                                  : const Color(0xFFE5E7EB),
                            ),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            setState(() => _selectedCourseWeek = 0);
                            Navigator.of(ctx).pop();
                          },
                          child: Text(
                            '本周 (第$currentWeek周)',
                            style: TextStyle(
                              color: _selectedCourseWeek == 0
                                  ? AppColors.usstRed
                                  : AppColors.textPrimary,
                              fontWeight: _selectedCourseWeek == 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('指定教学周：',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List<Widget>.generate(20, (i) {
                      final w = i + 1;
                      final isSel = _selectedCourseWeek == w;
                      return ChoiceChip(
                        label: Text('第$w周',
                            style: TextStyle(
                                fontSize: 12,
                                color: isSel
                                    ? Colors.white
                                    : AppColors.textPrimary)),
                        selected: isSel,
                        selectedColor: AppColors.usstRed,
                        backgroundColor: const Color(0xFFF3F4F6),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                              color: isSel
                                  ? AppColors.usstRed
                                  : Colors.transparent),
                        ),
                        onSelected: (_) {
                          setState(() => _selectedCourseWeek = w);
                          Navigator.of(ctx).pop();
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCollegePickerModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (sheetCtx, scrollController) {
            final allColleges = <String>['全部学院', ..._colleges];
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        '选择开课学院',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.6),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: allColleges.length,
                    itemBuilder: (context, index) {
                      final college = allColleges[index];
                      final isSelected = _selectedCollege == college;
                      return ListTile(
                        dense: true,
                        title: Text(
                          college,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? AppColors.usstRed
                                : AppColors.textPrimary,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check,
                                color: AppColors.usstRed, size: 20)
                            : null,
                        onTap: () {
                          setState(() => _selectedCollege = college);
                          Navigator.of(sheetCtx).pop();
                          if (_courseSearched) {
                            _searchSchoolCourses();
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCourseSearchSummary(int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          RichText(
            text: TextSpan(
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              children: <TextSpan>[
                const TextSpan(text: '检索结果：共找到 '),
                TextSpan(
                  text: '$count ',
                  style: const TextStyle(
                    color: AppColors.usstRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(text: '个教学班排课'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseInitialGuide() {
    final tags = <String>[
      '高等数学',
      '大学物理',
      '线性代数',
      '微积分',
      '程序设计',
      '大学英语',
      '管理学院',
      '机械工程学院',
      '光电信息与计算机工程学院',
      '体育教学部',
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.tips_and_updates_outlined,
                        color: AppColors.usstRed, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '全校课表搜索说明',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  '• 支持按课程名称模糊检索（如“高等数学”）、任课老师姓名（如“张老师”）或 8 位教务课程代码。\n'
                  '• 支持按开课学院、本科生/研究生层级、星期几与教学周即时筛选。\n'
                  '• 数据实时同步自上海理工大学轻应用排课库。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '快捷热门检索',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((t) {
              return ActionChip(
                label: Text(t, style: const TextStyle(fontSize: 12.5)),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.border, width: 0.8),
                ),
                onPressed: () {
                  if (t.contains('学院') || t.contains('部')) {
                    setState(() => _selectedCollege = t);
                    _courseSearchController.clear();
                  } else {
                    _courseSearchController.text = t;
                  }
                  _searchSchoolCourses();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolCourseCard(SchoolCourse course, int currentWeek) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 顶部：课程名 + 本研标签 + 课程类型
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  course.courseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 本研标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: course.isGraduate
                      ? const Color(0xFFF3E8FF)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  course.isGraduate ? '研究生' : '本科',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: course.isGraduate
                        ? const Color(0xFF7E22CE)
                        : const Color(0xFF1D4ED8),
                  ),
                ),
              ),
              if (course.courseType.isNotEmpty) ...<Widget>[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    course.courseType,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF52525B),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // 教师与学院
          Row(
            children: <Widget>[
              const Icon(Icons.person_outline,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                course.teacherDisplay,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              if (course.college.isNotEmpty) ...<Widget>[
                const Icon(Icons.apartment_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    course.college,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),

          // 学分与班级名
          Row(
            children: <Widget>[
              if (course.creditHoursDisplay.isNotEmpty) ...<Widget>[
                const Icon(Icons.credit_card_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  course.creditHoursDisplay,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  course.className.isNotEmpty
                      ? course.className
                      : (course.classCode.isNotEmpty ? '班级：${course.classCode}' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 排课时段明细框
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: course.slots.map((slot) {
                final isThisWeek = slot.isActiveInWeek(currentWeek);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: <Widget>[
                      // 星期与节次
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFFE5E7EB), width: 0.6),
                        ),
                        child: Text(
                          '${slot.dayOfWeekName} ${slot.sectionDesc}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 上课地点
                      const Icon(Icons.place_outlined,
                          size: 13, color: AppColors.usstRed),
                      const SizedBox(width: 2),
                      Text(
                        slot.classroom.isNotEmpty ? slot.classroom : '待定',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 周次区间
                      Text(
                        '(${slot.weeksText.isNotEmpty ? slot.weeksText : "${slot.startWeek}-${slot.endWeek}"}周)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),

                      // 本周有课徽章
                      if (isThisWeek)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '本周有课',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
