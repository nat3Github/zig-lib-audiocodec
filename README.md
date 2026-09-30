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

### fdk-aac (Fraunhofer)

AAC is built from a modified fdk-aac, the "Third-Party Modified Version of the Fraunhofer FDK AAC
Codec Library for Android", under Fraunhofer's software license (the fork's `NOTICE`). In short: the
complete license text must ship with binaries, the fdk-aac source including modifications must be
available free of charge (it is: nat3Github/cpp-lib-fdk-aac, branch `zig`), no copyright license fees,
and Fraunhofer's name may not be used to promote derived products. The license grants **no patent
rights**: using AAC may require patent licenses (e.g. through Via Licensing Alliance), which is up to
you.
