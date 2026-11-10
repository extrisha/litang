import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:project_usst/app_theme.dart';
import 'package:project_usst/data/attachment_cache.dart';
import 'package:project_usst/pages/profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: '理堂',
      packageName: 'com.example.project_usst',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    directory = await Directory.systemTemp.createTemp('litang-profile-layout-');
    await Directory('${directory.path}/downloads').create();
    AttachmentCache.directoryOverride = () async => directory;
  });

  tearDown(() async {
    AttachmentCache.directoryOverride = null;
    await directory.delete(recursive: true);
  });

  testWidgets('320dp 双倍字体时五字网页入口完整位于可点击卡片内', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const ProfilePage(),
      ),
    );
    await tester.runAsync(AttachmentCache.refreshSize);
    await tester.pumpAndSettle();

    for (final label in ['学工一体化', '教务网页版']) {
      final text = find.text(label);
      await tester.ensureVisible(text);
      await tester.pumpAndSettle();

      final ink = find.ancestor(of: text, matching: find.byType(InkWell)).first;
      final card = find
          .ancestor(of: text, matching: find.byType(Material))
          .first;
      final textRect = tester.getRect(text);
      expect(tester.getRect(ink).contains(textRect.topLeft), isTrue);
      expect(tester.getRect(ink).contains(textRect.bottomRight), isTrue);
      expect(tester.getRect(card).contains(textRect.topLeft), isTrue);
      expect(tester.getRect(card).contains(textRect.bottomRight), isTrue);
      expect(tester.widget<InkWell>(ink).onTap, isNotNull);
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
      );
      expect(MediaQuery.textScalerOf(tester.element(text)).scale(13), 26);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('教务网页版'));
    await tester.pump();
    expect(find.text('请先登录教务系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(AttachmentCache.refreshSize);
  });
}
