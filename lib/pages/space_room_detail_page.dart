import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';
import '../data/date_format.dart';
import '../data/jwc/space_booking_api.dart';
import '../data/jwc/space_web_url.dart';
import '../data/request_guard.dart';
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

  /// [_detail] 的整点时段，加载成功时算一次缓存住。
  ///
  /// `SpaceRoomDetail.hourSlots` 是个重算 getter，直接在 `GridView.itemBuilder`
  /// 里访问会变成「每个格子重算一遍整表」，13 个时段就是每帧十几次全量分配。
  List<SpaceHourSlot> _hourSlots = const <SpaceHourSlot>[];

  /// 详情请求代次。切日期时会有多个请求同时在飞，先发的可能后到，
  /// 只允许「最新一次」的结果落到界面上，否则会出现「选中后天、显示明天」。
  final RequestGuard _detailGuard = RequestGuard();

  // 选中的时段
  String? _selectedStartTime;
  String? _selectedEndTime;

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
      final authed = await widget.api.ensureAuthenticated();
      if (!mounted || !_detailGuard.isCurrent(requestId)) return;
      // 登录失败和「当天没时段」在界面上必须能区分开，
      // 否则用户会以为房间真的没有空位。
      if (!authed) {
        setState(() {
          _error = '空间预约系统登录失败，请检查教务登录态后重试';
          _loading = false;
        });
        return;
      }
      final detail = await widget.api.fetchRoomReservationDetail(
        roomId: widget.room.id,
        date: dateStr,
      );

      // 晚到的旧响应必须丢掉，不能覆盖当前选中日期的数据
      if (!mounted || !_detailGuard.isCurrent(requestId)) return;

      final dateChanged = _detailDate != dateStr;
      setState(() {
        _detail = detail;
        _detailDate = dateStr;
        _hourSlots = detail?.hourSlots ?? const <SpaceHourSlot>[];
        _loading = false;
        if (dateChanged) {
          _initDefaultTimeSlot();
        } else if (_selectedStartTime != null &&
            _selectedEndTime != null &&
            (!_isSlotBookable(_selectedStartTime!) ||
                _hasTimeConflict(_selectedStartTime!, _selectedEndTime!))) {
          // 刷新同一天时保留用户的选择，但选中的区间如果已被别人占掉就得重置
          _initDefaultTimeSlot();
        }
      });
    } catch (e) {
      if (!mounted || !_detailGuard.isCurrent(requestId)) return;
      setState(() {
        _error = '获取房间时段详情失败，请检查网络或登录 WebVPN 后重试';
        _loading = false;
      });
    }
  }

  /// 这个整点是否还能选（存在、未被占、未过时）。
  bool _isSlotBookable(String startHour) {
    for (final slot in _hourSlots) {
      if (slot.startHour != startHour) continue;
      return !slot.isOccupied && !slot.isPastFor(_selectedDate);
    }
    return false;
  }

  /// 自动初始化一个合理的默认时间段（例如当前时间之后最近的一个1小时空闲时段）
  void _initDefaultTimeSlot() {
    for (final slot in _hourSlots) {
      if (slot.isOccupied || slot.isPastFor(_selectedDate)) continue;
      _selectedStartTime = slot.startHour;
      _selectedEndTime = slot.endHour;
      return;
    }

    _selectedStartTime = null;
    _selectedEndTime = null;
  }

  /// 点击选择整点时段
  void _onTapHourSlot(SpaceHourSlot slot) {
    if (slot.isOccupied || slot.isPastFor(_selectedDate)) return;

    setState(() {
      if (_selectedStartTime == null ||
          _selectedEndTime == null ||
          slot.startHour.compareTo(_selectedStartTime!) <= 0) {
        // 点击当前起始或更早的时段，重置为当前选中1小时
        _selectedStartTime = slot.startHour;
        _selectedEndTime = slot.endHour;
        return;
      }

      // 点击较晚的时段：尝试扩展
      final startH = int.tryParse(_selectedStartTime!.split(':').first) ?? 8;
      final endH = int.tryParse(slot.endHour.split(':').first) ?? 9;
      final durationHours = endH - startH;
      final maxAllowedHours = (widget.room.reservationMaxTime / 60).round();

      if (durationHours > maxAllowedHours) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('单次预约最多允许 $maxAllowedHours 小时')));
        return;
      }

      if (_hasTimeConflict(_selectedStartTime!, slot.endHour)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('所选区间包含已占用时段，无法选择')));
        return;
      }

      _selectedEndTime = slot.endHour;
    });
  }

  /// 检查所选时间段是否与已被占用的时段冲突
  bool _hasTimeConflict(String start, String end) {
    final booked = _detail?.bookedSegments ?? <SpaceBookedSegment>[];
    for (final b in booked) {
      // 若 [start, end) 与 [b.startTime, b.endTime) 有重叠
      if (start.compareTo(b.endTime) < 0 && end.compareTo(b.startTime) > 0) {
        return true;
      }
    }
    return false;
  }

  /// 免密跳转官方网页端直接预约该研讨间
  Future<void> _openWebBooking() async {
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: '网页端预约 · ${widget.room.name}',
          url: webUrl,
          cookies: cookies,
        ),
      ),
    );
  }

  /// 弹出原生预约配置表单底部抽屉
  void _openNativeBookingSheet(SpaceRoom room) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NativeBookingBottomSheet(
        room: room,
        selectedDate: _selectedDate,
        initialStartTime: _selectedStartTime,
        initialEndTime: _selectedEndTime,
        purposes: _purposes,
        bookedSegments: _detail?.bookedSegments ?? const <SpaceBookedSegment>[],
        timeSlices: _detail?.timeSlices ?? const <SpaceTimeSlice>[],
        api: widget.api,
        onSuccess: () {
          Navigator.of(ctx).pop();
          _loadDetail();
          widget.onReservationCompleted?.call();
          _showBookingSuccessDialog(room);
        },
        onFallbackWeb: () {
          Navigator.of(ctx).pop();
          _openWebBooking();
        },
      ),
    );
  }

  void _showBookingSuccessDialog(SpaceRoom room) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: <Widget>[
            Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
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
              '日期：${DateFmt.ymd(_selectedDate)}\n时段：${_selectedStartTime ?? ''} - ${_selectedEndTime ?? ''}',
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
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.access_time_filled,
                    color: Color(0xFFD97706),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '请务必在开场前20分钟至开场后20分钟内在门口刷卡或扫码签到，以免影响信用积分。',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF92400E),
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
                    if (currentRoom.deviceList.isNotEmpty) ...<Widget>[
                      _buildDevicesCard(currentRoom),
                      const SizedBox(height: 12),
                    ],
                    _buildRulesCard(currentRoom),
                    const SizedBox(height: 12),
                    _buildSlicesCard(currentRoom),
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
  // 日期快捷切换条（今天 / 明天 / 后天，共 3 天）
  // =========================================================================
  Widget _buildDateSelector() {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: List<Widget>.generate(candidateDates.length, (i) {
          final d = candidateDates[i];
          final isSelected =
              d.year == _selectedDate.year &&
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
                    setState(() {
                      _selectedDate = d;
                    });
                    _loadDetail();
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFDE8E8)
                        : const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.usstRed
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        DateFmt.md(d),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.usstRed
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? AppColors.usstRed
                              : AppColors.textSecondary,
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

  // =========================================================================
  // 卡片 1: 房间概览卡片
  // =========================================================================
  Widget _buildOverviewCard(SpaceRoom room) {
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
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  room.statusDesc,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: badgeText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.6, color: Color(0xFFEEEEEE)),
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
              if (room.spaceTime > 0)
                _buildMetaTag(Icons.timelapse_outlined, room.freeTimeDesc),
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
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE9ECEF), width: 0.6),
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
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dev,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF374151),
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
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A), width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.info_outline,
                    size: 15,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      room.label.isNotEmpty ? room.label : room.remark,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
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

  String _calculateDurationText(String start, String end) {
    final s = int.tryParse(start.split(':').first) ?? 0;
    final e = int.tryParse(end.split(':').first) ?? 0;
    final h = e - s;
    return h > 0 ? '共 $h 小时' : '';
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
              _buildLegend(
                const Color(0xFFDCFCE7),
                const Color(0xFF15803D),
                '可预约',
              ),
              const SizedBox(width: 8),
              _buildLegend(const Color(0xFFFEE2E2), AppColors.usstRed, '已选'),
              const SizedBox(width: 8),
              _buildLegend(
                const Color(0xFFF3F4F6),
                const Color(0xFF9CA3AF),
                '不可约',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.usstRed,
                  ),
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: <Widget>[
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loadDetail,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            )
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
                  bg = const Color(0xFFFEE2E2);
                  border = AppColors.usstRed;
                  textColor = AppColors.usstRed;
                  statusText = '已选中';
                  icon = Icons.check_circle_rounded;
                } else if (occupied) {
                  bg = const Color(0xFFF3F4F6);
                  border = const Color(0xFFE5E7EB);
                  textColor = const Color(0xFF9CA3AF);
                  statusText = slot.occupantDesc.isNotEmpty
                      ? slot.occupantDesc
                      : '已被约';
                  icon = Icons.lock_outline;
                } else if (isPast) {
                  bg = const Color(0xFFF9FAFB);
                  border = const Color(0xFFE5E7EB);
                  textColor = const Color(0xFF9CA3AF);
                  statusText = '已过时';
                  icon = Icons.history;
                } else {
                  bg = const Color(0xFFF0FDF4);
                  border = const Color(0xFFBBF7D0);
                  textColor = const Color(0xFF15803D);
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
            if (_selectedStartTime != null &&
                _selectedEndTime != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
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
                        '已选：$_selectedStartTime - $_selectedEndTime (${_calculateDurationText(_selectedStartTime!, _selectedEndTime!)})',
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
                      onPressed: () {
                        setState(() {
                          _selectedStartTime = null;
                          _selectedEndTime = null;
                        });
                      },
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
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.event_busy,
                          size: 14,
                          color: Color(0xFFEF4444),
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
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            seg.statusDesc,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFFB91C1C),
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
    final available = room.isAvailable;

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
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8)),
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
                  _selectedStartTime != null && _selectedEndTime != null
                      ? '已选：$_selectedStartTime - $_selectedEndTime (${_calculateDurationText(_selectedStartTime!, _selectedEndTime!)})'
                      : available
                      ? '点击上方时段卡片选择'
                      : room.statusDesc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: available
                        ? const Color(0xFF15803D)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.usstRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.event_available, size: 16),
            label: Text(
              available ? '立即预约' : '查看预约规则',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: available
                ? () => _openNativeBookingSheet(room)
                : _openWebBooking,
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
    required this.initialStartTime,
    required this.initialEndTime,
    required this.purposes,
    required this.bookedSegments,
    required this.timeSlices,
    required this.api,
    required this.onSuccess,
    required this.onFallbackWeb,
  });

  final SpaceRoom room;
  final DateTime selectedDate;
  final String? initialStartTime;
  final String? initialEndTime;
  final List<SpacePurpose> purposes;
  final List<SpaceBookedSegment> bookedSegments;
  final List<SpaceTimeSlice> timeSlices;
  final SpaceBookingApi api;
  final VoidCallback onSuccess;
  final VoidCallback onFallbackWeb;

  @override
  State<_NativeBookingBottomSheet> createState() =>
      _NativeBookingBottomSheetState();
}

