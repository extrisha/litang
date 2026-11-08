import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/date_format.dart';
import '../data/jwc/space_booking_api.dart';
import '../data/jwc/space_booking_rules.dart';
import '../data/jwc/space_web_url.dart';
import '../data/request_guard.dart';
import '../widgets/async_state.dart';
import '../widgets/blocking_progress.dart';
import 'simple_web_page.dart';

/// 研讨间详情与时段查看/预约内页
class SpaceRoomDetailPage extends StatefulWidget {
  const SpaceRoomDetailPage({
    super.key,
    required this.room,
    required this.initialDate,
    required this.api,
    this.onReservationCompleted,
  });

  final SpaceRoom room;
  final DateTime initialDate;
  final SpaceBookingApi api;
  final VoidCallback? onReservationCompleted;

  @override
  State<SpaceRoomDetailPage> createState() => _SpaceRoomDetailPageState();
}

class _SpaceRoomDetailPageState extends State<SpaceRoomDetailPage> {
  late DateTime _selectedDate;
  bool _loading = false;
  String? _error;
  SpaceRoomDetail? _detail;
  List<SpacePurpose> _purposes = const <SpacePurpose>[];

  /// [_detail] 对应的是哪一天（YYYY-MM-DD）。
  /// 用来区分「切换日期」和「刷新同一天」——前者要重置选中时段，后者不该清掉用户的选择。
  String? _detailDate;

  /// 当前日期的整点时段（来自 `SpaceRoomDetail.hourSlots`，模型层已缓存）。
  List<SpaceHourSlot> _hourSlots = const <SpaceHourSlot>[];

  /// 时段表位置：底部「去选时段」用它把用户滚到时段表。
  final GlobalKey _slotsKey = GlobalKey();

  /// 详情请求代次。切日期时会有多个请求同时在飞，先发的可能后到，
  /// 只允许「最新一次」的结果落到界面上，否则会出现「选中后天、显示明天」。
  final RequestGuard _detailGuard = RequestGuard();

  // 选中的时段
  String? _selectedStartTime;
  String? _selectedEndTime;

