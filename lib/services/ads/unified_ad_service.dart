import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../app/navigation/app_navigator.dart';
import '../../features/subscriptions/subscriptions_controller.dart';
import 'admob_ads_service.dart';
import 'ads_api.dart';
import 'ads_models.dart';

class UnifiedAdService {
  UnifiedAdService._();

  static final UnifiedAdService instance = UnifiedAdService._();

  bool _showingInterstitial = false;
  bool _showingRewarded = false;

  bool get _supportsAdsPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _forcedAdsEnabled =>
      SubscriptionsController.instance.entitlements.effectiveAdsEnabled;

  Future<void> showPlaybackInterstitial() async {
    if (!_supportsAdsPlatform) return;
    if (_showingInterstitial) return;

    if (!_forcedAdsEnabled) return;

    _showingInterstitial = true;
    try {
      final context = AppNavigator.key.currentContext;
      if (context == null) {
        await AdmobAdsService.instance.showInterstitial();
        return;
      }

      final directOk = await _showDirectInterstitial(context);
      if (directOk) return;

      await AdmobAdsService.instance.showInterstitial();
    } finally {
      _showingInterstitial = false;
    }
  }

  Future<double> showRewardedForCoins(BuildContext context) async {
    if (!_supportsAdsPlatform) return 0;
    if (_showingRewarded) return 0;

    _showingRewarded = true;
    try {
      // Prefer a direct rewarded video creative. If none, fall back to AdMob.
      final api = const AdsApi();
      AdsCreative? creative;
      try {
        creative = await api.fetchNext(placement: AdPlacement.rewarded);
      } catch (_) {
        creative = null;
      }

      if (!context.mounted) return 0;

      if (creative != null && (creative.videoUrl ?? '').trim().isNotEmpty) {
        final completed = await _showDirectVideo(context, creative);
        if (!completed) return 0;

        // Reward (server-side) after a completion.
        try {
          return await api.rewardCoins(adId: creative.id, source: 'direct');
        } catch (_) {
          return 0;
        }
      }

      // AdMob rewarded fallback.
      var awarded = 0.0;
      final ok = await AdmobAdsService.instance.showRewarded(
        onUserEarnedReward: () async {
          try {
            awarded = await api.rewardCoins(source: 'admob');
          } catch (_) {
            awarded = 0;
          }
        },
      );

      return ok ? awarded : 0;
    } finally {
      _showingRewarded = false;
    }
  }

  Future<bool> _showDirectInterstitial(BuildContext context) async {
    final api = const AdsApi();

    AdsCreative? creative;
    try {
      creative = await api.fetchNext(placement: AdPlacement.interstitial);
    } catch (_) {
      creative = null;
    }

    if (!context.mounted) return false;

    if (creative == null || !creative.hasPlayableMedia) return false;

    // Track impression best-effort.
    unawaited(api.track(adId: creative.id, event: AdTrackEvent.impression));

    if ((creative.videoUrl ?? '').trim().isNotEmpty) {
      final completed = await _showDirectVideo(context, creative);
      if (completed) {
        unawaited(api.track(adId: creative.id, event: AdTrackEvent.completion));
      }
      return true;
    }

    if ((creative.audioUrl ?? '').trim().isNotEmpty) {
      final completed = await _showDirectAudio(context, creative);
      if (completed) {
        unawaited(api.track(adId: creative.id, event: AdTrackEvent.completion));
      }
      return true;
    }

    return false;
  }

