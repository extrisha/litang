import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../data/calendar/calendar_service.dart';
import '../../../data/jwc/classroom_api.dart';
import '../../../data/jwc/classroom_data.dart';

String getSectionTimeDesc(SectionOption opt) {
  switch (opt.label) {
    case '1-2节 (上午)':
      return '08:00 - 09:35 · 上午第1大节';
    case '3-5节 (上午)':
      return '09:55 - 12:20 · 上午第2大节';
    case '6-7节 (下午)':
      return '13:30 - 15:05 · 下午第1大节';
    case '8-10节 (下午)':
      return '15:25 - 17:50 · 下午第2大节';
    case '11-13节 (晚上)':
      return '18:30 - 20:55 · 晚间课程';
    default:
      return '全天课表及教室占用';
  }
}

/// 选择教学楼弹窗
void showBuildingPickerModal({
  required BuildContext context,
  required String selectedBuilding,
  required ValueChanged<String> onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      '选择教学楼',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.6, color: Color(0xFFF3F4F6)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: allKnownBuildings.map((b) {
                    final isSelected = selectedBuilding == b;
                    final displayName = b == '全部教学楼'
                        ? '全部教学楼'
                        : b
                            .replaceAll('第一教学楼', '一教')
                            .replaceAll('第三教学楼', '三教')
                            .replaceAll('第四教学楼', '四教');
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        if (selectedBuilding != b) {
                          onSelected(b);
                        }
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFEF2F2) : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppColors.usstRed : const Color(0xFFE5E7EB),
                            width: isSelected ? 1.4 : 0.8,
                          ),
                        ),
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 选择时段节次弹窗
void showSectionPickerModal({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      '选择时段节次',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.6, color: Color(0xFFF3F4F6)),
              ...List<Widget>.generate(defaultSectionOptions.length, (i) {
                final opt = defaultSectionOptions[i];
                final isSelected = selectedIndex == i;
                return InkWell(
                  onTap: () {
                    if (selectedIndex != i) {
                      onSelected(i);
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent,
                      border: const Border(
                        bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.6),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected ? AppColors.usstRed : const Color(0xFFD1D5DB),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                opt.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                                ),
                              ),
                              if (opt.range != null) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  getSectionTimeDesc(opt),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isSelected
                                        ? AppColors.usstRed.withValues(alpha: 0.8)
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },
  );
}

/// 选择周次与星期弹窗
void showDatePickerModal({
  required BuildContext context,
  required int selectedWeek,
  required int selectedDay,
  required void Function(int week, int day) onConfirmed,
}) {
  final currentWeek = CalendarService.instance.currentWeek ?? 1;
  final nowWeekday = DateTime.now().weekday;

  int tempWeek = selectedWeek;
  int tempDay = selectedDay;

  const days = <({String name, int day})>[
    (name: '周一', day: 1),
    (name: '周二', day: 2),
    (name: '周三', day: 3),
    (name: '周四', day: 4),
    (name: '周五', day: 5),
    (name: '周六', day: 6),
    (name: '周日', day: 7),
  ];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (sheetCtx, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          '选择周次与星期',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.usstRed,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('今天与当前周', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            setModalState(() {
                              tempWeek = currentWeek.clamp(1, 20);
                              tempDay = nowWeekday;
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 16, thickness: 0.6),
                    const Text(
                      '教学周',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 20,
                        itemBuilder: (context, i) {
                          final w = i + 1;
                          final isSel = tempWeek == w;
                          final isCur = w == currentWeek;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                isCur ? '第$w周(本周)' : '第$w周',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: isSel ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppColors.usstRed,
                              backgroundColor: const Color(0xFFF3F4F6),
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isSel ? AppColors.usstRed : Colors.transparent,
                                ),
                              ),
                              onSelected: (_) {
                                setModalState(() => tempWeek = w);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '星期',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: days.map((d) {
                        final isSel = tempDay == d.day;
                        final isToday = d.day == nowWeekday;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setModalState(() => tempDay = d.day),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? AppColors.usstRed
                                      : (isToday ? const Color(0xFFFEF2F2) : const Color(0xFFF7F8FA)),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSel
                                        ? AppColors.usstRed
                                        : (isToday ? const Color(0xFFFECACA) : const Color(0xFFE5E7EB)),
                                    width: isSel ? 1.2 : 0.8,
                                  ),
                                ),
                                child: Column(
                                  children: <Widget>[
                                    Text(
                                      d.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            (isSel || isToday) ? FontWeight.bold : FontWeight.normal,
                                        color: isSel
                                            ? Colors.white
                                            : (isToday ? AppColors.usstRed : AppColors.textPrimary),
                                      ),
                                    ),
                                    if (isToday)
                                      Text(
                                        '今天',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: isSel ? Colors.white70 : AppColors.usstRed,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.usstRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          onConfirmed(tempWeek, tempDay);
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('确定',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
