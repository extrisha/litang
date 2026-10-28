import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 理评：校园课程评价、避坑指南与搭子广场。
class ForumPage extends StatefulWidget {
  const ForumPage({super.key});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  int _tab = 0; // 0: 选课评价, 1: 课程搭子

  static const List<Map<String, dynamic>> _reviews = [
    {
      'course': '高等数学 (上)',
      'teacher': '理学院 · 张老师',
      'rating': '4.9',
      'tags': ['给分优厚', '划重点', '干货满满'],
      'comment': '老师板书非常清晰，考前会有针对性的重难点习题串讲。平时作业认真写、不缺勤，期末总评很厚道，强烈推荐！',
      'date': '2026-10',
    },
    {
      'course': '大学物理实验',
      'teacher': '基础物理实验中心',
      'rating': '4.3',
      'tags': ['规范预习', '早出数据早走', '注重动手'],
      'comment': '预习报告必须提前画好表格。做实验时注意仪器微调和有效数字规范，数据处理完给老师签字就可以提前离场。',
      'date': '2026-10',
    },
    {
      'course': '工程制图与CAD',
      'teacher': '机械学院 · 李老师',
      'rating': '4.7',
      'tags': ['耐心细致', 'CAD实操多', '大作业避坑'],
      'comment': '每周会有机房实操指导，期末的大作业模型早点搭，不要拖到最后一周渲染。老师答疑很耐心。',
      'date': '2026-09',
    },
  ];

  static const List<Map<String, String>> _partners = [
    {
      'course': '数据结构',
      'demand': '课程大作业找 2 名队友，一起做图算法与可视化部分',
      'people': '还差 2 人',
      'author': '22 计科 · 小王',
    },
    {
      'course': '大学物理实验',
      'demand': '求组队做双缝干涉实验，一起核对数据报告',
      'people': '还差 1 人',
      'author': '22 光电 · A 同学',
    },
    {
      'course': '机械设计基础',
      'demand': '想找人一起复习期末，约图书馆 3 楼自习室',
      'people': '队伍 3 人',
      'author': '22 机械 · 阿哲',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showContributeDialog(context),
        backgroundColor: AppColors.usstRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.rate_review_outlined, size: 19),
        label: Text(_tab == 0 ? '写课程点评' : '发布找搭子'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: <Widget>[
                  const Text(
                    '理评',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '选课避坑 · 校园参考',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  _tabSwitcher(),
                ],
              ),
            ),
            Expanded(
              child: _tab == 0 ? _reviewList() : _partnerList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFEBEBEB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _tabChip('课程点评', 0),
          _tabChip('找搭子', 1),
        ],
      ),
    );
  }

  Widget _tabChip(String title, int index) {
    final active = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: active
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _reviewList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _reviews.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _reviews[i];
        final tags = r['tags'] as List<String>;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    r['course'] as String,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFFD591)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFD46B08)),
                        const SizedBox(width: 2),
                        Text(
                          r['rating'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD46B08),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                r['teacher'] as String,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: tags.map((t) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                r['comment'] as String,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _partnerList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _partners.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = _partners[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.redTint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p['course']!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.usstRed,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    p['people']!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                p['demand']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p['author']!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showContributeDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const <Widget>[
            Text(
              '共建上理课程避坑指南',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 10),
            Text(
              '理评不设中心服务器，所有课程评价与经验建议由同学们匿名提交并定期整理发布到静态库中，零广告、离线可用。\n\n如需提供选课评价或搭子需求，欢迎联系开发者或通过校内匿名表单提交！',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
