import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/widgets/lazy_indexed_stack.dart';

class _Page extends StatefulWidget {
  const _Page(this.id, this.initialized, this.disposed);
  final int id;
  final List<int> initialized;
  final List<int> disposed;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    widget.initialized.add(widget.id);
  }

  @override
  void dispose() {
    widget.disposed.add(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('${widget.id}:$count'),
  );
}

void main() {
  testWidgets('只初始化选中页，来回切换保留状态，离开后正常销毁', (tester) async {
    final initialized = <int>[];
    final disposed = <int>[];
    final pages = List.generate(5, (i) => _Page(i, initialized, disposed));
    Widget view(int index) => MaterialApp(
      home: Scaffold(
        body: LazyIndexedStack(index: index, children: pages),
      ),
    );
    await tester.pumpWidget(view(2));
    expect(initialized, [2]);
    await tester.tap(find.text('2:0'));
    await tester.pump();
    await tester.pumpWidget(view(0));
    expect(initialized, [2, 0]);
    expect(disposed, isEmpty);
    await tester.pumpWidget(view(2));
    expect(find.text('2:1'), findsOneWidget);
    expect(initialized, [2, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed.toSet(), {0, 2});
    expect(tester.takeException(), isNull);
  });
}