class _NativeBookingBottomSheetState extends State<_NativeBookingBottomSheet> {
  late String _startHour;
  late int _durationHours;
  SpacePurpose? _selectedPurpose;
  final List<String> _memberIds = <String>[];
  final TextEditingController _memberInputCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();

  bool _submitting = false;
  String? _formError;

  List<String> get _openHours {
    final startH =
        int.tryParse(widget.room.openStartTime.split(':').first) ?? 8;
    final endH = int.tryParse(widget.room.openEndTime.split(':').first) ?? 21;
    final list = <String>[];
    for (var h = startH; h < endH; h++) {
      list.add('${h.toString().padLeft(2, '0')}:00');
    }
    return list;
  }

  /// 可选的开始时间：今天要滤掉已经过去的整点。
  ///
  /// 网格那边已经用 `isPastFor` 把过期时段置灰了，抽屉如果还全天可选，
  /// 就会出现「网格灰着、下拉能选、提交被服务端拒绝」。
  /// 判定口径与 `SpaceHourSlot.isPastFor` 保持一致（整点后 10 分钟算过期）。
  List<String> get _availableStartHours {
    final now = DateTime.now();
    final d = widget.selectedDate;
    final isToday =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (!isToday) return _openHours;
    return _openHours.where((hour) {
      final h = int.tryParse(hour.split(':').first) ?? 0;
      if (h < now.hour) return false;
      if (h == now.hour && now.minute >= 10) return false;
      return true;
    }).toList();
  }

