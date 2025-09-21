
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// --- Main entry point ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(
    debug: kDebugMode,
    ignoreSsl: true,
  );
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
    const Color primarySeedColor = Color(0xFFC70039);

    final TextTheme appTextTheme = TextTheme(
      displayLarge: GoogleFonts.oswald(fontSize: 57, fontWeight: FontWeight.bold),
      titleLarge: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500),
      bodyMedium: GoogleFonts.openSans(fontSize: 14),
      labelLarge: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.bold),
    );

    final elevatedButtonTheme = ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ));

    final lightTheme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primarySeedColor,
          brightness: Brightness.light,
        ),
        textTheme: appTextTheme,
        elevatedButtonTheme: elevatedButtonTheme);

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primarySeedColor,
        brightness: Brightness.dark,
      ),
      textTheme: appTextTheme,
      elevatedButtonTheme: elevatedButtonTheme,
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

// --- State Management (Provider) ---
class DownloadProvider with ChangeNotifier {
  String _status = 'မင်္ဂလာပါ! ဒေါင်းလုဒ်လုပ်ရန် ဗီဒီယိုကို ရှာဖွေပါ။';
  double _progress = 0.0;
  bool _isDownloading = false;
  String _currentUrl = "https://www.google.com";
  String? _taskId;

  String get status => _status;
  double get progress => _progress;
  bool get isDownloading => _isDownloading;
  String get currentUrl => _currentUrl;

  void updateStatus(String newStatus, {bool isError = false}) {
    _status = newStatus;
    if (isError) _isDownloading = false;
    notifyListeners();
  }

  void startDownload(String url, String taskId) {
    _currentUrl = url;
    _isDownloading = true;
    _progress = 0.0;
    _status = 'ဒေါင်းလုဒ် စတင်နေပါသည်...';
    _taskId = taskId;
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
    _taskId = null;
    notifyListeners();
  }

  void errorDownload(String message) {
    _isDownloading = false;
    _status = message;
    _taskId = null;
    notifyListeners();
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
  final List<Widget> _pages = [
    const BrowserPage(),
    DownloadsPage(key: GlobalKey<_DownloadsPageState>())
  ];
  final ReceivePort _port = ReceivePort();

  @override
  void initState() {
    super.initState();
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) {
      String id = data[0];
      int status = data[1];
      int progress = data[2];

      final provider = Provider.of<DownloadProvider>(context, listen: false);

      if (status == DownloadTaskStatus.running.index) {
        provider.updateProgress(progress / 100, 'ဒေါင်းလုဒ်လုပ်နေသည်: $progress%');
      } else if (status == DownloadTaskStatus.complete.index) {
        provider.completeDownload('ဒေါင်းလုဒ် ပြီးဆုံးပါပြီ!');
        _loadVideoFiles();
      } else if (status == DownloadTaskStatus.failed.index) {
        provider.errorDownload('ဒေါင်းလုဒ် မအောင်မြင်ပါ!');
      }
    });

    FlutterDownloader.registerCallback(downloadCallback);
  }

  void _loadVideoFiles() {
    final downloadsPage = _pages[1];
    if (downloadsPage is DownloadsPage) {
      (downloadsPage.key as GlobalKey<_DownloadsPageState>)
          .currentState
          ?._loadVideoFiles();
    }
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send =
        IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.download), label: 'Downloads'),
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

