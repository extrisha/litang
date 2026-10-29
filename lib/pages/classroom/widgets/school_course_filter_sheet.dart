import 'package:flutter/material.dart';

import '../../../app_theme.dart';

const List<({String name, int day})> kCourseDays = <({String name, int day})>[
  (name: '周一', day: 1),
  (name: '周二', day: 2),
  (name: '周三', day: 3),
  (name: '周四', day: 4),
  (name: '周五', day: 5),
  (name: '周六', day: 6),
  (name: '周日', day: 7),
];

/// 选择开课学院弹窗
void showCollegePickerModal({
  required BuildContext context,
  required List<String> colleges,
  required String selectedCollege,
  required ValueChanged<String> onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.4,
        expand: false,
        builder: (sheetCtx, scrollController) {
          final allColleges = <String>['全部学院', ...colleges];
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      '选择开课学院',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.6),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: allColleges.length,
                  itemBuilder: (context, index) {
                    final college = allColleges[index];
                    final isSelected = selectedCollege == college;
                    return ListTile(
                      dense: true,
                      title: Text(
                        college,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.usstRed : AppColors.textPrimary,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: AppColors.usstRed, size: 20)
                          : null,
                      onTap: () {
                        onSelected(college);
                        Navigator.of(sheetCtx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// 选择培养层次（本科/研究生）
void showLevelPickerModal({
  required BuildContext context,
  required String selectedLevel,
  required ValueChanged<String> onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final options = <({String value, String label, String desc})>[
        (value: 'ALL', label: '本研不限', desc: '显示本科生与研究生全部课程'),
        (value: 'UNDERGRADUATE', label: '仅本科生', desc: '仅检索本科培养计划课程'),
        (value: 'GRADUATE', label: '仅研究生', desc: '仅检索硕士及博士研究生课程'),
      ];
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
                      '选择培养层次',
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
              ...options.map((opt) {
                final isSel = selectedLevel == opt.value;
                return InkWell(
                  onTap: () {
                    onSelected(opt.value);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFFFEF2F2) : Colors.transparent,
                      border: const Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.6)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          isSel ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSel ? AppColors.usstRed : const Color(0xFFD1D5DB),
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
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                  color: isSel ? AppColors.usstRed : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                opt.desc,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isSel
                                      ? AppColors.usstRed.withValues(alpha: 0.8)
                                      : AppColors.textSecondary,
                                ),
                              ),
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

/// 选择星期几弹窗
void showCourseDayPickerModal({
  required BuildContext context,
  required int selectedCourseDay,
  required ValueChanged<int> onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final options = <({int value, String label})>[
        (value: -1, label: '全部星期 (周一至周日)'),
        ...kCourseDays.map((d) => (value: d.day, label: d.name)),
      ];
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
                      '选择星期几',
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
              ...options.map((opt) {
                final isSel = selectedCourseDay == opt.value;
                return InkWell(
                  onTap: () {
                    onSelected(opt.value);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFFFEF2F2) : Colors.transparent,
                      border: const Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.6)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          isSel ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSel ? AppColors.usstRed : const Color(0xFFD1D5DB),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            color: isSel ? AppColors.usstRed : AppColors.textPrimary,
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

/// 选择教学周弹窗
void showCourseWeekPickerModal({
  required BuildContext context,
  required int currentWeek,
  required int selectedCourseWeek,
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        '选择教学周',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.6),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: selectedCourseWeek == -1
                              ? const Color(0xFFFEF2F2)
                              : Colors.white,
                          side: BorderSide(
                            color: selectedCourseWeek == -1
                                ? AppColors.usstRed
                                : const Color(0xFFE5E7EB),
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          onSelected(-1);
                          Navigator.of(ctx).pop();
                        },
                        child: Text(
                          '全部周次',
                          style: TextStyle(
                            color: selectedCourseWeek == -1
                                ? AppColors.usstRed
                                : AppColors.textPrimary,
                            fontWeight: selectedCourseWeek == -1
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: selectedCourseWeek == 0
                              ? const Color(0xFFFEF2F2)
                              : Colors.white,
                          side: BorderSide(
                            color: selectedCourseWeek == 0
                                ? AppColors.usstRed
                                : const Color(0xFFE5E7EB),
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          onSelected(0);
                          Navigator.of(ctx).pop();
                        },
                        child: Text(
                          '本周 (第$currentWeek周)',
                          style: TextStyle(
                            color: selectedCourseWeek == 0
                                ? AppColors.usstRed
                                : AppColors.textPrimary,
                            fontWeight: selectedCourseWeek == 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('指定教学周：',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List<Widget>.generate(20, (i) {
                    final w = i + 1;
                    final isSel = selectedCourseWeek == w;
                    return ChoiceChip(
                      label: Text('第$w周',
                          style: TextStyle(
                              fontSize: 12,
                              color: isSel ? Colors.white : AppColors.textPrimary)),
                      selected: isSel,
                      selectedColor: AppColors.usstRed,
                      backgroundColor: const Color(0xFFF3F4F6),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: isSel ? AppColors.usstRed : Colors.transparent),
                      ),
                      onSelected: (_) {
                        onSelected(w);
                        Navigator.of(ctx).pop();
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
