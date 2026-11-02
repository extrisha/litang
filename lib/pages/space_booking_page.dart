import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/date_format.dart';
import '../data/jwc/space_booking_api.dart';
import '../data/jwc/space_web_url.dart';
import '../data/request_guard.dart';
import '../widgets/blocking_progress.dart';
import 'simple_web_page.dart';
import 'space_room_detail_page.dart';

enum _ExpandedPanel { none, date, building }

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

  /// 列表请求代次。`_initAndLoad`（首次/下拉刷新/重试）与 `_changeDate`（切日期）
  /// 会并发，先发的慢响应不能覆盖后发的结果。
  final RequestGuard _roomsGuard = RequestGuard();

  /// 网页端入口是否正在打开中（防止连点叠出多个遮罩/页面）
  bool _webBookingOpening = false;

  List<SpaceRoom> _rooms = const <SpaceRoom>[];
  List<SpaceReservation> _reservations = const <SpaceReservation>[];

  late DateTime _selectedDate;
  String _selectedBuilding = '全部场馆';
  String _selectedCapacityFilter = '全部'; // 全部, 单人间, 1~4人, 3~6人
  _ExpandedPanel _expandedPanel = _ExpandedPanel.none;
  int _reservationFilterIndex = 0; // 0: 全部, 1: 进行中, 2: 已结束

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final requestId = _roomsGuard.begin();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final sessionOk = await JwglAuth.instance.ensureSession();
    if (!mounted || !_roomsGuard.isCurrent(requestId)) return;
    final client = JwglAuth.instance.client;
    if (!sessionOk || client == null) {
      setState(() {
        _error = '请先在“我的”页面登录统一身份认证（CAS）后再使用空间预约';
        _loading = false;
      });
      return;
    }

    // 复用同一个 API 实例：每次重建都会丢掉 accessToken，导致每次都重走一遍
    // CAS 登录（1~2 秒）。只有 CAS 会话真的换了客户端对象时才重建。
    final existing = _api;
    if (existing == null || !identical(existing.casClient, client)) {
      _api = SpaceBookingApi(client);
    }
    final api = _api!;

    try {
      // 下拉刷新只是要新数据，不需要新 token。
      // 真正的过期由 `isTokenValid`（比例余量）和各接口的 401 重试兜底。
      final ok = await api.ensureAuthenticated();
      if (!mounted || !_roomsGuard.isCurrent(requestId)) return;
      if (!ok) {
        setState(() {
          _error = '统一身份认证（CAS）免密登录空间预约失败，请检查网络或登录 WebVPN 后重试';
          _loading = false;
        });
        return;
      }

      final dateStr = DateFmt.ymd(_selectedDate);
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        api.fetchRooms(date: dateStr),
        api.fetchMyReservations(),
      ]);

      if (!mounted || !_roomsGuard.isCurrent(requestId)) return;
      setState(() {
        _rooms = results[0] as List<SpaceRoom>;
        _reservations = results[1] as List<SpaceReservation>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || !_roomsGuard.isCurrent(requestId)) return;
      setState(() {
        // 接口层已经把「登录失效」「HTTP 失败」「解析失败」分开了，直接透出
        _error = e is SpaceBookingException
            ? e.message
            : '获取空间预约数据失败，请检查网络或登录 WebVPN 后重试';
        _loading = false;
      });
    }
  }

  Future<void> _changeDate(DateTime date) async {
    final requestId = _roomsGuard.begin();
    setState(() {
      _selectedDate = date;
      _loading = true;
      _error = null;
      _expandedPanel = _ExpandedPanel.none;
    });

    final api = _api;
    if (api == null) {
      // 首次登录就没成功时 `_api` 为 null：这里必须把 loading 收掉，
      // 否则页面会永久停在转圈，连错误提示都看不到。
      setState(() => _loading = false);
      return;
    }

    try {
      await api.ensureAuthenticated();
      if (!mounted || !_roomsGuard.isCurrent(requestId)) return;
      final rooms = await api.fetchRooms(date: DateFmt.ymd(date));
      if (!mounted || !_roomsGuard.isCurrent(requestId)) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || !_roomsGuard.isCurrent(requestId)) return;
      setState(() {
        // 切日期失败时不能保留上一天的列表，否则界面会变成「新日期 + 旧房间」，
        // 用户会照着错的可用状态去挑房间。
        _rooms = const <SpaceRoom>[];
        // 接口层已经把「登录失效」「HTTP 失败」「解析失败」分开了，直接透出
        _error = e is SpaceBookingException
            ? e.message
            : '获取空间预约数据失败，请检查网络或登录 WebVPN 后重试';
        _loading = false;
      });
    }
  }

  /// 房间容量分档。
  ///
  /// 原来三个分支的判定互相重叠：6 人间同时满足「1~4人」的
  /// `minNum <= 2 && maxNum <= 6` 和「3~6人」的 `maxNum >= 5 && minNum <= 6`，
  /// 同一间房会同时出现在两个筛选结果里。改成单一分档、以 maxNum 为准，
  /// 保证互斥，也让 chip 上的间数和列表对得上。
  String _capacityBucket(SpaceRoom r) {
    final isSingle =
        r.maxNum == 1 || r.name.contains('静音舱') || r.roomType.contains('单人');
    if (isSingle) return '单人间';
    if (r.maxNum >= 5) return '3~6人';
    return '1~4人';
  }

  bool _matchesBuilding(SpaceRoom r, String building) {
    if (building == '全部场馆' || building == '全部房间' || building == '全部') {
      return true;
    }
    return r.shortBuildingName == building ||
        r.buildingName.contains(building) ||
        r.name.contains(building);
  }

  bool _matchesCapacity(SpaceRoom r) {
    if (_selectedCapacityFilter == '全部') return true;
    return _capacityBucket(r) == _selectedCapacityFilter;
  }

  List<SpaceRoom> get _filteredRooms {
    return _rooms
        .where(
          (r) => _matchesBuilding(r, _selectedBuilding) && _matchesCapacity(r),
        )
        .toList();
  }

  List<String> get _availableBuildings {
    const canonicalOrder = <String>['全部场馆', '湛恩', '334号', '复兴', '1100号'];
    final present = <String>{'全部场馆'};
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
    // 统计要同时应用容量筛选，否则选了「1~4人」后 chip 写着「全部场馆 (37间)」，
    // 下面却只列出十几间。
    return _rooms
        .where((r) => _matchesBuilding(r, b) && _matchesCapacity(r))
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
      _initAndLoad();
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
      _initAndLoad();
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
      _initAndLoad();
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

  void _openRoomDetail(SpaceRoom room) {
    if (_api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpaceRoomDetailPage(
          room: room,
          initialDate: _selectedDate,
          api: _api!,
          onReservationCompleted: () => _initAndLoad(),
        ),
      ),
    );
  }

  /// 官方网页端入口（免密跳转）
  ///
  /// 网页端和 App 各自持有一套 CAS 会话：在网页里登录一次，很可能把 App
  /// 这边的 TGT 顶掉。所以出来之后必须重新校验一次，不能沿用网页打开前的状态。
  Future<void> _openWebBooking([SpaceRoom? room]) async {
    // 连点会叠出多个遮罩、多次 push，这里直接拦住
    if (_webBookingOpening) return;
    _webBookingOpening = true;
    try {
      final api = _api;
      final code = api == null
          ? null
          : await runWithBlockingProgress<String?>(
              context,
              '正在同步免密凭据...',
              () => api.acquireFreshAuthCode(
                redirectPath: room != null ? '/mStudent/room' : '/mStudent/index',
              ),
            );

      final dateStr = DateFmt.ymd(_selectedDate);
      // 授权码已解码，必须重新做百分号编码（含 '+'、'/'、'='）
      final webUrl = room != null
          ? SpaceWebUrl.room(roomId: room.id, date: dateStr, code: code)
          : SpaceWebUrl.index(code: code);

      final cookies =
          JwglAuth.instance.client?.jar.cookies ?? const <CasCookie>[];

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SimpleWebPage(
            title: room != null ? '网页预约 · ${room.name}' : '图书馆空间预约',
            url: webUrl,
            cookies: cookies,
          ),
        ),
      );

      // 从网页回来后重新同步。
      //
      // 关键：网页端的登录很可能已经把服务端会话换掉了。本地这个 token 按
      // 签发时间算还在 2 小时有效期内，但服务端已经认不出来——继续用只会一直
      // 拿到 400。所以先作废 token，逼一次重新认证。
      if (!mounted) return;
      _api?.invalidateToken();
      await _initAndLoad();
    } finally {
      _webBookingOpening = false;
    }
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
                onPressed: () => _initAndLoad(),
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
      onRefresh: () => _initAndLoad(),
      child: CustomScrollView(
        // 内容不满一屏时也要能下拉刷新
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          // 两行选项栏（第1行选择日期与场馆，点开原地拉出抽屉；第2行筛选 单人间 / 1~4人 / 3~6人）
          SliverToBoxAdapter(
            child: _buildControlsBar(),
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
                      _selectedBuilding == '全部场馆'
                          ? '当前筛选条件下暂无研讨空间'
                          : '【$_selectedBuilding】暂无匹配研讨空间',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                    if (_selectedBuilding != '全部场馆' || _selectedCapacityFilter != '全部') ...<Widget>[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _selectedBuilding = '全部场馆';
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

  /// 两行选项栏：第一行左边日期、右边场馆（点开后原地拉出一栏）；第二行容量筛选
  Widget _buildControlsBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 第一行：左边选择日期，右边选择场馆
          Row(
            children: <Widget>[
              // 左边：选择日期
              Expanded(
                child: _buildSelectorButton(
                  icon: Icons.calendar_today_rounded,
                  label: _dateDisplayLabel(_selectedDate),
                  isExpanded: _expandedPanel == _ExpandedPanel.date,
                  onTap: () {
                    setState(() {
                      _expandedPanel = _expandedPanel == _ExpandedPanel.date
                          ? _ExpandedPanel.none
                          : _ExpandedPanel.date;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              // 右边：选择场馆
              Expanded(
                child: _buildSelectorButton(
                  icon: Icons.apartment_rounded,
                  label: _selectedBuilding,
                  isExpanded: _expandedPanel == _ExpandedPanel.building,
                  onTap: () {
                    setState(() {
                      _expandedPanel = _expandedPanel == _ExpandedPanel.building
                          ? _ExpandedPanel.none
                          : _ExpandedPanel.building;
                    });
                  },
                ),
              ),
            ],
          ),

          // 原地拉出的展开抽屉
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _expandedPanel == _ExpandedPanel.none
                ? const SizedBox.shrink()
                : _buildExpandedDrawer(),
          ),

          const SizedBox(height: 10),

          // 第二行：筛选 单人间 1~4人 3~6人
          _buildCapacityFilterRow(),
        ],
      ),
    );
  }

  /// 选择器按钮（日期 / 场馆）
  Widget _buildSelectorButton({
    required IconData icon,
    required String label,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isExpanded ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isExpanded ? AppColors.usstRed : const Color(0xFFE2E8F0),
            width: isExpanded ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: isExpanded ? AppColors.usstRed : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isExpanded ? FontWeight.bold : FontWeight.w600,
                  color: isExpanded ? AppColors.usstRed : AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              isExpanded ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
              size: 22,
              color: isExpanded ? AppColors.usstRed : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 原地展开的抽屉面板
  Widget _buildExpandedDrawer() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
      ),
      child: _expandedPanel == _ExpandedPanel.date
          ? _buildDateDrawerContent()
          : _buildBuildingDrawerContent(),
    );
  }

  /// 日期展开面板内容
  Widget _buildDateDrawerContent() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = <DateTime>[
      today,
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 2)),
    ];
    const labels = <String>['今天', '明天', '后天'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < dates.length; i++) ...<Widget>[
              Expanded(
                child: _buildDrawerOptionChip(
                  label: '${labels[i]} ${DateFmt.md(dates[i])}',
                  isSelected: _selectedDate.year == dates[i].year &&
                      _selectedDate.month == dates[i].month &&
                      _selectedDate.day == dates[i].day,
                  onTap: () {
                    setState(() => _expandedPanel = _ExpandedPanel.none);
                    if (_selectedDate.year != dates[i].year ||
                        _selectedDate.month != dates[i].month ||
                        _selectedDate.day != dates[i].day) {
                      _changeDate(dates[i]);
                    }
                  },
                ),
              ),
              if (i < dates.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            setState(() => _expandedPanel = _ExpandedPanel.none);
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: today,
              lastDate: today.add(const Duration(days: 14)),
              builder: (ctx, child) {
                return Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppColors.usstRed,
                      onPrimary: Colors.white,
                      onSurface: AppColors.textPrimary,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              _changeDate(picked);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.7),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.edit_calendar_rounded, size: 14, color: AppColors.usstRed),
                SizedBox(width: 6),
                Text(
                  '在日历中挑选其他日期',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 场馆展开面板内容
  Widget _buildBuildingDrawerContent() {
    final buildings = _availableBuildings;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buildings.map((b) {
        final isSelected = b == _selectedBuilding;
        final count = _countForBuilding(b);
        String displayName = b;
        if (b == '湛恩') {
          displayName = '湛恩 ($count间)';
        } else if (b == '334号') {
          displayName = '334号南校区 ($count间)';
        } else if (b == '复兴') {
          displayName = '复兴路校区 ($count间)';
        } else if (b == '1100号') {
          displayName = '1100号校区 ($count间)';
        } else if (b == '全部场馆') {
          displayName = '全部场馆 ($count间)';
        } else {
          displayName = '$b ($count间)';
        }

        return _buildDrawerOptionChip(
          label: displayName,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedBuilding = b;
              _expandedPanel = _ExpandedPanel.none;
            });
          },
        );
      }).toList(),
    );
  }

  /// 原地展开抽屉选项 Chip
  Widget _buildDrawerOptionChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEE2E2) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.usstRed : const Color(0xFFCBD5E1),
            width: isSelected ? 1.2 : 0.7,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 第二行容量筛选选项条
  Widget _buildCapacityFilterRow() {
    const options = <String>['全部', '单人间', '1~4人', '3~6人'];
    return Row(
      children: options.map((opt) {
        final isSelected = _selectedCapacityFilter == opt;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedCapacityFilter = opt;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.usstRed : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 日期显示文本格式化（今天 MM-dd / 明天 MM-dd / 后天 MM-dd / MM-dd 周X）
  String _dateDisplayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = target.difference(today).inDays;

    final md = DateFmt.md(dt);

    if (diff == 0) {
      return '今天 $md';
    } else if (diff == 1) {
      return '明天 $md';
    } else if (diff == 2) {
      return '后天 $md';
    } else {
      const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final weekdayStr = weekdays[dt.weekday - 1];
      return '$md $weekdayStr';
    }
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

    // 之前这个 tab 完全不看 _error：登录失败或断网时显示「当前没有预约记录」，
    // 等于告诉用户"你的预约没了"。
    if (_error != null && _reservations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                onPressed: () => _initAndLoad(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredReservations;
    final activeCount = _reservations.where((r) => r.isUpcoming || r.isInProgress).length;
    final pastCount = _reservations.where((r) => r.isFinished || r.isCancelled).length;

    return RefreshIndicator(
      color: AppColors.usstRed,
      onRefresh: () => _initAndLoad(),
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
                // 空态也要可滚动，否则 RefreshIndicator 收不到滚动通知、拉不动
                ? LayoutBuilder(
                    builder: (ctx, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
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
                                    color: AppColors.textSecondary,
                                    fontSize: 14),
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
                        ),
                      ),
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
