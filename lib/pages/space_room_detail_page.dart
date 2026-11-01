import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/jwc/space_booking_api.dart';
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

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _loadPurposes() async {
    try {
      final pList = await widget.api.fetchPurposes();
      if (mounted) {
        setState(() {
          _purposes = pList;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final dateStr = _formatDate(_selectedDate);
    try {
      final detail = await widget.api.fetchRoomReservationDetail(
        roomId: widget.room.id,
        date: dateStr,
      );

      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
          _initDefaultTimeSlot(detail?.room ?? widget.room);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取房间时段详情失败，请检查网络或登录 WebVPN 后重试';
          _loading = false;
        });
      }
    }
  }

  /// 自动初始化一个合理的默认时间段（例如当前时间之后最近的一个空闲时段）
  void _initDefaultTimeSlot(SpaceRoom room) {
    final slices = _detail?.timeSlices ?? <SpaceTimeSlice>[];
    if (slices.isEmpty) return;

    // 寻找第一个连续空闲至少 reservationMinTime 的区间
    final freeSlots = slices.where((s) => !s.isOccupied).toList();
    if (freeSlots.isNotEmpty) {
      _selectedStartTime = freeSlots.first.startTime;
      // 默认时长为最短时长（如 60 分钟 = 6个10分钟切片）
      final stepCount = (room.reservationMinTime / 10).round();
      final startIdx = slices.indexWhere((s) => s.startTime == _selectedStartTime);
      if (startIdx != -1 && startIdx + stepCount <= slices.length) {
        // 检查该区间是否全部空闲
        final candidate = slices.sublist(startIdx, startIdx + stepCount);
        if (!candidate.any((s) => s.isOccupied)) {
          _selectedEndTime = candidate.last.endTime;
          return;
        }
      }
      _selectedEndTime = freeSlots.length >= 6 ? freeSlots[5].endTime : freeSlots.last.endTime;
    }
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

    final code = await widget.api.acquireFreshAuthCode(
      redirectPath: '/mStudent/room',
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    final dateStr = _formatDate(_selectedDate);
    final webUrl = (code != null && code.isNotEmpty)
        ? 'https://libspace.usst.edu.cn/mStudent/room?roomId=${widget.room.id}&date=$dateStr&code=$code'
        : 'https://libspace.usst.edu.cn/mStudent/room?roomId=${widget.room.id}&date=$dateStr';

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleWebPage(
          title: '网页端预约 · ${widget.room.name}',
          url: webUrl,
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
            Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 28),
            SizedBox(width: 10),
            Text('预约成功', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '您已成功预约【${room.name}】',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              '日期：${_formatDate(_selectedDate)}\n时段：${_selectedStartTime ?? ''} - ${_selectedEndTime ?? ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
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
                  Icon(Icons.access_time_filled, color: Color(0xFFD97706), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '请务必在开场前20分钟至开场后20分钟内在门口刷卡或扫码签到，以免影响信用积分。',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    if (currentRoom.devices.isNotEmpty) ...<Widget>[
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
                    color: isSelected ? const Color(0xFFFDE8E8) : const Color(0xFFF4F4F5),
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
                      '${room.buildingName.isNotEmpty ? room.buildingName : room.shortBuildingName} · ${room.floor}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                room.verify == 1 ? Icons.verified_user_outlined : Icons.lock_open_outlined,
                room.verify == 1 ? '须审核' : '免审核',
              ),
              if (room.spaceTime > 0)
                _buildMetaTag(Icons.timelapse_outlined, '剩余空闲 ${room.spaceTime} 分钟'),
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
            style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dev,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
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
    final minHours = (room.reservationMinTime / 60).toStringAsFixed(room.reservationMinTime % 60 == 0 ? 0 : 1);
    final maxHours = (room.reservationMaxTime / 60).toStringAsFixed(room.reservationMaxTime % 60 == 0 ? 0 : 1);

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
            '单次 $minHours ~ $maxHours 小时 (${room.reservationMinTime} - ${room.reservationMaxTime} 分钟)',
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
                  const Icon(Icons.info_outline, size: 15, color: Color(0xFFD97706)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      room.label.isNotEmpty ? room.label : room.remark,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
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
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
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
  // 卡片 4: 实时时段分布卡片
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
              const Icon(Icons.calendar_view_day_outlined, size: 16, color: AppColors.usstRed),
              const SizedBox(width: 6),
              const Text(
                '实时时段分布',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _buildLegend(const Color(0xFFDCFCE7), const Color(0xFF15803D), '空闲'),
              const SizedBox(width: 10),
              _buildLegend(const Color(0xFFF3F4F6), const Color(0xFF9CA3AF), '已占用'),
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
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.usstRed),
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
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
          else if (_detail != null && _detail!.timeSlices.isNotEmpty) ...<Widget>[
            // 时段切片流（支持点击快速选择）
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _detail!.timeSlices.map((slice) {
                final occupied = slice.isOccupied;
                final isSelected = (_selectedStartTime != null && _selectedEndTime != null) &&
                    (slice.startTime.compareTo(_selectedStartTime!) >= 0 &&
                        slice.endTime.compareTo(_selectedEndTime!) <= 0);

                Color bg;
                Color border;
                Color textColor;

                if (occupied) {
                  bg = const Color(0xFFF3F4F6);
                  border = const Color(0xFFE5E7EB);
                  textColor = const Color(0xFF9CA3AF);
                } else if (isSelected) {
                  bg = const Color(0xFFFEE2E2);
                  border = AppColors.usstRed;
                  textColor = AppColors.usstRed;
                } else {
                  bg = const Color(0xFFF0FDF4);
                  border = const Color(0xFFBBF7D0);
                  textColor = const Color(0xFF15803D);
                }

                return InkWell(
                  onTap: occupied
                      ? null
                      : () {
                          setState(() {
                            // 若尚未选择，或者点选了比开始还早的时段，重设开始时间
                            if (_selectedStartTime == null ||
                                (_selectedEndTime != null && slice.startTime.compareTo(_selectedStartTime!) <= 0)) {
                              _selectedStartTime = slice.startTime;
                              _selectedEndTime = slice.endTime;
                            } else {
                              // 尝试扩展结束时间
                              if (!_hasTimeConflict(_selectedStartTime!, slice.endTime)) {
                                _selectedEndTime = slice.endTime;
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('所选区间包含已占用时段，无法选择')),
                                );
                              }
                            }
                          });
                        },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: border, width: isSelected ? 1.2 : 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          occupied
                              ? Icons.remove_circle_outline
                              : isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                          size: 13,
                          color: textColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${slice.startTime}-${slice.endTime}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_selectedStartTime != null && _selectedEndTime != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.touch_app_outlined, size: 16, color: AppColors.usstRed),
                    const SizedBox(width: 6),
                    Text(
                      '已选时段：$_selectedStartTime - $_selectedEndTime',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
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
                      child: const Text('重置', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Column(
                children: _detail!.bookedSegments.map((seg) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE5E7EB), width: 0.6),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.event_busy, size: 14, color: Color(0xFFEF4444)),
                        const SizedBox(width: 6),
                        Text(
                          seg.timeRange,
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            seg.statusDesc,
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFB91C1C)),
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
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
        Text(
          label,
          style: TextStyle(fontSize: 11, color: text),
        ),
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
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _formatDate(_selectedDate),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedStartTime != null && _selectedEndTime != null
                      ? '已选时段：$_selectedStartTime - $_selectedEndTime'
                      : available
                          ? '点击上方切片或直接预约'
                          : room.statusDesc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: available ? const Color(0xFF15803D) : const Color(0xFFDC2626),
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
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            onPressed: available ? () => _openNativeBookingSheet(room) : _openWebBooking,
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
  State<_NativeBookingBottomSheet> createState() => _NativeBookingBottomSheetState();
}

class _NativeBookingBottomSheetState extends State<_NativeBookingBottomSheet> {
  late String _startTime;
  late String _endTime;
  SpacePurpose? _selectedPurpose;
  final List<String> _memberIds = <String>[];
  final TextEditingController _memberInputCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();

  bool _submitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _startTime = widget.initialStartTime ?? widget.room.openStartTime;
    _endTime = widget.initialEndTime ?? _calculateDefaultEndTime(_startTime);

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

    if (widget.api.userProfile != null && widget.api.userProfile!.mobile.isNotEmpty) {
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

  String _calculateDefaultEndTime(String start) {
    final parts = start.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? 8;
      final m = int.tryParse(parts[1]) ?? 0;
      final minDuration = widget.room.reservationMinTime;
      final totalMin = h * 60 + m + minDuration;
      final endH = (totalMin ~/ 60).toString().padLeft(2, '0');
      final endM = (totalMin % 60).toString().padLeft(2, '0');
      return '$endH:$endM';
    }
    return widget.room.openEndTime;
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

    if (_startTime.compareTo(_endTime) >= 0) {
      setState(() => _formError = '结束时间必须晚于开始时间');
      return;
    }

    // 检查冲突
    for (final b in widget.bookedSegments) {
      if (_startTime.compareTo(b.endTime) < 0 && _endTime.compareTo(b.startTime) > 0) {
        setState(() => _formError = '所选时间段与已有预约 (${b.timeRange}) 冲突');
        return;
      }
    }

    // 检查人数
    final requiredMin = _selectedPurpose?.minNum ?? widget.room.minNum;
    final totalMembers = 1 + _memberIds.length;
    if (totalMembers < requiredMin) {
      setState(() => _formError = '【${_selectedPurpose?.label ?? '研讨'}】要求至少 $requiredMin 人同时预约（含本人还需添加 ${requiredMin - totalMembers} 名同行人）');
      return;
    }

    setState(() {
      _submitting = true;
    });

    final dateStr = _formatDate(widget.selectedDate);
    final fullStart = '$dateStr $_startTime:00';
    final fullEnd = '$dateStr $_endTime:00';
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
                    '${_formatDate(widget.selectedDate)} · ${widget.room.shortBuildingName} ${widget.room.floor}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
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
                  const Text('预约用途', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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
                          color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppColors.usstRed : Colors.transparent,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedPurpose = p);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 2. 时段选择
                  const Text('预约起止时间', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _buildTimeInputBox('开始时间', _startTime, (newVal) {
                          setState(() {
                            _startTime = newVal;
                            _endTime = _calculateDefaultEndTime(_startTime);
                          });
                        }),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('至', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        child: _buildTimeInputBox('结束时间', _endTime, (newVal) {
                          setState(() => _endTime = newVal);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 3. 同行成员（若需要）
                  if (requiredMin > 1) ...<Widget>[
                    Row(
                      children: <Widget>[
                        const Text('同行成员', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        const SizedBox(width: 8),
                        Text(
                          '最少 $requiredMin 人（已选 $totalCount 人）',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: totalCount >= requiredMin ? const Color(0xFF16A34A) : AppColors.usstRed,
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
                                hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: _addMember,
                          child: const Text('添加', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        Chip(
                          avatar: const Icon(Icons.person, size: 14, color: AppColors.usstRed),
                          label: Text('${widget.api.realName ?? '本人'} (主约人)'),
                          backgroundColor: const Color(0xFFFEE2E2),
                          labelStyle: const TextStyle(fontSize: 11.5, color: AppColors.usstRed),
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
                            const Text('联系电话', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _mobileCtrl,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '用于接收通知',
                                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
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
                            const Text('预约备注', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _remarkCtrl,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '如 自习、研讨',
                                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
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
                          const Icon(Icons.error_outline, size: 15, color: Color(0xFFDC2626)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('确认提交预约', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: widget.onFallbackWeb,
              child: const Text('需要上传证明或改用官方网页端预约', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeInputBox(String label, String value, ValueChanged<String> onChanged) {
    return InkWell(
      onTap: () async {
        final parts = value.split(':');
        final initH = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 8) : 8;
        final initM = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: initH, minute: initM),
        );
        if (picked != null) {
          final hh = picked.hour.toString().padLeft(2, '0');
          final mm = picked.minute.toString().padLeft(2, '0');
          onChanged('$hh:$mm');
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Row(
          children: <Widget>[
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const Spacer(),
            const Icon(Icons.access_time, size: 16, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