class _BrowserPageState extends State<BrowserPage>
    with AutomaticKeepAliveClientMixin {
  final _urlController = TextEditingController();
  InAppWebViewController? _webViewController;
  List<String> _videoSrcs = [];
  final YoutubeExplode _ytExplode = YoutubeExplode();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<DownloadProvider>(context, listen: false);
    _urlController.text = provider.currentUrl;
  }

  Future<void> _handleUrlSubmission(String url) async {
    if (url.toLowerCase().contains('youtube.com') || url.toLowerCase().contains('youtu.be')) {
      _downloadFromYouTube(url);
    } else {
       final searchUrl = "https://www.google.com/search?q=$url";
      _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(url.startsWith('http') ? url : searchUrl)));
    }
  }

  Future<void> _downloadFromYouTube(String url) async {
    final provider = Provider.of<DownloadProvider>(context, listen: false);
    provider.updateStatus("YouTube ဗီဒီယိုကို ရယူနေသည်...");
    try {
      var video = await _ytExplode.videos.get(url);
      var manifest = await _ytExplode.videos.streamsClient.getManifest(video.id);
      var streamInfo = manifest.muxed.sortByBitrate().first;

      if (streamInfo != null) {
        final path = await _localPath;
        final fileName = '${video.title}.${streamInfo.container.name}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final taskId = await FlutterDownloader.enqueue(
          url: streamInfo.url.toString(),
          savedDir: path,
          fileName: fileName,
          showNotification: true,
          openFileFromNotification: true,
        );
        if (taskId != null) {
          provider.startDownload(url, taskId);
        } else {
          provider.errorDownload("YouTube ဒေါင်းလုဒ် စတင်နိုင်ခြင်း မရှိပါ။");
        }
      }
    } catch (e) {
      provider.errorDownload("YouTube ဗီဒီယို အချက်အလက် ရယူနိုင်ခြင်း မရှိပါ။");
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('YouTube ဗီဒီယို ရယူရာတွင် အမှားအယွင်း ဖြစ်ပွားပါသည်: $e')),
        );
      }
    }
  }


  Future<void> _checkForVideos() async {
    if (_webViewController == null) return;
    final String jsScript = """
      (function() {
        let sources = [];
        let videos = document.getElementsByTagName('video');
        for (let i = 0; i < videos.length; i++) {
          if (videos[i].src) {
            sources.push(videos[i].src);
          }
          let sourceTags = videos[i].getElementsByTagName('source');
          for (let j = 0; j < sourceTags.length; j++) {
            if (sourceTags[j].src) {
              sources.push(sourceTags[j].src);
            }
          }
        }
        return sources;
      })();
    """;
    try {
      final result = await _webViewController!.evaluateJavascript(source: jsScript);
      if (result != null && result is List) {
        setState(() {
          _videoSrcs = result.map((e) => e.toString()).toSet().toList(); // Remove duplicates
        });
      } else {
        setState(() {
          _videoSrcs = [];
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error checking for videos: $e");
      }
      setState(() {
        _videoSrcs = [];
      });
    }
  }

  Future<void> _handleDownloadAction() async {
    if (_videoSrcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ဤစာမျက်နှာတွင် ဒေါင်းလုဒ်လုပ်နိုင်သော ဗီဒီယိုများ မတွေ့ပါ။')),
      );
      return;
    }

    if (_videoSrcs.length == 1) {
      _startDownload(_videoSrcs.first);
    } else {
      _showVideoSelectionDialog();
    }
  }

  Future<void> _showVideoSelectionDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('ဒေါင်းလုဒ်လုပ်ရန် ဗီဒီယို ရွေးချယ်ပါ', style: Theme.of(context).dialogTheme.titleTextStyle),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _videoSrcs.length,
              itemBuilder: (context, index) {
                final videoSrc = _videoSrcs[index];
                return ListTile(
                  title: Text(
                    'Video ${index + 1}',
                    style: Theme.of(context).dialogTheme.contentTextStyle,
                  ),
                   subtitle: Text(
                    videoSrc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                     style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.download, color: Theme.of(context).colorScheme.primary),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _startDownload(videoSrc);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ပိတ်မည်'),
            )
          ],
        );
      },
    );
  }


  Future<void> _startDownload(String url) async {
    final provider = Provider.of<DownloadProvider>(context, listen: false);
    final path = await _localPath;
    // Try to get a reasonable filename
    final fileName = url.split('/').last.split('?').first.replaceAll(RegExp(r'[^a-zA-Z0-9\.]'), '_');


    final taskId = await FlutterDownloader.enqueue(
      url: url,
      savedDir: path,
      fileName: fileName.isNotEmpty ? fileName : "video.mp4",
      showNotification: true,
      openFileFromNotification: true,
    );
    if (taskId != null) {
      provider.startDownload(url, taskId);
    } else {
      provider.errorDownload("ဒေါင်းလုဒ် စတင်နိုင်ခြင်း မရှိပါ။");
       if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ဒေါင်းလုဒ် စတင်နိုင်ခြင်း မရှိပါ။')),
        );
      }
    }
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = Provider.of<DownloadProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _urlController,
          decoration:
              const InputDecoration(hintText: 'URL ထည့်ပါ သို့မဟုတ် ရှာဖွေပါ', border: InputBorder.none),
          onSubmitted: _handleUrlSubmission,
        ),
        actions: [
          if (_videoSrcs.isNotEmpty && !provider.isDownloading)
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined),
              color: Theme.of(context).colorScheme.primary,
              tooltip: 'ဗီဒီယို ဒေါင်းလုဒ်လုပ်ပါ',
              onPressed: _handleDownloadAction,
            ),
          if (provider.isDownloading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.0))),
            ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(provider.currentUrl)),
        initialSettings: InAppWebViewSettings(
          mediaPlaybackRequiresUserGesture: false,
          javaScriptEnabled: true,
        ),
        onWebViewCreated: (controller) => _webViewController = controller,
        onLoadStop: (controller, url) {
          if (url != null) {
            _urlController.text = url.toString();
            _checkForVideos();
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _ytExplode.close();
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
      final files = directory
          .listSync()
          .where((item) =>
              item.path.endsWith('.mp4') ||
              item.path.endsWith('.mkv') ||
              item.path.endsWith('.mov'))
          .toList();
      if (mounted) {
        setState(() {
          _videoFiles = files;
        });
      }
    } catch (e) {
      if (kDebugMode) print('ဗီဒီယိုများဖွင့်ရာတွင် အမှားအယွင်းဖြစ်ပွားသည်: $e');
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
        title: Text('ဒေါင်းလုဒ်များ', style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadVideoFiles,
              tooltip: 'စာရင်း ပြန်စစ်မည်')
        ],
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
                    Text(provider.status,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: provider.isDownloading ? provider.progress : null,
                      minHeight: 12,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary),
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
                  ? Center(
                      child: Text('ဒေါင်းလုဒ်လုပ်ထားသော ဗီဒီယိုများ မရှိသေးပါ။',
                          style: Theme.of(context).textTheme.bodyMedium))
                  : ListView.builder(
                      itemCount: _videoFiles.length,
                      itemBuilder: (context, index) {
                        final file = _videoFiles[index];
                        final fileName = file.path.split('/').last;
                        return ListTile(
                          leading: Icon(Icons.videocam,
                              color: Theme.of(context).colorScheme.primary,
                              size: 40),
                          title: Text(fileName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium),
                          subtitle: Text(
                              '${((file as File).lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
                              style: Theme.of(context).textTheme.bodySmall),
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
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    },
                    child: VideoPlayer(_controller)),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
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
