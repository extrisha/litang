import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/jwc/space_booking_api.dart';
import 'simple_web_page.dart';
import 'space_room_detail_page.dart';

/// 空间预约原生页面（图书馆研讨间 / 空间预约系统）
class SpaceBookingPage extends StatefulWidget {
  const SpaceBookingPage({super.key});

  static const String spaceBaseUrl =
      'https://libspace.usst.edu.cn/student/studentIndex';

  @override
  State<SpaceBookingPage> createState() => _SpaceBookingPageState();
}

class _SpaceBookingPageState extends State<SpaceBookingPage> {
  SpaceBookingApi? _api;
  bool _loading = false;
  String? _error;

  List<SpaceRoom> _rooms = const <SpaceRoom>[];
  List<SpaceReservation> _reservations = const <SpaceReservation>[];

  late DateTime _selectedDate;
  String _selectedBuilding = '全部房间';

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _initAndLoad();
  }

  Future<void> _initAndLoad({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = JwglAuth.instance.client;
    if (client == null) {
      setState(() {
        _error = '请先在“我的”页面登录统一身份认证（CAS）后再使用空间预约';
        _loading = false;
      });
      return;
    }

    _api ??= SpaceBookingApi(client);

    try {
      if (forceRefresh || !_api!.isTokenValid) {
        final ok = await _api!.ensureAuthenticated(force: forceRefresh);
        if (!ok) {
          setState(() {
            _error = '统一身份认证（CAS）免密登录空间预约失败，该系统仅限校园网访问，请连接校园内网或登录 WebVPN 后重试';
            _loading = false;
          });
          return;
        }
      }

      final dateStr = _formatDate(_selectedDate);
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _api!.fetchRooms(date: dateStr),
        _api!.fetchMyReservations(),
      ]);

      if (mounted) {
        setState(() {
          _rooms = results[0] as List<SpaceRoom>;
          _reservations = results[1] as List<SpaceReservation>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取空间预约数据失败，该系统仅限校园网访问，请连接校园内网或登录 WebVPN 后重试';
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeDate(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _loading = true;
    });
    if (_api != null) {
      try {
        final dateStr = _formatDate(date);
        final rooms = await _api!.fetchRooms(date: dateStr);
        if (mounted) {
          setState(() {
            _rooms = rooms;
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = '获取空间预约数据失败，该系统仅限校园网访问，请连接校园内网或登录 WebVPN 后重试';
            _loading = false;
          });
        }
      }
    }
  }

  List<SpaceRoom> get _filteredRooms {
    if (_selectedBuilding == '全部房间' || _selectedBuilding == '全部') {
      return _rooms;
    }
    return _rooms.where((r) {
      return r.shortBuildingName == _selectedBuilding ||
          r.buildingName.contains(_selectedBuilding) ||
          r.name.contains(_selectedBuilding);
    }).toList();
  }

  List<String> get _availableBuildings {
    const canonicalOrder = <String>['全部房间', '湛恩', '334号', '复兴', '1100号'];
    final present = <String>{'全部房间'};
    for (final r in _rooms) {
      final s = r.shortBuildingName;
      if (s != '其他') {
        present.add(s);
      }
    }
    final result = <String>[];
    for (final b in canonicalOrder) {
      if (present.contains(b)) {
        result.add(b);
      }
    }
    for (final b in present) {
      if (!result.contains(b)) {
        result.add(b);
      }
    }
    return result;
  }

  int _countForBuilding(String b) {
    if (b == '全部房间' || b == '全部') return _rooms.length;
    return _rooms
        .where((r) =>
            r.shortBuildingName == b ||
            r.buildingName.contains(b) ||
            r.name.contains(b))
        .length;
  }

  Future<void> _handleCancel(SpaceReservation res) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认取消预约'),
        content: Text('您确定要取消【${res.roomName}】(${res.date} ${res.timeRange}) 的预约吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('放弃'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (_api == null) return;

    final success = await _api!.cancelReservation(res.id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预约已成功取消')),
      );
      _initAndLoad(forceRefresh: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('取消预约失败，请稍后重试或在网页端操作')),
      );
    }
  }

  void _openRoomDetail(SpaceRoom room) {
    if (_api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpaceRoomDetailPage(
          room: room,
          initialDate: _selectedDate,
          api: _api!,
        ),
      ),
    );
  }

  /// 预约空间：动态获取全新 code，直接免密直达房间预约页面
  Future<void> _openWebBooking([SpaceRoom? room]) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.usstRed),
                SizedBox(width: 16),
                Text('正在同步免密凭据...', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );

    String? code;
    if (_api != null) {
      code = await _api!.acquireFreshAuthCode(
        redirectPath: room != null ? '/mStudent/room' : '/mStudent/index',
      );
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    final dateStr = _formatDate(_selectedDate);
    final webUrl = (code != null && code.isNotEmpty)
        ? (room != null
            ? 'https://libspace.usst.edu.cn/mStudent/room?roomId=${room.id}&date=$dateStr&code=$code'
            : 'https://libspace.usst.edu.cn/mStudent/index?code=$code')
        : (room != null
            ? 'https://libspace.usst.edu.cn/mStudent/room?roomId=${room.id}&date=$dateStr'
            : 'https://libspace.usst.edu.cn/mStudent/index');

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: room != null ? '预约 · ${room.name}' : '图书馆空间预约',
          url: webUrl,
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _showBuildingPicker() {
    final buildings = _availableBuildings;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: <Widget>[
                    const Text(
                      '选择可预约建筑',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.6, color: Color(0xFFEEEEEE)),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: buildings.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, thickness: 0.5, indent: 20, endIndent: 20),
                  itemBuilder: (ctx, i) {
                    final b = buildings[i];
                    final isSelected = b == _selectedBuilding;
                    final count = _countForBuilding(b);

                    String fullName = '';
                    if (b == '湛恩') fullName = '湛恩图书馆';
                    if (b == '334号') fullName = '南校区图书馆';
                    if (b == '复兴') fullName = '复兴路校区图书馆';
                    if (b == '1100号') fullName = '1100号校区图书馆';

                    return ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      title: Row(
                        children: <Widget>[
                          Text(
                            b,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                            ),
                          ),
                          if (fullName.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 8),
                            Text(
                              fullName,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '$count间',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isSelected ? AppColors.usstRed : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isSelected)
                            const Icon(Icons.check_rounded, color: AppColors.usstRed, size: 20)
                          else
                            const SizedBox(width: 20),
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          _selectedBuilding = b;
                        });
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showDatePickerSheet() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidateDates = <DateTime>[
      today,
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 2)),
    ];
    final weekdayNames = <int, String>{
      1: '周一',
      2: '周二',
      3: '周三',
      4: '周四',
      5: '周五',
      6: '周六',
      7: '周日',
    };
    const dayLabels = <String>['今天', '明天', '后天'];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: <Widget>[
                    const Text(
                      '选择预约日期 (仅开放近3天)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.6, color: Color(0xFFEEEEEE)),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidateDates.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, thickness: 0.5, indent: 20, endIndent: 20),
                  itemBuilder: (ctx, i) {
                    final d = candidateDates[i];
                    final isSelected = d.year == _selectedDate.year &&
                        d.month == _selectedDate.month &&
                        d.day == _selectedDate.day;
                    final isToday = i == 0;
                    final remark = dayLabels[i];

                    return ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      title: Row(
                        children: <Widget>[
                          Text(
                            _formatDate(d),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            weekdayNames[d.weekday] ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isToday ? const Color(0xFFFEE2E2) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              remark,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isToday ? AppColors.usstRed : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: AppColors.usstRed, size: 20)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _changeDate(d);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('空间预约'),
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
                text: '研修空间',
              ),
              Tab(
                icon: Icon(Icons.calendar_today_outlined, size: 20),
                text: '我的预约',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _buildRoomsTab(),
            _buildReservationsTab(),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 1: 研讨间列表
  // =========================================================================

  Widget _buildRoomsTab() {
    if (_loading && _rooms.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.usstRed),
      );
    }

    if (_error != null && _rooms.isEmpty) {
      return Center(
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
                    color: AppColors.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.usstRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _initAndLoad(forceRefresh: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredRooms;

    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _initAndLoad(forceRefresh: true),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _buildFilterBar(),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.weekend_outlined,
                        color: AppColors.textSecondary, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _selectedBuilding == '全部房间'
                          ? '所选日期暂无可预约研讨间'
                          : '所选日期【$_selectedBuilding】暂无可预约研讨间',
                      style: const TextStyle(
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
                  (ctx, i) => _buildRoomCard(filtered[i]),
                  childCount: filtered.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          // 胶囊 1: 建筑选择
          Expanded(
            child: _buildCapsule(
              text: _selectedBuilding,
              onTap: _showBuildingPicker,
            ),
          ),
          const SizedBox(width: 12),
          // 胶囊 2: 日期选择
          Expanded(
            child: _buildCapsule(
              text: _formatDate(_selectedDate),
              onTap: _showDatePickerSheet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapsule({
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFD1D5DB),
            width: 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(SpaceRoom room) {
    Color badgeBg;
    Color badgeText;
    if (room.isAvailable) {
      badgeBg = const Color(0xFFDCFCE7);
      badgeText = const Color(0xFF15803D);
    } else if (room.status == 2) {
      badgeBg = const Color(0xFFF3F4F6);
      badgeText = const Color(0xFF6B7280);
    } else if (room.status == 1) {
      badgeBg = const Color(0xFFF3F4F6);
      badgeText = const Color(0xFF6B7280);
    } else {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFB45309);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openRoomDetail(room),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      room.statusDesc,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  if (room.shortBuildingName != '其他') ...<Widget>[
                    const Icon(Icons.apartment_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      room.shortBuildingName,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (room.floor.isNotEmpty) ...<Widget>[
                    const Icon(Icons.place_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      room.floor,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Icon(Icons.people_outline,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text(
                    room.capacityDesc,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      room.roomType,
                      style:
                          const TextStyle(fontSize: 10.5, color: Color(0xFF52525B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const Icon(Icons.access_time_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '开放时段：${room.openStartTime} - ${room.openEndTime}',
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF6B7280)),
                  ),
                  if (room.verify == 1) ...<Widget>[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '须审核',
                        style: TextStyle(fontSize: 10, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ],
              ),
              if (room.devices.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    const Icon(Icons.devices_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '设施：${room.devices}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.calendar_month_outlined, size: 15),
                        label: const Text('时段详情',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        onPressed: () => _openRoomDetail(room),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.usstRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.event_available_outlined, size: 15),
                        label: const Text('预约此空间',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        onPressed: () => _openWebBooking(room),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 2: 我的预约
  // =========================================================================

  Widget _buildReservationsTab() {
    if (_loading && _reservations.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.usstRed),
      );
    }

    if (_reservations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.event_busy_outlined,
                color: AppColors.textSecondary, size: 52),
            const SizedBox(height: 12),
            const Text(
              '当前没有进行中或近期的预约记录',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _initAndLoad(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reservations.length,
        itemBuilder: (ctx, i) => _buildReservationCard(_reservations[i]),
      ),
    );
  }

  Widget _buildReservationCard(SpaceReservation res) {
    Color badgeBg;
    Color badgeText;
    switch (res.status) {
      case 0:
        badgeBg = const Color(0xFFFEF3C7);
        badgeText = const Color(0xFFB45309);
        break;
      case 1:
        badgeBg = const Color(0xFFDCFCE7);
        badgeText = const Color(0xFF15803D);
        break;
      case 2:
        badgeBg = const Color(0xFFF3F4F6);
        badgeText = const Color(0xFF4B5563);
        break;
      default:
        badgeBg = const Color(0xFFFEE2E2);
        badgeText = const Color(0xFFB91C1C);
    }

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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  res.roomName,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  res.statusDesc,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Icon(Icons.date_range_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                res.date,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.access_time_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                res.timeRange,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textPrimary),
              ),
            ],
          ),
          if (res.canCancel) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.usstRed,
                    side: const BorderSide(color: AppColors.usstRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                  ),
                  onPressed: () => _handleCancel(res),
                  child: const Text('取消预约', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
