# zig-lib-audiocodec

Audio-only codec library for Zig 0.16.0: one static build, no GPL/LGPL code, a single Zig API for
decode and encode (API in progress).

## Codecs

| codec  | backend                                  | license of backend |
|--------|------------------------------------------|--------------------|
| opus   | libopus, libopusfile, libopusenc         | BSD                |
| vorbis | libvorbis + libogg                       | BSD                |
| flac   | libFLAC                                  | BSD                |
| mp3    | dr_mp3 (decode only)                     | PD / MIT-0         |
| aac    | fdk-aac                                  | Fraunhofer         |
| alac   | Zig port over the Apple ALAC C DSP core  | Apache 2.0         |
| m4a    | minimp4                                  | CC0                |
| wav/aiff | own Zig code (planned)                 | -                  |

So far the C libraries are built and bound (`audiocodec.c`), and ALAC encode/decode is ported
(`audiocodec.alac`). The unified Decoder/Encoder API is not there yet.

## Use

```sh
zig fetch --save git+https://github.com/nat3Github/zig-lib-audiocodec#main
```

```zig
const audiocodec = b.dependency("audiocodec", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("audiocodec", audiocodec.module("audiocodec"));
```

All C libraries are fetched from nat3Github forks (branch `zig`) pinned in `build.zig.zon`, and built
from source by `zig build`. There are no system dependencies.

## License

BSD-3-Clause (this repo). Vendored libraries keep their own licenses (see table).
