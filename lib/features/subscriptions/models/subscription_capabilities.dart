// Shared capability enums used by both entitlement gates and UI.
//
// This avoids circular dependencies between gate services and UI prompt factories.

enum ConsumerCapability {
  downloads,
  skips,
  contentAccess,
  exclusiveContent,
  priorityLiveAccess,
  standardGifts,
  vipGifts,
  songRequests,
  highlightedComments,
}

enum CreatorCapability {
  uploadTrack,
  uploadVideo,
  goLive,
  battle,
  monetization,
  withdraw,
}
