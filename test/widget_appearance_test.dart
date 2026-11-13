import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/widget_appearance.dart';

void main() {
  group('WidgetAppearance', () {
    test('默认磨砂玻璃 85%', () {
      const appearance = WidgetAppearance.defaults;
      expect(appearance.style, WidgetStyle.glass);
      expect(appearance.alpha, 85);
      expect(appearance.effectiveAlpha, 85);
      expect(appearance.label, '磨砂玻璃');
    });

    test('fromPrefs 能还原三种风格', () {
      for (final style in WidgetStyle.values) {
        final appearance = WidgetAppearance.fromPrefs(style.name, 70);
        expect(appearance.style, style);
        expect(appearance.alpha, 70);
      }
    });

    test('fromPrefs 遇到脏数据退回默认', () {
      expect(
        WidgetAppearance.fromPrefs('holographic', 85).style,
        WidgetStyle.glass,
      );
      expect(WidgetAppearance.fromPrefs(null, null).alpha, 85);
      expect(WidgetAppearance.fromPrefs('glass', 'not-a-number').alpha, 85);
    });

    test('fromPrefs 把越界透明度夹到 40–100', () {
      expect(WidgetAppearance.fromPrefs('glass', 5).alpha, 40);
      expect(WidgetAppearance.fromPrefs('glass', 999).alpha, 100);
      expect(WidgetAppearance.fromPrefs('glass', -20).alpha, 40);
    });

    test('fromPrefs 接受字符串数字（SharedPreferences 可能给 String）', () {
      expect(WidgetAppearance.fromPrefs('glass', '62').alpha, 62);
    });

    test('copyWith 会夹住透明度', () {
      const appearance = WidgetAppearance.defaults;
      expect(appearance.copyWith(alpha: 10).alpha, 40);
      expect(appearance.copyWith(alpha: 1000).alpha, 100);
      expect(
        appearance.copyWith(style: WidgetStyle.solid).style,
        WidgetStyle.solid,
      );
    });

    test('三种风格都有可读的名字和说明', () {
      for (final style in WidgetStyle.values) {
        final appearance = WidgetAppearance(style: style);
        expect(appearance.label, isNotEmpty);
        expect(appearance.description, isNotEmpty);
      }
    });

    test('默认视图是课表，提前提示 45 分钟', () {
      const appearance = WidgetAppearance.defaults;
      expect(appearance.viewMode, WidgetViewMode.schedule);
      expect(appearance.upcomingMinutes, 45);
      expect(appearance.effectiveUpcoming, 45);
    });

    test('fromPrefs 能还原待办模式与提前量', () {
      final appearance = WidgetAppearance.fromPrefs(
        'glass',
        85,
        rawViewMode: 'todo',
        rawUpcoming: 30,
      );
      expect(appearance.viewMode, WidgetViewMode.todo);
      expect(appearance.upcomingMinutes, 30);
    });

    test('fromPrefs 脏数据：视图退回课表、提前量退回 45', () {
      final appearance = WidgetAppearance.fromPrefs(
        'glass',
        85,
        rawViewMode: 'weather',
        rawUpcoming: 'oops',
      );
      expect(appearance.viewMode, WidgetViewMode.schedule);
      expect(appearance.upcomingMinutes, 45);
    });

    test('提前量夹在 0–120', () {
      expect(
        WidgetAppearance.fromPrefs(
          'glass',
          85,
          rawUpcoming: -5,
        ).upcomingMinutes,
        0,
      );
      expect(
        WidgetAppearance.fromPrefs(
          'glass',
          85,
          rawUpcoming: 999,
        ).upcomingMinutes,
        120,
      );
      expect(
        WidgetAppearance.defaults
            .copyWith(upcomingMinutes: 300)
            .upcomingMinutes,
        120,
      );
    });

    test('可选档位覆盖「不提示」到「一小时」', () {
      expect(WidgetAppearance.upcomingOptions.first, 0);
      expect(WidgetAppearance.upcomingOptions, contains(45));
      for (final value in WidgetAppearance.upcomingOptions) {
        expect(value, inInclusiveRange(0, 120));
      }
    });

    test('copyWith 能切默认视图', () {
      expect(
        WidgetAppearance.defaults
            .copyWith(viewMode: WidgetViewMode.todo)
            .viewMode,
        WidgetViewMode.todo,
      );
    });

    test('相等性按 style + alpha + 视图 + 提前量', () {
      expect(
        const WidgetAppearance(viewMode: WidgetViewMode.todo),
        isNot(const WidgetAppearance()),
      );
      expect(
        const WidgetAppearance(upcomingMinutes: 30),
        isNot(const WidgetAppearance()),
      );
    });

    test('相等性按 style + alpha', () {
      expect(
        const WidgetAppearance(style: WidgetStyle.clear, alpha: 60),
        const WidgetAppearance(style: WidgetStyle.clear, alpha: 60),
      );
      expect(
        const WidgetAppearance(style: WidgetStyle.clear, alpha: 60),
        isNot(const WidgetAppearance(style: WidgetStyle.clear, alpha: 61)),
      );
    });
  });

  group('主题', () {
    test('默认跟随系统', () {
      expect(WidgetAppearance.defaults.theme, WidgetTheme.system);
    });

    test('fromPrefs 能还原三种主题', () {
      expect(
        WidgetAppearance.fromPrefs('glass', 85, rawTheme: 'dark').theme,
        WidgetTheme.dark,
      );
      expect(
        WidgetAppearance.fromPrefs('glass', 85, rawTheme: 'light').theme,
        WidgetTheme.light,
      );
      expect(
        WidgetAppearance.fromPrefs('glass', 85, rawTheme: 'system').theme,
        WidgetTheme.system,
      );
    });

    test('脏主题值退回跟随系统', () {
      expect(
        WidgetAppearance.fromPrefs('glass', 85, rawTheme: 'sepia').theme,
        WidgetTheme.system,
      );
      expect(
        WidgetAppearance.fromPrefs('glass', 85, rawTheme: null).theme,
        WidgetTheme.system,
      );
    });

    test('copyWith 能切换主题', () {
      expect(
        WidgetAppearance.defaults.copyWith(theme: WidgetTheme.dark).theme,
        WidgetTheme.dark,
      );
    });

    test('相等性包含主题', () {
      expect(
        const WidgetAppearance(theme: WidgetTheme.dark),
        isNot(const WidgetAppearance()),
      );
    });
  });
}
