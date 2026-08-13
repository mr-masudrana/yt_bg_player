import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

late MyAudioHandler _audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.yt.bg.player.audio',
      androidNotificationChannelName: 'YouTube Background Audio',
      androidNotificationOngoing: true,
    ),
  );
  runApp(const YTPlayerApp());
}

class MyAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  MyAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
  }

  Future<void> playYoutubeAudio(Video video) async {
    var yt = YoutubeExplode();
    try {
      var manifest = await yt.videos.streamsClient.getManifest(video.id);
      var streamInfo = manifest.audioOnly.withHighestBitrate();

      mediaItem.add(
        MediaItem(
          id: video.id.value,
          album: video.author,
          title: video.title,
          artUri: Uri.parse(video.thumbnails.highResUrl),
        ),
      );

      await _player.setUrl(streamInfo.url.toString());
      play();
    } finally {
      yt.close();
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(PlaybackState(
      controls: [
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }
}

class YTPlayerApp extends StatelessWidget {
  const YTPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.redAccent,
      ),
      home: const SearchScreen(),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Video> _searchResults = [];
  bool _isLoading = false;

  void _performSearch() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isLoading = true);
    var yt = YoutubeExplode();
    try {
      var searchList = await yt.search.search(query);
      setState(() {
        _searchResults = searchList.toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('খুঁজে পাওয়া যায়নি: $e')),
      );
    } finally {
      yt.close();
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube Music Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'গান বা শিল্পীর নাম লিখুন...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _performSearch,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _performSearch(),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                var video = _searchResults[index];
                return ListTile(
                  leading: Image.network(
                    video.thumbnails.lowResUrl,
                    width: 60,
                    fit: BoxFit.cover,
                  ),
                  title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(video.author),
                  onTap: () {
                    _audioHandler.playYoutubeAudio(video);
                  },
                );
              },
            ),
          ),
          
          // বটম প্লেয়ার বার
          StreamBuilder<MediaItem?>(
            stream: _audioHandler.mediaItem,
            builder: (context, snapshot) {
              var item = snapshot.data;
              if (item == null) return const SizedBox();

              return Container(
                color: Colors.grey[900],
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Image.network(item.artUri.toString(), width: 50, height: 50, fit: BoxFit.cover),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(item.album ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    StreamBuilder<PlaybackState>(
                      stream: _audioHandler.playbackState,
                      builder: (context, snapshot) {
                        var playing = snapshot.data?.playing ?? false;
                        return IconButton(
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: () {
                            if (playing) {
                              _audioHandler.pause();
                            } else {
                              _audioHandler.play();
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
