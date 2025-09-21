
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// --- Main entry point ---
Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  await Permission.storage.request();
  runApp(const MyApp());
}

// --- The root of the application ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primarySeedColor = Colors.red;

    final TextTheme appTextTheme = TextTheme(
      displayLarge: GoogleFonts.oswald(fontSize: 57, fontWeight: FontWeight.bold),
      titleLarge: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500),
      bodyMedium: GoogleFonts.openSans(fontSize: 14),
      labelLarge: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.bold),
    );

    final ThemeData lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primarySeedColor,
        brightness: Brightness.light,
      ),
      textTheme: appTextTheme,
    );

    final ThemeData darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primarySeedColor,
        brightness: Brightness.dark,
      ),
      textTheme: appTextTheme,
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: GoogleFonts.oswald(fontSize: 22, fontWeight: FontWeight.bold),
        contentTextStyle: GoogleFonts.roboto(fontSize: 16, color: Colors.white70),
      ),
    );

    return ChangeNotifierProvider(
      create: (context) => DownloadProvider(),
      child: MaterialApp(
        title: 'NMS Downloader',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark, // Enforce dark mode
        home: const MainPage(),
      ),
    );
  }
}

// --- Data Models ---
class VideoInfo {
  final String id;
  final String title;
  VideoInfo(this.id, this.title);
}

// --- State Management (Provider) ---
class DownloadProvider with ChangeNotifier {
  String _status = 'Welcome! Browse for a video to get started.';
  double _progress = 0.0;
  bool _isDownloading = false;
  String _currentUrl = "https://www.google.com";

  String get status => _status;
  double get progress => _progress;
  bool get isDownloading => _isDownloading;
  String get currentUrl => _currentUrl;

  void updateStatus(String newStatus, {bool isError = false}) {
    _status = newStatus;
    if (isError) _isDownloading = false;
    notifyListeners();
  }

  void startDownload(String url) {
    _currentUrl = url;
    _isDownloading = true;
    _progress = 0.0;
    _status = 'Starting download...';
    notifyListeners();
  }

  void updateProgress(double newProgress, String message) {
    _progress = newProgress;
    _status = message;
    notifyListeners();
  }

  void completeDownload(String finalMessage) {
    _isDownloading = false;
    _progress = 1.0;
    _status = finalMessage;
    notifyListeners();
  }
}

// --- Downloader Service ---
enum VideoPlatform { youtube, unsupported }

class DownloaderService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Function(double, String)? onProgress;

  DownloaderService({this.onProgress});

  VideoPlatform _getPlatform(String url) {
    if (url.contains("youtube.com") || url.contains("youtu.be")) {
      return VideoPlatform.youtube;
    }
    return VideoPlatform.unsupported;
  }

  Future<List<VideoInfo>> getVideosFromUrl(String url) async {
    final platform = _getPlatform(url);
    if (platform != VideoPlatform.youtube) {
      return [];
    }

    // Try to parse as a playlist
    try {
      final playlistId = PlaylistId(url);
      final videos = await _yt.playlists.getVideos(playlistId).toList();
      return videos.map((v) => VideoInfo(v.id.value, v.title)).toList();
    } on ArgumentError {
      // Not a valid playlist URL, ignore and try to parse as a video.
    } catch (e) {
      if (kDebugMode) {
        print('Error getting playlist videos from $url: $e');
      }
    }

    // Try to parse as a video
    try {
      final videoId = VideoId(url);
      final video = await _yt.videos.get(videoId);
      return [VideoInfo(video.id.value, video.title)];
    } on ArgumentError {
      if (kDebugMode) {
        print('Could not parse URL as a playlist or video: $url');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting video from $url: $e');
      }
    }

    return [];
  }

  Future<void> downloadVideo(VideoInfo videoInfo) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoInfo.id);
    final streamInfo = manifest.muxed.withHighestBitrate();
    final totalBytes = streamInfo.size.totalBytes;
    var downloadedBytes = 0;

    final downloadsDir = await getApplicationDocumentsDirectory();
    final fileName = '${videoInfo.title.replaceAll(r'[\\/:*?"<>|]', '')}.mp4';
    final filePath = '${downloadsDir.path}/$fileName';
    final file = File(filePath);
    final output = file.openWrite(mode: FileMode.writeOnlyAppend);

    final stream = _yt.videos.streamsClient.get(streamInfo);

    await for (final data in stream) {
      downloadedBytes += data.length;
      output.add(data);
      final progress = downloadedBytes / totalBytes;
      final message =
          'Downloading: ${(downloadedBytes / 1024 / 1024).toStringAsFixed(2)}MB / ${(totalBytes / 1024 / 1024).toStringAsFixed(2)}MB';
      onProgress?.call(progress, message);
    }

    await output.close();
  }

  void dispose() {
    _yt.close();
  }
}

