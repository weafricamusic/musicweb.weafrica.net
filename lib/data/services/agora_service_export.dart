// This file conditionally exports the correct implementation based on platform
export 'agora_service.dart' 
  if (dart.library.html) 'agora_service_web.dart';
