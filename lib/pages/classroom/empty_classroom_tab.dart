import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/auth/jwgl_auth.dart';
import '../../data/calendar/calendar_service.dart';
import '../../data/jwc/classroom_api.dart';
import '../../data/jwc/classroom_data.dart';
import 'widgets/classroom_card.dart';
import 'widgets/classroom_filter_sheet.dart';

/// 空教室检索 Tab 页面
class EmptyClassroomTab extends StatefulWidget {
  const EmptyClassroomTab({super.key});

  @override
  State<EmptyClassroomTab> createState() => _EmptyClassroomTabState();
}

class _EmptyClassroomTabState extends State<EmptyClassroomTab> {
  String _selectedBuilding = '全部教学楼';
  int _selectedWeek = 1;
  int _selectedDay = 1; // 1-7
  int _selectedSectionIndex = 0;
  bool _onlyFree = true;
  String _classroomKeyword = '';

  bool _loading = false;
  String? _error;
  List<ClassroomInfo> _allRooms = const <ClassroomInfo>[];
  final TextEditingController _searchController = TextEditingController();

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
    _searchController.addListener(() {
      setState(() {
        _classroomKeyword = _searchController.text.trim();
      });
    });
    _loadClassrooms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initDefaults() {
    final now = DateTime.now();
    final currentWeek = CalendarService.instance.currentWeek ?? 1;
    _selectedWeek = currentWeek.clamp(1, 20);
    _selectedDay = now.weekday;

    final hour = now.hour;
    if (hour < 10) {
      _selectedSectionIndex = 0;
    } else if (hour < 12) {
      _selectedSectionIndex = 1;
    } else if (hour < 15) {
      _selectedSectionIndex = 2;
    } else if (hour < 17) {
      _selectedSectionIndex = 3;
    } else {
      _selectedSectionIndex = 4;
    }
  }

  Future<void> _loadClassrooms({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = JwglAuth.instance.client;
    if (client == null) {
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
        _loading = false;
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
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '教室数据加载失败：$e';
        _loading = false;
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

  @override
  Widget build(BuildContext context) {
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
                _buildFilterHeader(),
                _buildSummary(total, freeCount),
              ],
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.usstRed),
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
                  (ctx, i) => ClassroomCard(room: filtered[i]),
                  childCount: filtered.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: <Widget>[
          // Top Row: 搜索框 + "仅看空闲"
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
                          controller: _searchController,
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
                          onTap: () => _searchController.clear(),
                          child: const Icon(Icons.cancel, size: 16, color: Color(0xFF9CA3AF)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
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

          // 3 个并排筛选胶囊 (楼栋 / 节次 / 周次星期)
          Row(
            children: <Widget>[
              _buildFilterPill(
                icon: Icons.apartment_outlined,
                label: _displayBuilding,
                isFiltered: _selectedBuilding != '全部教学楼',
                onTap: () => showBuildingPickerModal(
                  context: context,
                  selectedBuilding: _selectedBuilding,
                  onSelected: (b) {
                    setState(() => _selectedBuilding = b);
                    _loadClassrooms();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterPill(
                icon: Icons.access_time_outlined,
                label: _displaySection,
                isFiltered: _selectedSectionIndex != 0,
                onTap: () => showSectionPickerModal(
                  context: context,
                  selectedIndex: _selectedSectionIndex,
                  onSelected: (i) {
                    setState(() => _selectedSectionIndex = i);
                    _loadClassrooms();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterPill(
                icon: Icons.calendar_today_outlined,
                label: '第$_selectedWeek周·${_days[_selectedDay - 1].name}',
                isFiltered: _isDateFiltered,
                onTap: () => showDatePickerModal(
                  context: context,
                  selectedWeek: _selectedWeek,
                  selectedDay: _selectedDay,
                  onConfirmed: (w, d) {
                    setState(() {
                      _selectedWeek = w;
                      _selectedDay = d;
                    });
                    _loadClassrooms();
                  },
                ),
              ),
            ],
          ),
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

  Widget _buildSummary(int total, int freeCount) {
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
}
