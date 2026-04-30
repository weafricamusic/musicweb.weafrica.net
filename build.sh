#!/bin/bash

set -e

# Download and extract Flutter
curl -s https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.7-stable.tar.xz -o flutter.tar.xz
tar xf flutter.tar.xz

# Fix git ownership issue
git config --global --add safe.directory /vercel/path0/flutter

# Add Flutter to PATH
export PATH="$PATH:`pwd`/flutter/bin"

# Disable analytics
flutter config --no-analytics

# Pre-cache Flutter and get dependencies
flutter precache
flutter pub get

# Build Flutter web app
flutter build web --release