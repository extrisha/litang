import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/place_search.dart';

List<String> names(String query) =>
    searchCampusPlaces(query).map((p) => p.name).toList();

void main() {
  group('简称与别名', () {
    test('教超 → 上海教育超市（字不连续也能命中）', () {
      final r = names('教超');
      expect(r, contains('上海教育超市'));
    });

    test('二公 → 第二学生公寓一/二/三号楼', () {
      final r = names('二公');
      expect(r, contains('第二学生公寓一号楼'));
      expect(r, contains('第二学生公寓二号楼'));
      expect(r, contains('第二学生公寓三号楼'));
    });

    test('二公三 → 只剩三号楼', () {
      final r = names('二公三');
      expect(r.first, '第二学生公寓三号楼');
      expect(r, isNot(contains('第二学生公寓一号楼')));
    });

    test('阿拉伯数字和中文数字等价（2公三）', () {
      expect(names('2公三').first, '第二学生公寓三号楼');
      expect(names('二公3').first, '第二学生公寓三号楼');
    });

    test('一教 / 二食 这类编号简称', () {
      expect(names('一教'), contains('第一教学楼'));
      expect(names('二食'), contains('第二食堂'));
      // 地图上没有「第三食堂」，只有一/二/五食堂
      expect(names('五食'), contains('第五食堂'));
    });

    test('图档 → 图书馆·档案馆', () {
      expect(names('图档'), contains('图书馆·档案馆'));
    });
  });

  group('排序与边界', () {
    test('完全一致的排最前', () {
      expect(names('第二食堂').first, '第二食堂');
    });

    test('空查询和不存在的查询返回空', () {
      expect(searchCampusPlaces(''), isEmpty);
      expect(searchCampusPlaces('   '), isEmpty);
      expect(searchCampusPlaces('这是一个不存在的地方'), isEmpty);
    });

    test('限制返回条数', () {
      expect(searchCampusPlaces('学生公寓', limit: 5).length, lessThanOrEqualTo(5));
    });

    test('同名地点不会重复出现', () {
      final r = searchCampusPlaces('机械工程学院实验中心');
      final dup = r.map((p) => p.name).toList();
      expect(dup.length, dup.toSet().length);
    });
  });

  group('归一化', () {
    test('中文数字转阿拉伯、去括号补充说明', () {
      expect(normalizePlaceText('第十一学生宿舍'), '第11学生宿舍');
      expect(normalizePlaceText('第四教学楼（逸兴楼）'), '第4教学楼');
      expect(normalizePlaceText(' 图 书 馆 '), '图书馆');
    });

    test('展开查询会带上别名和规则', () {
      expect(expandPlaceQuery('二公'), isNotEmpty);
      expect(expandPlaceQuery(''), isEmpty);
    });
  });
}
