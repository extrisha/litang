# Flutter engine
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Plugins that use reflection
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.baseflow.geolocator.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }

# ML Kit / barcode scanner (native + reflection)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.odml.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.libraries.** { *; }

# Flutter plugins method channels
-keep class io.flutter.plugins.** { *; }
-keep class dev.steenbakker.** { *; }
-keep class com.baseflow.** { *; }
-keep class com.it_nomads.** { *; }

# App Widgets (Android 桌面小组件与适配器，防止 R8 混淆或剔除反射构造)
-keep class com.example.project_usst.TodayScheduleWidgetProvider { *; }
-keep class com.example.project_usst.TodayScheduleWidgetService { *; }
-keep class com.example.project_usst.TodayScheduleRemoteViewsFactory { *; }
-keep class es.antonborri.home_widget.** { *; }
