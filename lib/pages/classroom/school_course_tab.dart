import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/auth/jwgl_auth.dart';
import '../../data/calendar/calendar_service.dart';
import '../../data/jwc/classroom_api.dart';
import 'widgets/school_course_card.dart';
import 'widgets/school_course_filter_sheet.dart';

/// 全校课表检索 Tab 页面
class SchoolCourseTab extends StatefulWidget {
  const SchoolCourseTab({super.key});

  @override
  State<SchoolCourseTab> createState() => _SchoolCourseTabState();
}

class _SchoolCourseTabState extends State<SchoolCourseTab> {
  final TextEditingController _searchController = TextEditingController();
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<SchoolCourse> _schoolCourses = const <SchoolCourse>[];
  List<String> _colleges = ClassroomApi.defaultColleges;

  String _selectedCollege = '全部学院';
  String _selectedLevel = 'ALL'; // 'ALL', 'UNDERGRADUATE', 'GRADUATE'
  int _selectedCourseDay = -1; // -1: 全部, 1-7
  int _selectedCourseWeek = -1; // -1: 全部, 0: 当前周, 1-20

  @override
  void initState() {
    super.initState();
    _loadColleges();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _searchSchoolCourses({bool forceRefresh = false}) async {
    final keyword = _searchController.text.trim();
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
      _loading = true;
      _error = null;
      _searched = true;
    });

    final client = JwglAuth.instance.client;
    if (client == null) {
      setState(() {
        _error = '请先登录统一身份认证后查询全校排课';
        _loading = false;
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
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '全校排课查询失败：$e';
        _loading = false;
      });
    }
  }

  List<SchoolCourse> get _filteredCourses {
    final currentWeek = CalendarService.instance.currentWeek ?? 1;

    return _schoolCourses.where((c) {
      // 1. 本研筛选
      if (_selectedLevel == 'UNDERGRADUATE' && !c.isUndergraduate) return false;
      if (_selectedLevel == 'GRADUATE' && !c.isGraduate) return false;

      // 2. 学院筛选
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
        final hasWeek = c.slots.any((s) => s.isActiveInWeek(currentWeek));
        if (!hasWeek) return false;
      } else if (_selectedCourseWeek > 0) {
        final hasWeek = c.slots.any((s) => s.isActiveInWeek(_selectedCourseWeek));
        if (!hasWeek) return false;
      }

      return true;
    }).toList();
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

  bool get _hasActiveFilters =>
      _selectedCollege != '全部学院' ||
      _selectedLevel != 'ALL' ||
      _selectedCourseDay != -1 ||
      _selectedCourseWeek != -1;

  void _resetFilters() {
    setState(() {
      _selectedCollege = '全部学院';
      _selectedLevel = 'ALL';
      _selectedCourseDay = -1;
      _selectedCourseWeek = -1;
    });
    if (_searched) {
      _searchSchoolCourses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCourses;
    final currentWeek = CalendarService.instance.currentWeek ?? 1;

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildSearchBar(),
              _buildFiltersRow(currentWeek),
              if (_searched) _buildSearchSummary(filtered.length),
            ],
          ),
        ),
        if (_loading)
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
        else if (_error != null)
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
                      _error!,
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
        else if (!_searched)
          SliverToBoxAdapter(
            child: _buildInitialGuide(),
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
                (ctx, i) => SchoolCourseCard(
                  course: filtered[i],
                  currentWeek: currentWeek,
                ),
                childCount: filtered.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildSearchBar() {
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
                      controller: _searchController,
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
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
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

  Widget _buildFiltersRow(int currentWeek) {
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
                onTap: () => showCollegePickerModal(
                  context: context,
                  colleges: _colleges,
                  selectedCollege: _selectedCollege,
                  onSelected: (col) {
                    setState(() => _selectedCollege = col);
                    if (_searched) _searchSchoolCourses();
                  },
                ),
              ),
              const SizedBox(width: 6),
              _buildFilterPill(
                icon: Icons.school_outlined,
                label: _displayLevel,
                isFiltered: _selectedLevel != 'ALL',
                onTap: () => showLevelPickerModal(
                  context: context,
                  selectedLevel: _selectedLevel,
                  onSelected: (lvl) {
                    setState(() => _selectedLevel = lvl);
                  },
                ),
              ),
              const SizedBox(width: 6),
              _buildFilterPill(
                icon: Icons.calendar_today_outlined,
                label: _selectedCourseDay == -1
                    ? '全部星期'
                    : kCourseDays[_selectedCourseDay - 1].name,
                isFiltered: _selectedCourseDay != -1,
                onTap: () => showCourseDayPickerModal(
                  context: context,
                  selectedCourseDay: _selectedCourseDay,
                  onSelected: (d) {
                    setState(() => _selectedCourseDay = d);
                  },
                ),
              ),
              const SizedBox(width: 6),
              _buildFilterPill(
                icon: Icons.date_range_outlined,
                label: _displayCourseWeek(currentWeek),
                isFiltered: _selectedCourseWeek != -1,
                onTap: () => showCourseWeekPickerModal(
                  context: context,
                  currentWeek: currentWeek,
                  selectedCourseWeek: _selectedCourseWeek,
                  onSelected: (w) {
                    setState(() => _selectedCourseWeek = w);
                  },
                ),
              ),
            ],
          ),
          if (_hasActiveFilters) ...<Widget>[
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
                          if (_searched) _searchSchoolCourses();
                        }),
                      if (_selectedLevel != 'ALL')
                        _buildActiveFilterChip(_displayLevel,
                            () => setState(() => _selectedLevel = 'ALL')),
                      if (_selectedCourseDay != -1)
                        _buildActiveFilterChip(
                            kCourseDays[_selectedCourseDay - 1].name,
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
                  onPressed: _resetFilters,
                  child: const Text('重置筛选', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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

  Widget _buildSearchSummary(int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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

  Widget _buildInitialGuide() {
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
                    _searchController.clear();
                  } else {
                    _searchController.text = t;
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
}
