import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/jwc/space_booking_api.dart';
import 'simple_web_page.dart';
import 'space_room_detail_page.dart';

/// 空间预约原生主页面（图书馆研讨间 / 静音舱 / 研修空间系统）
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
  SpaceUserProfile? _profile;

  late DateTime _selectedDate;
  String _selectedBuilding = '全部房间';
  String _searchKeyword = '';
  String _selectedCapacityFilter = '全部'; // 全部, 仅看可约, 单人静音舱, 2-4人研讨, 5人以上
  int _reservationFilterIndex = 0; // 0: 全部, 1: 进行中, 2: 已结束

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _initAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final sessionOk = await JwglAuth.instance.ensureSession();
    final client = JwglAuth.instance.client;
    if (!sessionOk || client == null) {
      setState(() {
        _error = '请先在“我的”页面登录统一身份认证（CAS）后再使用空间预约';
        _loading = false;
      });
      return;
    }

    _api = SpaceBookingApi(client);

    try {
      if (forceRefresh || !_api!.isTokenValid) {
        final ok = await _api!.ensureAuthenticated(force: forceRefresh);
        if (!ok) {
          setState(() {
            _error = '统一身份认证（CAS）免密登录空间预约失败，请检查网络或登录 WebVPN 后重试';
            _loading = false;
          });
          return;
        }
      }

      final dateStr = _formatDate(_selectedDate);
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _api!.fetchRooms(date: dateStr),
        _api!.fetchMyReservations(),
        _api!.fetchUserProfile(force: forceRefresh),
      ]);

      if (mounted) {
        setState(() {
          _rooms = results[0] as List<SpaceRoom>;
          _reservations = results[1] as List<SpaceReservation>;
          _profile = results[2] as SpaceUserProfile?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取空间预约数据失败，请检查网络或登录 WebVPN 后重试';
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
        await _api!.ensureAuthenticated();
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
            _error = '获取空间预约数据失败，请检查网络或登录 WebVPN 后重试';
            _loading = false;
          });
        }
      }
    }
  }

  List<SpaceRoom> get _filteredRooms {
    return _rooms.where((r) {
      // 1. 建筑筛选
      if (_selectedBuilding != '全部房间' && _selectedBuilding != '全部') {
        final hit = r.shortBuildingName == _selectedBuilding ||
            r.buildingName.contains(_selectedBuilding) ||
            r.name.contains(_selectedBuilding);
        if (!hit) return false;
      }

      // 2. 类别/容量筛选
      if (_selectedCapacityFilter == '仅看可约') {
        if (!r.isAvailable) return false;
      } else if (_selectedCapacityFilter == '单人静音舱') {
        if (r.maxNum > 1 && !r.name.contains('静音舱')) return false;
      } else if (_selectedCapacityFilter == '2-4人研讨') {
        if (r.maxNum < 2 || r.minNum > 4) return false;
      } else if (_selectedCapacityFilter == '5人以上') {
        if (r.maxNum < 5) return false;
      }

      // 3. 关键字搜索
      if (_searchKeyword.isNotEmpty) {
        final kw = _searchKeyword.toLowerCase();
        final hit = r.name.toLowerCase().contains(kw) ||
            r.buildingName.toLowerCase().contains(kw) ||
            r.floor.toLowerCase().contains(kw) ||
            r.devices.toLowerCase().contains(kw) ||
            r.roomType.toLowerCase().contains(kw);
        if (!hit) return false;
      }

      return true;
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

  List<SpaceReservation> get _filteredReservations {
    if (_reservationFilterIndex == 1) {
      // 进行中（待使用或使用中）
      return _reservations.where((r) => r.isUpcoming || r.isInProgress).toList();
    } else if (_reservationFilterIndex == 2) {
      // 已结束（已完成或已取消）
      return _reservations.where((r) => r.isFinished || r.isCancelled).toList();
    }
    return _reservations;
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

  Future<void> _handleSignOut(SpaceReservation res) async {
    if (_api == null || res.roomId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认签退'),
        content: Text('确认对【${res.roomName}】执行签退并释放房间吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认签退'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await _api!.signOutReservation(roomId: res.roomId);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('签退成功，房间已释放')),
      );
      _initAndLoad(forceRefresh: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('签退失败，请重试或在门口设备刷卡')),
      );
    }
  }

  Future<void> _handleAfk(SpaceReservation res) async {
    if (_api == null || res.roomId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认暂离'),
        content: const Text('使用中暂离最长 30 分钟。超过时间系统将自动释放房间，确定暂离吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认暂离'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await _api!.afkReservation(roomId: res.roomId);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已登记暂离，请在30分钟内返回')),
      );
      _initAndLoad(forceRefresh: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登记暂离失败，请稍后重试')),
      );
    }
  }

  void _showSignCodeDialog(SpaceReservation res) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: <Widget>[
            Icon(Icons.qr_code_2_rounded, color: AppColors.usstRed, size: 24),
            SizedBox(width: 8),
            Text('签到凭证与核验码', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(res.roomName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${res.date} ${res.timeRange}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: <Widget>[
                  const Text('签到核销码', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  SelectableText(
                    res.qrCode.isNotEmpty ? res.qrCode : '可在研讨室门口刷校园卡直接签到',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: res.qrCode.isNotEmpty ? 22 : 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: res.qrCode.isNotEmpty ? 2.5 : 0,
                      color: AppColors.usstRed,
                    ),
                  ),
                ],
              ),
            ),
            if (res.qrCode.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('复制核销码', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: res.qrCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制签到核销码')),
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              '提示：到达研修室门口平板时，输入此核验码或直接刷实体校园卡即可完成快速签到。',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
            ),
          ],
        ),
        actions: <Widget>[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showCreditRulesDialog() {
    final score = _profile?.totalScore ?? 10;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: <Widget>[
            const Icon(Icons.stars_rounded, color: Color(0xFFEAB308), size: 24),
            const SizedBox(width: 8),
            Text('空间预约信用积分 ($score分)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '上海理工大学图书馆研讨空间信用规则：',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              '1. 初始信用积分为 10 分（满分）。\n'
              '2. 成功预约后，请在开场前20分钟至开场后20分钟内刷卡或扫码签到。\n'
              '3. 使用完毕后请在门禁设备或手机端主动点击“签退”。\n'
              '4. 迟到未签到、违规暂离超时（超过30分钟）等将被计为违规扣分。\n'
              '5. 信用积分低于指定分数将被暂停研讨空间预约资格。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45),
            ),
          ],
        ),
        actions: <Widget>[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  void _openRoomDetail(SpaceRoom room) {
    if (_api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpaceRoomDetailPage(
          room: room,
          initialDate: _selectedDate,
          api: _api!,
          onReservationCompleted: () => _initAndLoad(forceRefresh: true),
        ),
      ),
    );
  }

  /// 官方网页端入口（免密跳转）
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

    final cookies =
        JwglAuth.instance.client?.jar.cookies ?? const <CasCookie>[];

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: room != null ? '网页预约 · ${room.name}' : '图书馆空间预约',
          url: webUrl,
          cookies: cookies,
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
                      '选择建筑/馆舍',
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
              tooltip: '在官方网页端打开',
              icon: const Icon(Icons.open_in_browser_rounded, size: 22),
              onPressed: () => _openWebBooking(),
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
    final totalAvail = _rooms.where((r) => r.isAvailable).length;

    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _initAndLoad(forceRefresh: true),
      child: CustomScrollView(
        slivers: <Widget>[
          // 顶部个人信用徽章栏
          SliverToBoxAdapter(
            child: _buildCreditBanner(),
          ),
          // 快捷横向日期切换条
          SliverToBoxAdapter(
            child: _buildDateStrip(),
          ),
          // 筛选与搜索栏
          SliverToBoxAdapter(
            child: _buildFilterBar(totalAvail, filtered.length),
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
                      _searchKeyword.isNotEmpty
                          ? '未搜索到包含“$_searchKeyword”的空间'
                          : _selectedBuilding == '全部房间'
                              ? '当前筛选条件下暂无研讨间'
                              : '【$_selectedBuilding】暂无匹配研讨间',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                    if (_searchKeyword.isNotEmpty || _selectedCapacityFilter != '全部') ...<Widget>[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _searchKeyword = '';
                            _searchController.clear();
                            _selectedCapacityFilter = '全部';
                          });
                        },
                        child: const Text('重置筛选条件'),
                      ),
                    ],
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

  /// 顶部信用积分与身份横幅
  Widget _buildCreditBanner() {
    final name = _profile?.realName ?? _api?.realName ?? '同学';
    final dept = _profile?.departmentName ?? '';
    final score = _profile?.totalScore ?? 10;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: <Widget>[
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFFEE2E2),
              child: Icon(Icons.school, size: 18, color: AppColors.usstRed),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (dept.isNotEmpty)
                    Text(
                      dept,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            InkWell(
              onTap: _showCreditRulesDialog,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFDE68A), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 15),
                    const SizedBox(width: 4),
                    Text(
                      '信用分 $score',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.info_outline, color: Color(0xFFB45309), size: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 横向近3天快速切换条
  Widget _buildDateStrip() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidateDates = <DateTime>[
      today,
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 2)),
    ];
    const labels = <String>['今天', '明天', '后天'];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: List<Widget>.generate(candidateDates.length, (i) {
          final d = candidateDates[i];
          final isSelected = d.year == _selectedDate.year &&
              d.month == _selectedDate.month &&
              d.day == _selectedDate.day;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : 4,
                right: i == candidateDates.length - 1 ? 0 : 4,
              ),
              child: InkWell(
                onTap: () {
                  if (!isSelected) {
                    _changeDate(d);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFEE2E2) : const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.usstRed : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.usstRed : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 综合筛选与搜索栏
  Widget _buildFilterBar(int totalAvail, int filteredCount) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 搜索框与建筑下拉胶囊
          Row(
            children: <Widget>[
              // 建筑选择
              InkWell(
                onTap: _showBuildingPicker,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.apartment_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        _selectedBuilding,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 关键字搜索框
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索房间号/楼层/设施...',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                      suffixIcon: _searchKeyword.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                setState(() {
                                  _searchKeyword = '';
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.usstRed),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchKeyword = val.trim();
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 容量/类别过滤 Chip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <String>[
                '全部',
                '仅看可约',
                '单人静音舱',
                '2-4人研讨',
                '5人以上',
              ].map((category) {
                final isSelected = _selectedCapacityFilter == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    selectedColor: const Color(0xFFFEE2E2),
                    backgroundColor: const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                    ),
                    side: BorderSide(
                      color: isSelected ? AppColors.usstRed : Colors.transparent,
                      width: 0.8,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      setState(() {
                        _selectedCapacityFilter = category;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          // 实时可约数量统计
          Row(
            children: <Widget>[
              Text(
                '已筛选 $filteredCount 间空间',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '当前共 $totalAvail 间可约',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(SpaceRoom room) {
    Color badgeBg;
    Color badgeText;
    if (room.isAvailable) {
      badgeBg = const Color(0xFFDCFCE7);
      badgeText = const Color(0xFF15803D);
    } else if (room.status == 2 || room.status == 1) {
      badgeBg = const Color(0xFFF3F4F6);
      badgeText = const Color(0xFF6B7280);
    } else {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFB45309);
    }

    final devList = room.deviceList;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openRoomDetail(room),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // 左侧主要信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 第一行：房间名称与状态
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(5),
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
                      const SizedBox(height: 6),
                      // 第二行：位置与容量
                      Row(
                        children: <Widget>[
                          if (room.locationDesc.isNotEmpty) ...<Widget>[
                            const Icon(Icons.place_outlined,
                                size: 13.5, color: AppColors.textSecondary),
                            const SizedBox(width: 2.5),
                            Text(
                              room.locationDesc,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(width: 10),
                          ],
                          const Icon(Icons.people_outline,
                              size: 13.5, color: AppColors.textSecondary),
                          const SizedBox(width: 2.5),
                          Text(
                            room.capacityDesc,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                          if (room.roomType.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                room.roomType,
                                style: const TextStyle(
                                    fontSize: 10.5, color: Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 第三行：开放时段与空闲时长
                      Row(
                        children: <Widget>[
                          const Icon(Icons.access_time_outlined,
                              size: 13.5, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Text(
                            '${room.openStartTime} - ${room.openEndTime}',
                            style: const TextStyle(
                                fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                          if (room.isAvailable && room.spaceTime > 0) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                    color: const Color(0xFFBBF7D0), width: 0.6),
                              ),
                              child: Text(
                                room.freeTimeDesc,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF15803D),
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                          if (room.verify == 1) ...<Widget>[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                '须审核',
                                style: TextStyle(
                                    fontSize: 10, color: Color(0xFF92400E)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (devList.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: devList.take(3).map((d) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0), width: 0.5),
                              ),
                              child: Text(
                                d,
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFF64748B)),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 右侧箭头指示符
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
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

    final filtered = _filteredReservations;
    final activeCount = _reservations.where((r) => r.isUpcoming || r.isInProgress).length;
    final pastCount = _reservations.where((r) => r.isFinished || r.isCancelled).length;

    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _initAndLoad(forceRefresh: true),
      child: Column(
        children: <Widget>[
          // 分类子标签
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                _buildReservationFilterChip('全部 (${_reservations.length})', 0),
                const SizedBox(width: 8),
                _buildReservationFilterChip('进行中 ($activeCount)', 1),
                const SizedBox(width: 8),
                _buildReservationFilterChip('已结束 ($pastCount)', 2),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.6, color: Color(0xFFEEEEEE)),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(Icons.event_busy_outlined,
                            color: AppColors.textSecondary, size: 52),
                        const SizedBox(height: 12),
                        Text(
                          _reservationFilterIndex == 1
                              ? '当前没有进行中或待使用的预约'
                              : _reservationFilterIndex == 2
                                  ? '当前没有历史预约记录'
                                  : '当前没有进行中或近期的预约记录',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.usstRed,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text('去挑选研修空间'),
                          onPressed: () {
                            DefaultTabController.of(context).animateTo(0);
                          },
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _buildReservationCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReservationFilterChip(String label, int index) {
    final isSelected = _reservationFilterIndex == index;
    return InkWell(
      onTap: () => setState(() => _reservationFilterIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.usstRed : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
          ),
        ),
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
          // 房间名与状态徽章
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
          // 日期与时段
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
          if (res.minSignTime.isNotEmpty && res.maxSignTime.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Icon(Icons.pin_outlined, size: 14, color: Color(0xFFD97706)),
                const SizedBox(width: 4),
                Text(
                  '签到窗口：${res.minSignTime} - ${res.maxSignTime}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                ),
              ],
            ),
          ],
          if (res.dictName.isNotEmpty || res.remark.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '用途：${res.dictName.isNotEmpty ? res.dictName : '自习研习'}${res.remark.isNotEmpty ? ' (${res.remark})' : ''}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.6, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 10),
          // 操作按钮行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              // 查看签到码
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.qr_code, size: 14),
                label: const Text('签到凭证', style: TextStyle(fontSize: 12)),
                onPressed: () => _showSignCodeDialog(res),
              ),
              // 使用中：暂离
              if (res.canAfk) ...<Widget>[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD97706),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.pause_circle_outline, size: 14),
                  label: const Text('暂离', style: TextStyle(fontSize: 12)),
                  onPressed: () => _handleAfk(res),
                ),
              ],
              // 使用中：签退
              if (res.canSignOut) ...<Widget>[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.logout, size: 14),
                  label: const Text('立即签退', style: TextStyle(fontSize: 12)),
                  onPressed: () => _handleSignOut(res),
                ),
              ],
              // 待使用：取消预约
              if (res.canCancel) ...<Widget>[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.usstRed,
                    side: const BorderSide(color: AppColors.usstRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _handleCancel(res),
                  child: const Text('取消预约', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
