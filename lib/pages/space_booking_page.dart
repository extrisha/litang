import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/jwc/space_booking_api.dart';
import 'simple_web_page.dart';

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
        _error = '请先登录统一身份认证后使用空间预约';
        _loading = false;
      });
      return;
    }

    _api ??= SpaceBookingApi(client);

    try {
      if (_api!.accessToken == null || forceRefresh) {
        final ok = await _api!.login();
        if (!ok) {
          setState(() {
            _error = '统一身份认证（CAS）免密登录空间预约失败，请检查网络或重新登录';
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

      setState(() {
        _rooms = results[0] as List<SpaceRoom>;
        _reservations = results[1] as List<SpaceReservation>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载空间数据失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _changeDate(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _loading = true;
    });
    if (_api != null) {
      final dateStr = _formatDate(date);
      final rooms = await _api!.fetchRooms(date: dateStr);
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _loading = false;
        });
      }
    }
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

  void _showGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.menu_book_outlined, color: AppColors.usstRed, size: 22),
            SizedBox(width: 8),
            Text('图书馆预约指引', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '1. 空间预约系统（当前页面）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                '• 服务对象：主要用于预约图书馆研讨间、小组研修间与多媒体自习空间。\n'
                '• 认证方式：支持上理统一身份认证（CAS）免密自动登录。',
                style: TextStyle(fontSize: 12.5, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                '2. 图书馆日常座位预约（我去图书馆）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                '• 服务对象：图书馆各楼层日常普通自习座席的预约、选座与离馆签退。\n'
                '• 使用方式：微信搜索并打开【我去图书馆】官方小程序，绑定上理学号即可使用。',
                style: TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  void _openWebVersion() {
    final code = _api?.authCode;
    final webUrl = code != null && code.isNotEmpty
        ? '${SpaceBookingPage.spaceBaseUrl}?code=$code'
        : SpaceBookingPage.spaceBaseUrl;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: '图书馆空间预约',
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('空间预约'),
          actions: <Widget>[
            IconButton(
              tooltip: '原网页版',
              icon: const Icon(Icons.language_outlined, size: 20),
              onPressed: _openWebVersion,
            ),
            IconButton(
              tooltip: '预约指引',
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: _showGuideDialog,
            ),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _initAndLoad(forceRefresh: true),
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
                text: '研修空间',
              ),
              Tab(
                icon: Icon(Icons.calendar_today_outlined, size: 20),
                text: '我的预约',
              ),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            _buildUserHeaderCard(),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _buildRoomsTab(),
                  _buildReservationsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeaderCard() {
    final realName = _api?.realName ?? '上理同学';
    final hasAuth = _api?.accessToken != null;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFDE8E8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_circle_outlined,
                color: AppColors.usstRed, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  realName,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasAuth ? '上海理工大学图书馆 · 空间预约已认证' : '正在同步认证会话...',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: hasAuth
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  hasAuth ? Icons.check_circle : Icons.sync,
                  size: 12,
                  color: hasAuth
                      ? const Color(0xFF15803D)
                      : const Color(0xFFB45309),
                ),
                const SizedBox(width: 3),
                Text(
                  hasAuth ? 'CAS已认证' : '认证中',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasAuth
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
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

    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _initAndLoad(forceRefresh: true),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _buildDateSelector(),
          ),
          if (_rooms.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.weekend_outlined,
                        color: AppColors.textSecondary, size: 48),
                    SizedBox(height: 12),
                    Text(
                      '所选日期暂无可预约研讨间',
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
                  (ctx, i) => _buildRoomCard(_rooms[i]),
                  childCount: _rooms.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final dates = List<DateTime>.generate(5, (i) => now.add(Duration(days: i)));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Divider(height: 1, thickness: 0.6, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: dates.map((d) {
                final isSelected = d.year == _selectedDate.year &&
                    d.month == _selectedDate.month &&
                    d.day == _selectedDate.day;
                final isToday = d.year == now.year &&
                    d.month == now.month &&
                    d.day == now.day;
                final label = isToday ? '今天' : '${d.month}月${d.day}日';

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.usstRed,
                    backgroundColor: const Color(0xFFF7F8FA),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color:
                            isSelected ? AppColors.usstRed : AppColors.border,
                        width: isSelected ? 1 : 0.6,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected && !isSelected) {
                        _changeDate(d);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(SpaceRoom room) {
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
                  color: room.status == 1
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  room.status == 1 ? '可预约' : '不可约',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: room.status == 1
                        ? const Color(0xFF15803D)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
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
          if (room.devices.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
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
          SizedBox(
            width: double.infinity,
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
              icon: const Icon(Icons.event_available_outlined, size: 16),
              label: const Text('预约此空间',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              onPressed: _openWebVersion,
            ),
          ),
        ],
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
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.usstRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _initAndLoad(forceRefresh: true),
              child: const Text('刷新'),
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