  /// 下拉框候选项。`_startHour` 正常一定在 [_availableStartHours] 里，
  /// 但面板若停留跨过整点 10 分的边界就会失效；
  /// `DropdownButton` 要求 value 必须存在于 items 中，这里兜一层防止断言崩溃。
  List<String> get _startHourItems {
    final hours = _availableStartHours;
    if (hours.contains(_startHour)) return hours;
    return <String>[...hours, _startHour]..sort();
  }

  List<int> get _allowedDurations {
    final minH = (widget.room.reservationMinTime / 60).round().clamp(1, 4);
    final maxH = (widget.room.reservationMaxTime / 60).round().clamp(minH, 4);
    final list = <int>[];
    for (var d = minH; d <= maxH; d++) {
      list.add(d);
    }
    return list;
  }

  String get _endHour {
    final sH = int.tryParse(_startHour.split(':').first) ?? 8;
    final openEndH =
        int.tryParse(widget.room.openEndTime.split(':').first) ?? 21;
    final eH = (sH + _durationHours).clamp(sH + 1, openEndH);
    return '${eH.toString().padLeft(2, '0')}:00';
  }

  /// 与页面网格口径一致：占用既可能来自 `bookedSegments`，
  /// 也可能来自 `dateTimeSlicesList` 解析出的 `timeSlices`，两个都必须查。
  /// 只查前者会让「网格显示不可约、抽屉里却是绿的」这种情况漏过去。
  bool get _hasConflict {
    final end = _endHour;
    for (final b in widget.bookedSegments) {
      if (_startHour.compareTo(b.endTime) < 0 &&
          end.compareTo(b.startTime) > 0) {
        return true;
      }
    }
    for (final slice in widget.timeSlices) {
      if (!slice.isOccupied) continue;
      if (_startHour.compareTo(slice.endTime) < 0 &&
          end.compareTo(slice.startTime) > 0) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    // 先定开始时间，后面算时长候选时要用
    final initialStart = widget.initialStartTime;
    if (initialStart != null && initialStart.isNotEmpty) {
      final sH = int.tryParse(initialStart.split(':').first) ?? 8;
      _startHour = '${sH.toString().padLeft(2, '0')}:00';
    } else {
      final hours = _availableStartHours;
      _startHour = hours.isNotEmpty ? hours.first : '08:00';
    }

    final allowed = _allowedDurations;
    final minH = allowed.first;
    final maxH = allowed.last;

    final initialEnd = widget.initialEndTime;
    if (initialEnd != null && initialEnd.isNotEmpty) {
      final sH = int.tryParse(_startHour.split(':').first) ?? 8;
      final eH = int.tryParse(initialEnd.split(':').first) ?? (sH + minH);
      _durationHours = (eH - sH).clamp(minH, maxH);
    } else {
      _durationHours = minH;
    }

    // 默认用途
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

    // 验证学号是否存在
    final u = await widget.api.searchUser(input);
    if (!mounted) return;

    if (u == null) {
      // 容错：允许手动添加学号
      setState(() {
        _memberIds.add(input);
        _memberInputCtrl.clear();
        _formError = null;
      });
      return;
    }

    setState(() {
      _memberIds.add(input);
      _memberInputCtrl.clear();
      _formError = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _formError = null;
    });

    // 面板可能停留很久，或从网格带进来的开始时间在打开面板后已经过期
    if (!_availableStartHours.contains(_startHour)) {
      setState(() => _formError = '所选开始时间已过，请重新选择时段');
      return;
    }

    final end = _endHour;
    if (_hasConflict) {
      setState(() => _formError = '所选时间段 ($_startHour - $end) 与已有预约冲突，请重新选择');
      return;
    }

    // 检查人数
    final requiredMin = _selectedPurpose?.minNum ?? widget.room.minNum;
    final totalMembers = 1 + _memberIds.length;
    if (totalMembers < requiredMin) {
      setState(
        () => _formError =
            '【${_selectedPurpose?.label ?? '研讨'}】要求至少 $requiredMin 人同时预约（含本人还需添加 ${requiredMin - totalMembers} 名同行人）',
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    final dateStr = DateFmt.ymd(widget.selectedDate);
    final fullStart = '$dateStr $_startHour:00';
    final fullEnd = '$dateStr $end:00';
    final dictId = _selectedPurpose?.id ?? 1;

    final result = await widget.api.submitReservation(
      roomId: widget.room.id,
      startTime: fullStart,
      endTime: fullEnd,
      dictId: dictId,
      memberIds: _memberIds,
      mobile: _mobileCtrl.text.trim(),
      remark: _remarkCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
    });

    if (result.success) {
      widget.onSuccess();
    } else {
      setState(() {
        _formError = result.message;
      });
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '预约空间 · ${widget.room.name}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFmt.ymd(widget.selectedDate)} · ${widget.room.shortBuildingName} ${widget.room.floor}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
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
                        selectedColor: const Color(0xFFFEE2E2),
                        backgroundColor: const Color(0xFFF3F4F6),
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
                          if (val) {
                            setState(() => _selectedPurpose = p);
                          }
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
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: Color(0xFFD97706),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '未能加载预约用途列表，将按系统默认用途提交',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 2. 时段选择（整点小时）
                  const Text(
                    '预约时段（按小时整点预约）',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              '开始时间',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFD1D5DB),
                                ),
                                color: const Color(0xFFFAFAFA),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _startHour,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
                                  items: _startHourItems.map((h) {
                                    return DropdownMenuItem<String>(
                                      value: h,
                                      child: Text(
                                        h,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newStart) {
                                    if (newStart != null) {
                                      setState(() {
                                        _startHour = newStart;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              '预约时长',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: _allowedDurations.map((d) {
                                final isSelected = _durationHours == d;
                                return ChoiceChip(
                                  label: Text('$d小时'),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFFFEE2E2),
                                  backgroundColor: const Color(0xFFF3F4F6),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (val) {
                                    if (val) {
                                      setState(() => _durationHours = d);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _hasConflict
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _hasConflict
                            ? const Color(0xFFFECACA)
                            : const Color(0xFFBBF7D0),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _hasConflict
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          size: 16,
                          color: _hasConflict
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _hasConflict
                                ? '所选时段 $_startHour 至 $_endHour 已被占用，请更改'
                                : '预约时段：$_startHour 至 $_endHour (共 $_durationHours 小时)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _hasConflict
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF15803D),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

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
                        Text(
                          '最少 $requiredMin 人（已选 $totalCount 人）',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: totalCount >= requiredMin
                                ? const Color(0xFF16A34A)
                                : AppColors.usstRed,
                            fontWeight: FontWeight.w500,
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
                                  color: Color(0xFF9CA3AF),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF3F4F6),
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
                          backgroundColor: const Color(0xFFFEE2E2),
                          labelStyle: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.usstRed,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        ..._memberIds.map((mId) {
                          return Chip(
                            label: Text(mId),
                            backgroundColor: const Color(0xFFF3F4F6),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() => _memberIds.remove(mId));
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
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFD1D5DB),
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
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFD1D5DB),
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
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline,
                            size: 15,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFDC2626),
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
                        : const Text(
                            '确认提交预约',
                            style: TextStyle(
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
