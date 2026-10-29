import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'classroom/empty_classroom_tab.dart';
import 'classroom/school_course_tab.dart';
import 'simple_web_page.dart';

export 'classroom/empty_classroom_tab.dart';
export 'classroom/school_course_tab.dart';
export 'classroom/widgets/classroom_card.dart';
export 'classroom/widgets/classroom_filter_sheet.dart';
export 'classroom/widgets/school_course_card.dart';
export 'classroom/widgets/school_course_filter_sheet.dart';

/// 教室查询与全校排课一览页（双 Tab：空教室检索 + 全校课表检索）
class ClassroomQueryPage extends StatelessWidget {
  const ClassroomQueryPage({super.key});

  static const String webTimetableUrl =
      'https://lapp.usst.edu.cn/_web/_customizes/usst/schoolTimetable/mobile/permit/pc/pub/index.html';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('教室与排课'),
          actions: <Widget>[
            IconButton(
              tooltip: '原网页课表',
              icon: const Icon(Icons.language_outlined, size: 20),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SimpleWebPage(
                      title: '全校排课查询',
                      url: webTimetableUrl,
                    ),
                  ),
                );
              },
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
                text: '空教室',
              ),
              Tab(
                icon: Icon(Icons.calendar_view_week_outlined, size: 20),
                text: '全校课表',
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            EmptyClassroomTab(),
            SchoolCourseTab(),
          ],
        ),
      ),
    );
  }
}
