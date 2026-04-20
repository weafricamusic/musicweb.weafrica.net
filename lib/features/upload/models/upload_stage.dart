// WEAFRICA Music — Upload Stage Enum

enum UploadStage {
  preparing('Preparing…', 0.0),
  creatingDraft('Creating draft…', 0.1),
  compressing('Optimizing…', 0.2),
  uploading('Uploading to WEAFRICA…', 0.4),
  finalizing('Publishing…', 0.95),
  completed('Complete!', 1.0),
  failed('Failed', 0.0),
  cancelled('Cancelled', 0.0);

  const UploadStage(this.defaultMessage, this.defaultProgress);

  final String defaultMessage;
  final double defaultProgress;

  bool get isActive => this != completed && this != failed && this != cancelled;

  bool get isTerminal => this == completed || this == failed || this == cancelled;
}