// --- Main Page with Bottom Navigation ---
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [const BrowserPage(), const DownloadsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

// --- Tab 1: Browser Page ---
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with AutomaticKeepAliveClientMixin {
  final _urlController = TextEditingController();
  InAppWebViewController? _webViewController;
  bool _canDownload = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<DownloadProvider>(context, listen: false);
    _urlController.text = provider.currentUrl;
    _checkUrlForDownload(provider.currentUrl);
  }

  void _checkUrlForDownload(String url) {
    if (!mounted) return;
    _urlController.text = url;
    setState(() {
      _canDownload = (url.contains("youtube.com") || url.contains("youtu.be"));
    });
  }

  Future<void> _showVideoSelectionDialog() async {
    if (!_canDownload) return;

    final downloader = DownloaderService();
    final videos = await downloader.getVideosFromUrl(_urlController.text);
    downloader.dispose();

    if (!mounted) return;

    if (videos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No downloadable videos found on this page.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select a Video', style: Theme.of(context).dialogTheme.titleTextStyle),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final video = videos[index];
                return ListTile(
                  title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).dialogTheme.contentTextStyle),
                  trailing: IconButton(
                    icon: Icon(Icons.download, color: Theme.of(context).colorScheme.primary),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _startDownload(video);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
        );
      },
    );
  }

  Future<void> _startDownload(VideoInfo videoInfo) async {
    final provider = Provider.of<DownloadProvider>(context, listen: false);
    provider.startDownload('https://www.youtube.com/watch?v=${videoInfo.id}');

    final downloader = DownloaderService(
      onProgress: (progress, message) {
        provider.updateProgress(progress, message);
      },
    );

    try {
      await downloader.downloadVideo(videoInfo);
      provider.completeDownload('Finished downloading: ${videoInfo.title}');
    } catch (e) {
      provider.updateStatus('Error: ${e.toString()}', isError: true);
    } finally {
      downloader.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = Provider.of<DownloadProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _urlController,
          decoration: const InputDecoration(hintText: 'Enter URL or search', border: InputBorder.none),
          onSubmitted: (url) {
            final searchUrl = "https://www.google.com/search?q=$url";
            _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url.startsWith('http') ? url : searchUrl)));
          },
        ),
        actions: [
          if (_canDownload && !provider.isDownloading)
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined),
              color: Theme.of(context).colorScheme.primary, // Highlight color
              tooltip: 'Download Video',
              onPressed: _showVideoSelectionDialog,
            ),
          if (provider.isDownloading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: Theme.of(context).colorScheme.primary))),
            ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(provider.currentUrl)),
        initialSettings: InAppWebViewSettings(mediaPlaybackRequiresUserGesture: false),
        onWebViewCreated: (controller) => _webViewController = controller,
        onLoadStop: (controller, url) {
          if (url != null) _checkUrlForDownload(url.toString());
        },
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}

// --- Tab 2: Downloads Page ---
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<FileSystemEntity> _videoFiles = [];

  @override
  void initState() {
    super.initState();
    _loadVideoFiles();
    Provider.of<DownloadProvider>(context, listen: false).addListener(() {
      final provider = Provider.of<DownloadProvider>(context, listen: false);
      if (!provider.isDownloading && provider.progress == 1.0) {
        _loadVideoFiles();
      }
    });
  }

  Future<void> _loadVideoFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync().where((item) => item.path.endsWith('.mp4')).toList();
      if (mounted) {
        setState(() {
          _videoFiles = files;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading videos: $e');
    }
  }

  void _playVideo(String filePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(filePath: filePath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Downloads', style: Theme.of(context).textTheme.titleLarge),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadVideoFiles, tooltip: 'Refresh List')],
      ),
      body: Column(
        children: [
          Consumer<DownloadProvider>(
            builder: (context, provider, child) {
              if (!provider.isDownloading && provider.progress == 0.0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(provider.status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: provider.progress,
                      minHeight: 12,
                      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadVideoFiles,
              child: _videoFiles.isEmpty
                  ? Center(child: Text('No downloaded videos yet.', style: Theme.of(context).textTheme.bodyMedium))
                  : ListView.builder(
                      itemCount: _videoFiles.length,
                      itemBuilder: (context, index) {
                        final file = _videoFiles[index];
                        final fileName = file.path.split('/').last;
                        return ListTile(
                          leading: Icon(Icons.videocam, color: Theme.of(context).colorScheme.primary, size: 40),
                          title: Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                          subtitle: Text('${((file as File).lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB', style: Theme.of(context).textTheme.bodySmall),
                          onTap: () => _playVideo(file.path),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Video Player Screen ---
class VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  const VideoPlayerScreen({super.key, required this.filePath});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() {}); // Ensure the first frame is shown
        _controller.play();
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filePath.split('/').last),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _controller.value.isPlaying ? _controller.pause() : _controller.play();
                    });
                  },
                  child: VideoPlayer(_controller)
                ),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