  /// 网页端入口是否正在打开（防止连点叠出多个遮罩/页面）
  bool _webBookingOpening = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _loadDetail();
    _loadPurposes();
  }

  Future<void> _loadPurposes() async {
    try {
      final pList = await widget.api.fetchPurposes();
      if (mounted) {
        setState(() {
          _purposes = pList;
        });
      }
    } catch (e) {
      // 用途字典拉不到时不阻塞页面，但也不该完全无声：
      // 抽屉里会提示「将按系统默认用途提交」，避免静默用错 dictId。
      debugPrint('[space] 拉取预约用途失败: $e');
    }
  }

  Future<void> _loadDetail() async {
    final requestId = _detailGuard.begin();
    setState(() {
      _loading = true;
      _error = null;
    });

    final dateStr = DateFmt.ymd(_selectedDate);
    try {
      // fetchRoomReservationDetail 失败时会抛（不再吞成 null），
      // 所以「登录失败 / 网络失败」和「当天确实没有时段」能区分开。
      final detail = await widget.api.fetchRoomReservationDetail(
        roomId: widget.room.id,
        date: dateStr,
      );

      // 晚到的旧响应必须丢掉，不能覆盖当前选中日期的数据
      if (!mounted || !_detailGuard.isCurrent(requestId)) return;

      if (detail == null) {
        setState(() {
          _detail = null;
          _detailDate = null;
          _hourSlots = const <SpaceHourSlot>[];
          _selectedStartTime = null;
          _selectedEndTime = null;
          _error = '未取到该空间 $dateStr 的时段数据，请点重试';
          _loading = false;
        });
        return;
      }

      final dateChanged = _detailDate != dateStr;
      setState(() {
        _detail = detail;
        _detailDate = dateStr;
        _hourSlots = detail.hourSlots;
        _loading = false;
        // 默认不选中任何时段：用户点哪个整点就选哪个，再点一次取消。
        // 刷新同一天时保留仍然有效的选择，被占掉/过时了才清空。
        final current = _selection;
        if (dateChanged ||
            (current != null &&
                !_isRangeFree(current.startHour, current.endHour))) {
          _selectedStartTime = null;
          _selectedEndTime = null;
        }
      });
    } catch (e) {
      if (!mounted || !_detailGuard.isCurrent(requestId)) return;
      setState(() {
        _detail = null;
        _detailDate = null;
        _hourSlots = const <SpaceHourSlot>[];
        _selectedStartTime = null;
        _selectedEndTime = null;
        _error = e is SpaceBookingException
            ? e.message
            : '获取房间时段详情失败，请检查网络或登录 WebVPN 后重试';
        _loading = false;
      });
    }
  }

  /// 当前选中的区间；未选或数据不完整时返回 null。
  SpaceSlotSelection? get _selection {
    final start = _selectedStartTime;
    final end = _selectedEndTime;
    if (start == null || end == null) return null;
    final startH = int.tryParse(start.split(':').first);
    final endH = int.tryParse(end.split(':').first);
    if (startH == null || endH == null || endH <= startH) return null;
    return SpaceSlotSelection(startHour: startH, endHour: endH);
  }

  /// 当天实际生效的房间数据：详情接口返回的比列表快照更新。
  SpaceRoom get _room => _detail?.room ?? widget.room;

  int get _openEndHour =>
      int.tryParse(_room.openEndTime.split(':').first) ?? 21;

  void _applySelection(SpaceSlotSelection? selection) {
    setState(() {
      _selectedStartTime = selection?.startLabel;
      _selectedEndTime = selection?.endLabel;
    });
  }

  /// 区间内每个整点都能约（存在、未被占、未过时、未超出闭馆时间）。
  bool _isRangeFree(int startHour, int endHour) {
    if (endHour <= startHour || endHour > _openEndHour) return false;
    for (var h = startHour; h < endHour; h++) {
      SpaceHourSlot? found;
      for (final slot in _hourSlots) {
        if (slot.startHour == SpaceSlotSelection.labelOf(h)) {
          found = slot;
          break;
        }
      }
      if (found == null || found.isOccupied || found.isPastFor(_selectedDate)) {
        return false;
      }
    }
    return true;
  }

  /// 当前日期是否还有至少一个「满足最短时长」的可约起点。
  bool get _hasBookableSlot {
    final minH = SpaceBookingRules.minHoursFromMinutes(
      _room.reservationMinTime,
    );
    for (final slot in _hourSlots) {
      if (slot.isOccupied || slot.isPastFor(_selectedDate)) continue;
      final h = int.tryParse(slot.startHour.split(':').first);
      if (h == null) continue;
      if (_isRangeFree(h, h + minH)) return true;
    }
    return false;
  }

  int get _freeHourCount => _hourSlots
      .where((s) => !s.isOccupied && !s.isPastFor(_selectedDate))
      .length;

  /// 房间状态以「当天真实时段」为准。
  ///
  /// 详情接口返回的房间对象里没有 `spaceTime`（被解析成 0），直接读
  /// `statusDesc` 会永远显示「已约满」——这就是右上角那个莫名其妙的状态。
  ({String text, Color bg, Color fg}) _statusStyle(SpaceRoom room) {
    if (room.status == 1) {
      return (
        text: '已禁用',
        bg: AppColors.surfaceMuted,
        fg: AppColors.textSecondary,
      );
    }
    if (room.status == 2) {
      return (
        text: '维护中',
        bg: AppColors.surfaceMuted,
        fg: AppColors.textSecondary,
      );
    }
    if (_loading) {
      return (
        text: '加载中',
        bg: AppColors.surfaceMuted,
        fg: AppColors.textSecondary,
      );
    }
    if (_detail == null) {
      return (
        text: '数据未取到',
        bg: AppColors.surfaceMuted,
        fg: AppColors.textSecondary,
      );
    }
    if (_hasBookableSlot) {
      return (text: '可预约', bg: AppColors.successBg, fg: AppColors.successText);
    }
    return (
      text: '当天无可约时段',
      bg: AppColors.warningBg,
      fg: AppColors.warningText,
    );
  }

  /// 点击一个整点：选中 / 延长 / 再点开始时段取消。
  void _onTapHourSlot(SpaceHourSlot slot) {
    if (slot.isOccupied || slot.isPastFor(_selectedDate)) return;

    final hour = int.tryParse(slot.startHour.split(':').first);
    if (hour == null) return;

    final room = _room;
    final result = SpaceSlotSelection.tap(
      current: _selection,
      tappedHour: hour,
      openEndHour: _openEndHour,
      minDurationHours: SpaceBookingRules.minHoursFromMinutes(
        room.reservationMinTime,
      ),
      maxDurationHours: SpaceBookingRules.maxHoursFromMinutes(
        room.reservationMaxTime,
      ),
      isRangeFree: _isRangeFree,
    );

    if (result.error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }

    _applySelection(result.selection);
  }

  /// 把页面滚动到时段表（底部「去选时段」用）。
  void _scrollToSlots() {
    final ctx = _slotsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  /// 免密跳转官方网页端直接预约该研讨间
  Future<void> _openWebBooking() async {
    if (_webBookingOpening) return;
    _webBookingOpening = true;
    try {
      // 遮罩交给 runWithBlockingProgress：任务无论成功、失败还是抛异常都会关掉，
      // 不会留下一个点不动的全屏挡住页面退不出去。
      final code = await runWithBlockingProgress<String?>(
        context,
        '正在同步免密凭据...',
        () => widget.api.acquireFreshAuthCode(redirectPath: '/mStudent/room'),
      );

      // 授权码已解码，必须重新做百分号编码（含 '+'、'/'、'='）
      final webUrl = SpaceWebUrl.room(
        roomId: widget.room.id,
        date: DateFmt.ymd(_selectedDate),
        code: code,
      );

      final cookies =
          JwglAuth.instance.client?.jar.cookies ?? const <CasCookie>[];

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SimpleWebPage(
            title: '网页端预约 · ${widget.room.name}',
            url: webUrl,
            cookies: cookies,
          ),
        ),
      );

      // 网页端可能已经占用/释放了时段，回来必须重新拉一次，
      // 否则用户看到的是进网页之前的旧时段状态。
      if (!mounted) return;
      await _loadDetail();
    } finally {
      _webBookingOpening = false;
    }
  }

  /// 弹出原生预约配置表单底部抽屉
  void _openNativeBookingSheet(SpaceRoom room) {
    final selection = _selection;
    if (selection == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先在上方时段表中选择预约时间')));
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NativeBookingBottomSheet(
        room: room,
        selectedDate: _selectedDate,
        selection: selection,
        purposes: _purposes,
        bookedSegments: _detail?.bookedSegments ?? const <SpaceBookedSegment>[],
        timeSlices: _detail?.timeSlices ?? const <SpaceTimeSlice>[],
        api: widget.api,
        onSuccess: (start, end) {
          Navigator.of(ctx).pop();
          _loadDetail();
          widget.onReservationCompleted?.call();
          _showBookingSuccessDialog(room, start: start, end: end);
        },
        onFallbackWeb: () {
          Navigator.of(ctx).pop();
          _openWebBooking();
        },
      ),
    );
  }

  void _showBookingSuccessDialog(
    SpaceRoom room, {
    required String start,
    required String end,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: <Widget>[
            Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 28,
            ),
            SizedBox(width: 10),
            Text(
              '预约成功',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '您已成功预约【${room.name}】',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '日期：${DateFmt.ymd(_selectedDate)}\n时段：$start - $end',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.access_time_filled,
                    color: AppColors.warning,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '请务必在开场前20分钟至开场后20分钟内在门口刷卡或扫码签到，以免影响信用积分。',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // 返回上一页
            },
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentRoom = _detail?.room ?? widget.room;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(currentRoom.name),
        actions: <Widget>[
          IconButton(
            tooltip: '网页端预约',
            icon: const Icon(Icons.language_outlined, size: 22),
            onPressed: _openWebBooking,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildDateSelector(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.usstRed,
              onRefresh: _loadDetail,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildOverviewCard(currentRoom),
                    const SizedBox(height: 12),
                    // 时段选择是主操作，放在设施/规则之前，避免用户先滚一屏才看到。
                    KeyedSubtree(
                      key: _slotsKey,
                      child: _buildSlicesCard(currentRoom),
                    ),
                    const SizedBox(height: 12),
                    if (currentRoom.deviceList.isNotEmpty) ...<Widget>[
                      _buildDevicesCard(currentRoom),
                      const SizedBox(height: 12),
                    ],
                    _buildRulesCard(currentRoom),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomBar(currentRoom),
        ],
      ),
    );
  }

  // =========================================================================
  // 日期快捷切换条（今天 / 明天 / 后天 + 日历）
  // =========================================================================

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final quickDates = <DateTime>[
      today,
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 2)),
    ];
    const labels = <String>['今天', '明天', '后天'];
    final selectedIsQuick = quickDates.any((d) => _isSameDay(d, _selectedDate));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < quickDates.length; i++) ...<Widget>[
                    _buildDateChip(
                      date: quickDates[i],
                      label: labels[i],
                      isSelected: _isSameDay(quickDates[i], _selectedDate),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 日历可选未来 14 天，选到快捷项之外时补一个 chip；
                  // 否则三个快捷项全不高亮，用户看不出当前看的是哪天。
                  if (!selectedIsQuick)
                    _buildDateChip(
                      date: _selectedDate,
                      label: '已选',
                      isSelected: true,
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '选择其他日期',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.edit_calendar_rounded,
              size: 20,
              color: AppColors.usstRed,
            ),
            onPressed: _pickDate,
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateChip({
    required DateTime date,
    required String label,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: isSelected
          ? null
          : () {
              setState(() => _selectedDate = date);
              _loadDetail();
            },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.dangerBg : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.usstRed : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              DateFmt.md(date),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.usstRed : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
    if (picked == null || !mounted) return;
    if (_isSameDay(picked, _selectedDate)) return;
    setState(() {
      _selectedDate = picked;
      _selectedStartTime = null;
      _selectedEndTime = null;
    });
    await _loadDetail();
  }

  // =========================================================================
  // 卡片 1: 房间概览卡片
  // =========================================================================
  Widget _buildOverviewCard(SpaceRoom room) {
    // 不再读 `room.statusDesc`：详情接口的房间对象没有 `spaceTime`，
    // 会被解析成 0 并误判成「已约满」。状态一律按当天时段算。
    final status = _statusStyle(room);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.locationDesc.isNotEmpty
                          ? room.locationDesc
                          : (room.buildingName.isNotEmpty
                                ? room.buildingName
                                : '校内研讨室'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: status.bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: status.fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.6, color: AppColors.divider),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _buildMetaTag(Icons.people_outline, room.capacityDesc),
              _buildMetaTag(Icons.meeting_room_outlined, room.roomType),
              _buildMetaTag(
                room.verify == 1
                    ? Icons.verified_user_outlined
                    : Icons.lock_open_outlined,
                room.verify == 1 ? '须审核' : '免审核',
              ),
              if (_detail != null && !_loading)
                _buildMetaTag(
                  Icons.timelapse_outlined,
                  _freeHourCount > 0 ? '当天可约 $_freeHourCount 小时' : '当天无可约时段',
                )
              else if (_loading)
                _buildMetaTag(Icons.hourglass_empty, '时段加载中'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 卡片 2: 设施配置
  // =========================================================================
  Widget _buildDevicesCard(SpaceRoom room) {
    final deviceList = room.deviceList;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.devices_outlined, size: 16, color: AppColors.usstRed),
              SizedBox(width: 6),
              Text(
                '设施与配置',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: deviceList.map((dev) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4.5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dev,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 卡片 3: 使用与预约规则
  // =========================================================================
  Widget _buildRulesCard(SpaceRoom room) {
    final minHours = (room.reservationMinTime / 60).toStringAsFixed(
      room.reservationMinTime % 60 == 0 ? 0 : 1,
    );
    final maxHours = (room.reservationMaxTime / 60).toStringAsFixed(
      room.reservationMaxTime % 60 == 0 ? 0 : 1,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.rule_outlined, size: 16, color: AppColors.usstRed),
              SizedBox(width: 6),
              Text(
                '预约与使用规则',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRuleRow(
            Icons.access_time_outlined,
            '开放时段',
            '${room.openStartTime} - ${room.openEndTime}',
          ),
          const SizedBox(height: 8),
          _buildRuleRow(
            Icons.timelapse_outlined,
            '预约时长',
            '单次 $minHours ~ $maxHours 小时（按小时整点预约）',
          ),
          const SizedBox(height: 8),
          _buildRuleRow(
            Icons.pin_outlined,
            '签到规则',
            '开场前 ${room.minSignTime} 分钟至开场后 ${room.maxSignTime} 分钟内须签到',
          ),
          const SizedBox(height: 8),
          _buildRuleRow(
            Icons.pause_circle_outline,
            '暂离规则',
            '使用中暂离最长 ${room.leaveMaxTime} 分钟，超时将自动释放',
          ),
          if (room.label.isNotEmpty || room.remark.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warningFaint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warningBorder, width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.info_outline,
                    size: 15,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      room.label.isNotEmpty ? room.label : room.remark,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRuleRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 卡片 4: 实时时段分布卡片（按小时整点颗粒度）
  // =========================================================================
  Widget _buildSlicesCard(SpaceRoom room) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              const Icon(
                Icons.calendar_view_day_outlined,
                size: 16,
                color: AppColors.usstRed,
              ),
              const SizedBox(width: 6),
              const Text(
                '当日时段预约',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _buildLegend(AppColors.successBg, AppColors.successText, '可预约'),
              const SizedBox(width: 8),
              _buildLegend(AppColors.dangerBg, AppColors.usstRed, '已选'),
              const SizedBox(width: 8),
              _buildLegend(AppColors.surfaceMuted, AppColors.textMuted, '不可约'),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const AsyncStateView(loading: true, compact: true)
          else if (_error != null)
            AsyncStateView(error: _error, onRetry: _loadDetail, compact: true)
          else if (_detail != null && _hourSlots.isNotEmpty) ...<Widget>[
            // 1小时整点颗粒度时段网格
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.7,
              ),
              itemCount: _hourSlots.length,
              itemBuilder: (ctx, idx) {
                final slot = _hourSlots[idx];
                final occupied = slot.isOccupied;
                final isPast = slot.isPastFor(_selectedDate);
                final isSelected =
                    (_selectedStartTime != null && _selectedEndTime != null) &&
                    (slot.startHour.compareTo(_selectedStartTime!) >= 0 &&
                        slot.endHour.compareTo(_selectedEndTime!) <= 0);
                final isAvailable = !occupied && !isPast;

                Color bg;
                Color border;
                Color textColor;
                String statusText;
                IconData icon;

                if (isSelected) {
                  bg = AppColors.dangerBg;
                  border = AppColors.usstRed;
                  textColor = AppColors.usstRed;
                  statusText = '已选中';
                  icon = Icons.check_circle_rounded;
                } else if (occupied) {
                  bg = AppColors.surfaceMuted;
                  border = AppColors.border;
                  textColor = AppColors.textMuted;
                  statusText = slot.occupantDesc.isNotEmpty
                      ? slot.occupantDesc
                      : '已被约';
                  icon = Icons.lock_outline;
                } else if (isPast) {
                  bg = AppColors.surfaceSubtle;
                  border = AppColors.border;
                  textColor = AppColors.textMuted;
                  statusText = '已过时';
                  icon = Icons.history;
                } else {
                  bg = AppColors.successFaint;
                  border = AppColors.successBorderSoft;
                  textColor = AppColors.successText;
                  statusText = '可预约';
                  icon = Icons.radio_button_unchecked;
                }

                return InkWell(
                  onTap: isAvailable ? () => _onTapHourSlot(slot) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: border,
                        width: isSelected ? 1.4 : 0.8,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(icon, size: 16, color: textColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                slot.timeRange,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: textColor.withValues(alpha: 0.85),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_selection != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: AppColors.usstRed,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '已选：${_selection!.startLabel} - ${_selection!.endLabel}（共 ${_selection!.durationHours} 小时）',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _applySelection(null),
                      child: const Text(
                        '重置',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 10),
              const Row(
                children: <Widget>[
                  Icon(
                    Icons.touch_app_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '点选时段开始预约；再点一次已选中的时段可取消',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // 已占用明细
            if (_detail!.bookedSegments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              const Text(
                '已被占用时段明细：',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Column(
                children: _detail!.bookedSegments.map((seg) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceFaint,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border, width: 0.6),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.event_busy,
                          size: 14,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          seg.timeRange,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.dangerBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            seg.statusDesc,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ] else ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text(
                room.allTime == 1 ? '该空间当天全天开放可预约' : '当天暂无开放时段信息',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend(Color bg, Color text, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: text.withValues(alpha: 0.4), width: 0.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: text)),
      ],
    );
  }

  // =========================================================================
  // 底部固定操作栏
  // =========================================================================
  Widget _buildBottomBar(SpaceRoom room) {
    final selection = _selection;
    // 列表页拿到的 `spaceTime` 只代表进页面那一刻；切到别的日期后并不可信。
    // 真正能不能约要看当前日期拉到的整点时段。
    final canBook =
        room.status == 0 && !_loading && _detail != null && _hasBookableSlot;

    final String hint;
    final Color hintColor;
    if (_loading) {
      hint = '正在加载当天时段...';
      hintColor = AppColors.textSecondary;
    } else if (!canBook) {
      hint = _detail == null
          ? '未取到当天时段，请下拉刷新或点重试'
          : room.status != 0
          ? _statusStyle(room).text
          : '当天已无可约时段，可到网页端查看';
      hintColor = AppColors.danger;
    } else if (selection == null) {
      hint = '先在下方时段表里点选预约时间（再点一次可取消）';
      hintColor = AppColors.textSecondary;
    } else {
      hint =
          '已选：${selection.startLabel} - ${selection.endLabel}（共 ${selection.durationHours} 小时）';
      hintColor = AppColors.successText;
    }

    // 没选时段时按钮改成「去选时段」并把页面滚到时段表，
    // 而不是给一个点不动的禁用按钮。
    final String buttonLabel;
    final IconData buttonIcon;
    final VoidCallback? onPressed;
    if (canBook) {
      if (selection == null) {
        buttonLabel = '去选时段';
        buttonIcon = Icons.touch_app_outlined;
        onPressed = _scrollToSlots;
      } else {
        buttonLabel = '去预约';
        buttonIcon = Icons.event_available;
        onPressed = () => _openNativeBookingSheet(room);
      }
    } else {
      buttonLabel = '网页端查看';
      buttonIcon = Icons.open_in_new;
      onPressed = _openWebBooking;
    }

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  DateFmt.ymd(_selectedDate),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: hintColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.surfaceMuted,
              disabledForegroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            icon: Icon(buttonIcon, size: 16),
            label: Text(
              // 标签必须和真实动作一致：
              // - 可约但未选时段 → 禁用（表单只接受已选时段）
              // - 当天没有可约时段 → 网页端查看
              buttonLabel,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

/// 原生快速预约底部抽屉
class _NativeBookingBottomSheet extends StatefulWidget {
  const _NativeBookingBottomSheet({
    required this.room,
    required this.selectedDate,
    required this.selection,
    required this.purposes,
    required this.bookedSegments,
    required this.timeSlices,
    required this.api,
    required this.onSuccess,
    required this.onFallbackWeb,
  });

  final SpaceRoom room;
  final DateTime selectedDate;

  /// 用户在时段表上选好的区间。表单不再自带开始时间/时长控件——
  /// 那套控件与网格各算各的，会出现「选中了 10:00-12:00，表单里却是别的时段」。
  final SpaceSlotSelection selection;
  final List<SpacePurpose> purposes;
  final List<SpaceBookedSegment> bookedSegments;
  final List<SpaceTimeSlice> timeSlices;
  final SpaceBookingApi api;

  /// 预约成功回调，带上**实际提交**的开始/结束时间。
  final void Function(String start, String end) onSuccess;
  final VoidCallback onFallbackWeb;

  @override
  State<_NativeBookingBottomSheet> createState() =>
      _NativeBookingBottomSheetState();
}

class _NativeBookingBottomSheetState extends State<_NativeBookingBottomSheet> {
  SpacePurpose? _selectedPurpose;
  final List<String> _memberIds = <String>[];

  /// 同行成员学号 → 姓名（查到时展示「张三 (2312xxx)」，查不到只显示学号）
  final Map<String, String> _memberNames = <String, String>{};
  final TextEditingController _memberInputCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();

  bool _submitting = false;
  bool _submissionUnconfirmed = false;
  String? _formError;

  /// 当前用途允许的最长整点小时数；null 表示不限。
  int? get _purposeMaxHours {
    final maxTime = _selectedPurpose?.maxTime;
    if (maxTime == null || maxTime <= 0) return null;
    return SpaceBookingRules.maxHoursFromMinutes(maxTime);
  }

  bool get _exceedsPurposeMax {
    final maxH = _purposeMaxHours;
    return maxH != null && widget.selection.durationHours > maxH;
  }

  /// 与页面网格口径一致：占用既可能来自 `bookedSegments`，
  /// 也可能来自 `dateTimeSlicesList` 解析出的 `timeSlices`，两个都必须查。
  bool get _hasConflict {
    final start = widget.selection.startLabel;
    final end = widget.selection.endLabel;
    for (final b in widget.bookedSegments) {
      if (start.compareTo(b.endTime) < 0 && end.compareTo(b.startTime) > 0) {
        return true;
      }
    }
    for (final slice in widget.timeSlices) {
      if (!slice.isOccupied) continue;
      if (start.compareTo(slice.endTime) < 0 &&
          end.compareTo(slice.startTime) > 0) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    // 默认用途：静音舱等单人间优先「单人研习」，其余优先「研讨交流」。
    if (widget.purposes.isNotEmpty) {
      if (widget.room.maxNum == 1) {
        _selectedPurpose = widget.purposes.firstWhere(
          (p) => p.label.contains('单人'),
          orElse: () => widget.purposes.first,
        );
      } else {
        _selectedPurpose = widget.purposes.firstWhere(
          (p) => p.label.contains('研讨'),
          orElse: () => widget.purposes.first,
        );
      }

      // 用户可能在时段表上选了 4 小时，而默认用途最长只有 2 小时。
      // 换成一个放得下的用途（取最长），避免一打开表单就是错误状态。
      if (_exceedsPurposeMax) {
        final fitting = widget.purposes.where((p) {
          final maxTime = p.maxTime;
          return maxTime <= 0 ||
              SpaceBookingRules.maxHoursFromMinutes(maxTime) >=
                  widget.selection.durationHours;
        }).toList();
        if (fitting.isNotEmpty) {
          _selectedPurpose = fitting.reduce(
            (a, b) => a.maxTime >= b.maxTime ? a : b,
          );
        }
      }
    }

    if (widget.api.userProfile != null &&
        widget.api.userProfile!.mobile.isNotEmpty) {
      _mobileCtrl.text = widget.api.userProfile!.mobile;
    }
  }

  @override
  void dispose() {
    _memberInputCtrl.dispose();
    _mobileCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    if (_submitting) return;
    final input = _memberInputCtrl.text.trim();
    if (input.isEmpty) return;

    if (input == widget.api.userId) {
      setState(() => _formError = '无需添加自己为同行成员');
      return;
    }

    if (_memberIds.contains(input)) {
      setState(() => _formError = '该学号已被添加');
      return;
    }

    // 人数上限：服务端会拒绝超额预约，这里提前拦住，
    // 避免用户填完一串信息、提交后才看到报错。
    final maxNum = widget.room.maxNum;
    if (maxNum > 0 && 1 + _memberIds.length >= maxNum) {
      setState(() => _formError = '该空间最多 $maxNum 人，无法再添加同行成员');
      return;
    }

    // 查学号：null = 查无此人；异常 = 查询失败。两种情况必须分开提示，
    // 原来「查不到也照样加进去」会把手误学号带进提交，被服务端整单拒绝。
    Map<String, dynamic>? user;
    try {
      user = await widget.api.searchUser(input);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = e is SpaceBookingException ? e.message : '查询同学信息失败，请稍后重试';
      });
      return;
    }
    if (!mounted) return;

    if (user == null) {
      setState(() => _formError = '未找到学号 $input 的同学，请核对后重试');
      return;
    }

    final name =
        (user['realName'] ?? user['userName'] ?? user['nickName'] ?? '')
            .toString()
            .trim();
    setState(() {
      _memberIds.add(input);
      if (name.isNotEmpty) _memberNames[input] = name;
      _memberInputCtrl.clear();
      _formError = null;
    });
  }

  /// 表单错误：同时写进错误条 + 弹一条 SnackBar。
  ///
  /// 抽屉内容可能被滚到顶部，底部错误条不一定在视野里；只写错误条时
  /// 用户会觉得「点了提交没反应」。
  void _showFormError(String message) {
    if (!mounted) return;
    setState(() => _formError = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _formError = null;
    });

    final selection = widget.selection;

    // 面板可能停留很久：选中的开始时间可能已经过了。
    if (SpaceBookingRules.isPastHour(
      selection.startHour,
      widget.selectedDate,
      DateTime.now(),
    )) {
      _showFormError('所选开始时间已过，请关闭本页重新选择时段');
      return;
    }

    if (_hasConflict) {
      _showFormError(
        '所选时段 (${selection.startLabel} - ${selection.endLabel}) 已被占用，请关闭本页刷新后重选',
      );
      return;
    }

    if (_exceedsPurposeMax) {
      _showFormError(
        '【${_selectedPurpose?.label ?? '当前用途'}】最长 $_purposeMaxHours 小时，当前选择 ${selection.durationHours} 小时，请返回重选时段',
      );
      return;
    }

    // 检查人数
    final requiredMin = _selectedPurpose?.minNum ?? widget.room.minNum;
    final totalMembers = 1 + _memberIds.length;
    if (totalMembers < requiredMin) {
      _showFormError(
        '【${_selectedPurpose?.label ?? '研讨'}】要求至少 $requiredMin 人同时预约（含本人还需添加 ${requiredMin - totalMembers} 名同行人）',
      );
      return;
    }
    if (widget.room.maxNum > 0 && totalMembers > widget.room.maxNum) {
      _showFormError('该空间最多 ${widget.room.maxNum} 人，当前已选 $totalMembers 人');
      return;
    }

    // 联系电话：选填，但填了就要是合法手机号，避免服务端静默丢弃通知。
    final mobile = _mobileCtrl.text.trim();
    if (mobile.isNotEmpty && !RegExp(r'^1\d{10}$').hasMatch(mobile)) {
      _showFormError('联系电话格式不正确，请填写 11 位手机号');
      return;
    }

    setState(() {
      _submitting = true;
    });

    final dateStr = DateFmt.ymd(widget.selectedDate);
    final fullStart = '$dateStr ${selection.startLabel}:00';
    final fullEnd = '$dateStr ${selection.endLabel}:00';
    final dictId = _selectedPurpose?.id ?? 1;

    late ReservationResult result;
    try {
      result = await widget.api.submitReservation(
        roomId: widget.room.id,
        startTime: fullStart,
        endTime: fullEnd,
        dictId: dictId,
        memberIds: _memberIds,
        mobile: mobile,
        remark: _remarkCtrl.text.trim(),
      );
    } catch (e) {
      if (mounted) _showFormError('无法提交预约，请检查登录状态和网络后重试');
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }

    if (!mounted) return;
    setState(() {
      _submissionUnconfirmed = result.outcomeUnknown;
    });

    if (result.success) {
      widget.onSuccess(selection.startLabel, selection.endLabel);
    } else {
      _showFormError(result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final requiredMin = _selectedPurpose?.minNum ?? widget.room.minNum;
    final totalCount = 1 + _memberIds.length;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 顶部栏
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '预约空间 · ${widget.room.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateFmt.ymd(widget.selectedDate)} · ${widget.room.shortBuildingName} ${widget.room.floor}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(height: 16, thickness: 0.6),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 0. 已选时段（来自时段表，表单里只读）
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _hasConflict
                          ? AppColors.redTintBg
                          : AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _hasConflict
                            ? AppColors.dangerBorder
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _hasConflict
                              ? Icons.error_outline
                              : Icons.event_available,
                          size: 18,
                          color: _hasConflict
                              ? AppColors.danger
                              : AppColors.usstRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '预约时段：${widget.selection.startLabel} - ${widget.selection.endLabel}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _hasConflict
                                    ? '该时段刚刚被占用，请关闭本页刷新后重选'
                                    : '共 ${widget.selection.durationHours} 小时 · 需调整请关闭本页在时段表上重选',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _hasConflict
                                      ? AppColors.danger
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            '重选',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 1. 用途选择
                  const Text(
                    '预约用途',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.purposes.map((p) {
                      final isSelected = _selectedPurpose?.id == p.id;
                      return ChoiceChip(
                        label: Text(p.label),
                        selected: isSelected,
                        selectedColor: AppColors.dangerBg,
                        backgroundColor: AppColors.surfaceMuted,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppColors.usstRed
                              : AppColors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.usstRed
                              : Colors.transparent,
                        ),
                        onSelected: (val) {
                          if (!val) return;
                          setState(() => _selectedPurpose = p);
                        },
                      );
                    }).toList(),
                  ),
                  // 用途字典没拉到时不阻塞预约，但要明确告诉用户会用默认用途，
                  // 而不是静默按 dictId=1 提交（可能用错用途被拒且提示莫名）。
                  if (widget.purposes.isEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warningBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: AppColors.warning,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '未能加载预约用途列表，将按系统默认用途提交',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.warningText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 2. 用途时长校验（时间在时段表上选，表单不再重复提供控件）
                  if (_exceedsPurposeMax) ...<Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline,
                            size: 15,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '【${_selectedPurpose?.label ?? '当前用途'}】最长 $_purposeMaxHours 小时，当前选择 ${widget.selection.durationHours} 小时。请换用途或返回重选时段。',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 3. 同行成员（若需要）
                  if (requiredMin > 1) ...<Widget>[
                    Row(
                      children: <Widget>[
                        const Text(
                          '同行成员',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '最少 $requiredMin 人，最多 ${widget.room.maxNum} 人（已选 $totalCount 人）',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: totalCount >= requiredMin
                                  ? AppColors.success
                                  : AppColors.usstRed,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: TextField(
                              controller: _memberInputCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '输入同行同学学号',
                                hintStyle: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: AppColors.borderStrong,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceMuted,
                            foregroundColor: AppColors.textPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: _addMember,
                          child: const Text(
                            '添加',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        Chip(
                          avatar: const Icon(
                            Icons.person,
                            size: 14,
                            color: AppColors.usstRed,
                          ),
                          label: Text('${widget.api.realName ?? '本人'} (主约人)'),
                          backgroundColor: AppColors.dangerBg,
                          labelStyle: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.usstRed,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        ..._memberIds.map((mId) {
                          final name = _memberNames[mId];
                          return Chip(
                            label: Text(
                              name == null || name.isEmpty
                                  ? mId
                                  : '$name ($mId)',
                            ),
                            backgroundColor: AppColors.surfaceMuted,
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() {
                                _memberIds.remove(mId);
                                _memberNames.remove(mId);
                              });
                            },
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 4. 联系手机 & 备注
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              '联系电话',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _mobileCtrl,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '用于接收通知',
                                  hintStyle: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: AppColors.borderStrong,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              '预约备注',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _remarkCtrl,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '如 自习、研讨',
                                  hintStyle: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: AppColors.borderStrong,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_formError != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline,
                            size: 15,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 提交按钮
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.usstRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _submissionUnconfirmed ? '查询预约结果' : '确认提交预约',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: widget.onFallbackWeb,
              child: const Text(
                '需要上传证明或改用官方网页端预约',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
