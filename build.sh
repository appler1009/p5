# Build script
swift build 2>&1 | grep -E "(Sources/MediaBrowser|Tests)" || true
echo "Built successfully. Run with:"
echo "./.build/arm64-apple-macosx/debug/MediaBrowser"