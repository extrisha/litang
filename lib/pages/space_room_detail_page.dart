import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/jwc/space_booking_api.dart';
import 'simple_web_page.dart';

/// 研讨间详情与时段查看内页
class SpaceRoomDetailPage extends StatefulWidget {
  const SpaceRoomDetailPage({
    super.key,
    required this.room,
    required this.initialDate,
    required this.api,
  });

  final SpaceRoom room;
  final DateTime initialDate;
  final SpaceBookingApi api;

  @override
  State<SpaceRoomDetailPage> createState() => _SpaceRoomDetailPageState();
}

class _SpaceRoomDetailPageState extends State<SpaceRoomDetailPage> {
  late DateTime _selectedDate;
  bool _loading = false;
  String? _error;
  SpaceRoomDetail? _detail;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _loadDetail();
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取房间时段详情失败，空间预约系统仅限校园网访问，请连接校园内网或登录 WebVPN 后重试';
          _loading = false;
        });
      }
    }
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
          title: '预约 · ${widget.room.name}',
          url: webUrl,
        ),
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
          Row(
            children: <Widget>[
              _buildMetaTag(Icons.people_outline, room.capacityDesc),
              const SizedBox(width: 8),
              _buildMetaTag(Icons.meeting_room_outlined, room.roomType),
              const SizedBox(width: 8),
              _buildMetaTag(
                room.verify == 1 ? Icons.verified_user_outlined : Icons.lock_open_outlined,
                room.verify == 1 ? '须审核' : '免审核',
              ),
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
    final deviceList = room.devices
        .split(RegExp(r'[,，、;；\s]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

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
                  const SizedBox(width: 6),
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
  // 卡片 4: 实时时段切片与占用视图（抓取自官方接口）
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
              // 图例
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
            // 切片流（半小时 / 1小时一个单元）
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _detail!.timeSlices.map((slice) {
                final occupied = slice.isOccupied;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: occupied ? const Color(0xFFF3F4F6) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: occupied ? const Color(0xFFE5E7EB) : const Color(0xFFBBF7D0),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        occupied ? Icons.remove_circle_outline : Icons.check_circle_outline,
                        size: 13,
                        color: occupied ? const Color(0xFF9CA3AF) : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${slice.startTime}-${slice.endTime}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: occupied ? const Color(0xFF6B7280) : const Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            // 已占用时段列表（若存在）
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
                  room.isAvailable ? '时段充裕，可在线预约' : room.statusDesc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: room.isAvailable ? const Color(0xFF15803D) : const Color(0xFFDC2626),
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
            label: const Text(
              '前往官方预约',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            onPressed: _openWebBooking,
          ),
        ],
      ),
    );
  }
}
