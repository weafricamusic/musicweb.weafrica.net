import 'download_stats_impl_stub.dart'
    if (dart.library.io) 'download_stats_impl_io.dart';

import 'download_stats_model.dart';

export 'download_stats_model.dart';

Future<DownloadStats> getDownloadStats() => getDownloadStatsImpl();
