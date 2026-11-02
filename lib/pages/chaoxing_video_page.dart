import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../app_theme.dart';

/// 学习通视频内置播放页。
class ChaoxingVideoPage extends StatefulWidget {
  const ChaoxingVideoPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<ChaoxingVideoPage> createState() => _ChaoxingVideoPageState();
}

class _ChaoxingVideoPageState extends State<ChaoxingVideoPage> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      // 学习通 CDN（*.cldisk.com）会校验请求头：裸请求返回 403，
      // 带上 Referer/UA 才返回 206 video/mp4。video_player 默认什么都不带。
      httpHeaders: const <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://mooc1.chaoxing.com/',
      },
    );
    try {
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        // 初始化期间页面已经关了：dispose() 拿到的是 null，这里必须自己释放，
        // 否则视频解码器会一直挂着。
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      // 403 / 编码不支持都会走到这里，打出原因才好排查
      debugPrint('[video] 初始化失败: $e');
      await controller.dispose();
      if (mounted) setState(() => _error = '视频加载失败');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      try {
                        await launchUrl(
                          Uri.parse(widget.url),
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {
                        // 忽略
                      }
                    },
                    child: const Text('用其他应用打开'),
                  ),
                ],
              ),
            )
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio == 0
                      ? 16 / 9
                      : controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      iconSize: 34,
                      onPressed: () {
                        if (controller.value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                        setState(() {});
                      },
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_circle
                            : Icons.play_circle,
                        color: AppColors.usstRed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