  Future<bool> _showDirectAudio(BuildContext context, AdsCreative creative) async {
    final audioUrl = (creative.audioUrl ?? '').trim();
    if (audioUrl.isEmpty) return false;

    final player = AudioPlayer();
    bool completed = false;

    Future<void> safeDispose() async {
      try {
        await player.dispose();
      } catch (_) {
        // ignore
      }
    }

    try {
      await player.setUrl(audioUrl);
      unawaited(player.play());

      if (!context.mounted) return false;

      final dialogClosed = Completer<void>();
      var dialogOpen = true;

      unawaited(
        showDialog<void>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: creative.isSkippable,
          builder: (dialogContext) {
            return _DirectAudioAdDialog(
              creative: creative,
              player: player,
              onClick: creative.clickUrl == null
                  ? null
                  : () async {
                      final uri = Uri.tryParse(creative.clickUrl!);
                      if (uri == null) return;
                      unawaited(const AdsApi().track(adId: creative.id, event: AdTrackEvent.click));
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
              onSkip: creative.isSkippable
                  ? () {
                      if (Navigator.of(dialogContext, rootNavigator: true).canPop()) {
                        Navigator.of(dialogContext, rootNavigator: true).pop();
                      }
                    }
                  : null,
            );
          },
        ).whenComplete(() {
          dialogOpen = false;
          if (!dialogClosed.isCompleted) dialogClosed.complete();
        }),
      );

      // Complete when either the audio finishes or the dialog closes.
      final finished = player.processingStateStream.firstWhere(
        (s) => s == ProcessingState.completed,
      );

      await Future.any([
        finished,
        dialogClosed.future,
      ]).timeout(
        Duration(seconds: creative.durationSeconds > 0 ? creative.durationSeconds + 6 : 45),
        onTimeout: () {},
      );

      completed = player.processingState == ProcessingState.completed;

      // Ensure dialog is closed.
      if (dialogOpen && context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // ignore
        }
      }

      return completed;
    } catch (_) {
      return false;
    } finally {
      await safeDispose();
    }
  }

  Future<bool> _showDirectVideo(BuildContext context, AdsCreative creative) async {
    final videoUrl = (creative.videoUrl ?? '').trim();
    if (videoUrl.isEmpty) return false;

    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    try {
      await controller.initialize();
      await controller.play();

      if (!context.mounted) return false;

      final completed = await showDialog<bool>(
            context: context,
            barrierDismissible: creative.isSkippable,
            builder: (dialogContext) {
              return _DirectVideoAdDialog(
                creative: creative,
                controller: controller,
                onClick: creative.clickUrl == null
                    ? null
                    : () async {
                        final uri = Uri.tryParse(creative.clickUrl!);
                        if (uri == null) return;
                        unawaited(const AdsApi().track(adId: creative.id, event: AdTrackEvent.click));
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                onSkip: creative.isSkippable
                    ? () {
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.of(dialogContext).pop(false);
                        }
                      }
                    : null,
              );
            },
          ) ??
          false;

      if (completed) {
        return true;
      }

      // If dialog dismissed and video already ended, treat as completion.
      return controller.value.position >= controller.value.duration;
    } catch (_) {
      return false;
    } finally {
      try {
        await controller.pause();
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }
}

class _DirectAudioAdDialog extends StatefulWidget {
  const _DirectAudioAdDialog({
    required this.creative,
    required this.player,
    this.onClick,
    this.onSkip,
  });

  final AdsCreative creative;
  final AudioPlayer player;
  final VoidCallback? onClick;
  final VoidCallback? onSkip;

  @override
  State<_DirectAudioAdDialog> createState() => _DirectAudioAdDialogState();
}

class _DirectAudioAdDialogState extends State<_DirectAudioAdDialog> {
  @override
  Widget build(BuildContext context) {
    final title = widget.creative.title.trim().isEmpty ? 'Sponsored' : widget.creative.title.trim();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sponsored', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(widget.creative.advertiser, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            StreamBuilder<Duration>(
              stream: widget.player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = widget.player.duration ?? Duration.zero;
                final total = dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds;
                final value = (pos.inMilliseconds / total).clamp(0.0, 1.0);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: value),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (widget.onClick != null)
                          TextButton.icon(
                            onPressed: widget.onClick,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Learn more'),
                          ),
                        const Spacer(),
                        if (widget.onSkip != null)
                          TextButton(
                            onPressed: widget.onSkip,
                            child: const Text('Skip'),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectVideoAdDialog extends StatefulWidget {
  const _DirectVideoAdDialog({
    required this.creative,
    required this.controller,
    this.onClick,
    this.onSkip,
  });

  final AdsCreative creative;
  final VideoPlayerController controller;
  final VoidCallback? onClick;
  final VoidCallback? onSkip;

  @override
  State<_DirectVideoAdDialog> createState() => _DirectVideoAdDialogState();
}

class _DirectVideoAdDialogState extends State<_DirectVideoAdDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVideoTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideoTick);
    super.dispose();
  }

  void _onVideoTick() {
    if (!mounted) return;
    final v = widget.controller.value;
    if (!v.isInitialized) return;
    if (v.position >= v.duration && v.duration.inMilliseconds > 0) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.creative.title.trim().isEmpty ? 'Sponsored' : widget.creative.title.trim();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (widget.onSkip != null)
                  IconButton(
                    onPressed: widget.onSkip,
                    icon: const Icon(Icons.close),
                    tooltip: 'Skip',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: widget.controller.value.isInitialized
                  ? widget.controller.value.aspectRatio
                  : (16 / 9),
              child: widget.controller.value.isInitialized
                  ? VideoPlayer(widget.controller)
                  : const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (widget.onClick != null)
                  FilledButton.icon(
                    onPressed: widget.onClick,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Learn more'),
                  ),
                const Spacer(),
                Text(widget.creative.advertiser, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
