#!/usr/bin/env bash
# Builds the note-model engine into .build/engine/llama-server.
# It is llama-server from PrismML's llama.cpp, the only runtime that loads
# Bonsai, at the commit soapcap tested. One self-contained file with nothing
# from Homebrew in it, so it can ship inside Soapcap.app.
# Needs cmake and git. Skips the build when the pinned one is already there.
set -eu
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

url="https://github.com/PrismML-Eng/llama.cpp.git"
commit="9a9394a895b96003ca842a6041cb28ac49a108f7"
dir="$here/.build/engine"
src="$dir/llama.cpp"
out="$dir/llama-server"

die() { echo "engine.sh: $*" >&2; exit 1; }
command -v cmake >/dev/null 2>&1 || die "needs cmake (brew install cmake)"

if [ -x "$out" ] && [ "$(cat "$dir/commit" 2>/dev/null)" = "$commit" ]; then
  echo "Engine is up to date ($out)"
  exit 0
fi

mkdir -p "$dir"
if [ "$(git -C "$src" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]; then
  echo "==> Fetching PrismML's llama.cpp (commit ${commit:0:9})"
  rm -rf "$src"
  git init -q "$src"
  git -C "$src" remote add origin "$url"
  git -C "$src" fetch -q --depth 1 origin "$commit"
  git -C "$src" checkout -q --detach FETCH_HEAD
fi

# Static, so there are no libraries to carry along. No OpenSSL: the server
# only ever listens on this Mac. No web page: only the app talks to it. Not
# tuned to this Mac's processor: it has to run on every Apple silicon Mac.
echo "==> Building llama-server (a few minutes; log: $dir/build.log)"
if ! { cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
         -DBUILD_SHARED_LIBS=OFF -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_UI=OFF \
         -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
         -DGGML_NATIVE=OFF -DGGML_METAL_EMBED_LIBRARY=ON \
       && cmake --build "$src/build" --config Release --target llama-server \
            -j "$(/usr/sbin/sysctl -n hw.ncpu)"; } >"$dir/build.log" 2>&1; then
  tail -n 20 "$dir/build.log" >&2
  die "build failed; full log: $dir/build.log"
fi

built="$src/build/bin/llama-server"
"$built" --version >/dev/null 2>&1 || die "the built llama-server doesn't run; see $dir/build.log"
# Anything outside the system would be missing on someone else's Mac.
if otool -L "$built" | tail -n +2 | grep -vE '^[[:space:]]*(/System/Library/|/usr/lib/)' >&2; then
  die "llama-server depends on the libraries above, which other Macs won't have"
fi
cp "$built" "$out"
cp "$src/LICENSE" "$dir/LICENSE"
echo "$commit" > "$dir/commit"
echo "Built $out ($(du -h "$out" | cut -f1 | tr -d ' '))"
