// macOS-only: assert app-group container membership before any store I/O.
//
// Why this exists (fix/macos-host-container-registration): the signed host
// carries the `com.apple.security.application-groups` entitlement for
// `A8QUU5F9G3.dev.camillobucciarelli.kdbxKeyVault.browser`, but Sequoia's
// App Data protection only treats the process as a group *member* — and
// therefore skips the "would like to access data from other apps" prompt —
// after the process has asserted membership with containermanagerd. A raw
// `open()` on the container path does not do that: it is classified as
// generic App Data access and blocks on a per-spawn TCC prompt (measured:
// real host via launchd = blocked; a probe calling
// `containerURLForSecurityApplicationGroupIdentifier:` first, then doing raw
// file I/O in the same process, = instant, three consecutive launchd spawns,
// zero prompts). So the host calls that API once per process, before the
// first store access, purely for its registration side effect.
//
// The returned path is NOT used to locate the store. The app writes the
// store at the path derived by
// `DesktopBrowserAutofillCacheStore.defaultDirectory`, and the host must
// read exactly where the app wrote, so both sides use the same derivation.
// The two agree by construction today (the API returns
// `~/Library/Group Containers/<group>`); if a macOS release ever made them
// diverge, following the API here would break the pairing while the TCC
// benefit of the call itself would remain — so the derived path stays
// authoritative and the API result is only returned for sanity checks and
// tests.
//
// Everything is fail-soft: on any missing library, class, selector, or a
// nil URL the function returns null and the host proceeds with the derived
// path — never crash the host over an optimization of the prompt behavior.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _CPtrFromCString = Pointer<Void> Function(Pointer<Uint8>);
typedef _CMsgSend0 = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _CMsgSend1 =
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _CPoolPush = Pointer<Void> Function();
typedef _CPoolPop = Void Function(Pointer<Void>);
typedef _CMalloc = Pointer<Uint8> Function(IntPtr);
typedef _CFree = Void Function(Pointer<Uint8>);

const macosBrowserStoreAppGroup =
    'A8QUU5F9G3.dev.camillobucciarelli.kdbxKeyVault.browser';

bool _registered = false;
String? _containerPath;

/// Asserts membership of the browser-store app group with containermanagerd
/// (macOS only, once per process) and returns the container path the API
/// reported, or `null` off macOS or on any failure.
///
/// The path is informational; callers must keep using
/// `DesktopBrowserAutofillCacheStore.defaultDirectory` for store I/O.
String? ensureMacosGroupContainerRegistered() {
  if (!Platform.isMacOS) {
    return null;
  }
  if (_registered) {
    return _containerPath;
  }
  _registered = true;
  try {
    _containerPath = _containerPathFromFoundation();
  } catch (_) {
    _containerPath = null;
  }
  return _containerPath;
}

String? _containerPathFromFoundation() {
  // Foundation must be loaded for NSFileManager to resolve; a Dart AOT CLI
  // does not link it. libobjc comes in as a dependency but is opened
  // explicitly so a lookup failure surfaces here, inside the try.
  DynamicLibrary.open(
    '/System/Library/Frameworks/Foundation.framework/Foundation',
  );
  final objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
  final libSystem = DynamicLibrary.process();

  final objcGetClass = objc.lookupFunction<_CPtrFromCString, _CPtrFromCString>(
    'objc_getClass',
  );
  final selRegisterName = objc
      .lookupFunction<_CPtrFromCString, _CPtrFromCString>('sel_registerName');
  // objc_msgSend is looked up once and cast per call-site signature. Every
  // message sent here takes and returns pointer-sized values only, so the
  // plain (non-stret) variant is correct on both arm64 and x86_64.
  final msgSendPtr = objc.lookup<NativeFunction<_CMsgSend0>>('objc_msgSend');
  final msgSend0 = msgSendPtr.asFunction<_CMsgSend0>();
  final msgSend1 = msgSendPtr
      .cast<NativeFunction<_CMsgSend1>>()
      .asFunction<_CMsgSend1>();
  final poolPush = objc.lookupFunction<_CPoolPush, _CPoolPush>(
    'objc_autoreleasePoolPush',
  );
  final poolPop = objc.lookupFunction<_CPoolPop, void Function(Pointer<Void>)>(
    'objc_autoreleasePoolPop',
  );
  final malloc = libSystem
      .lookupFunction<_CMalloc, Pointer<Uint8> Function(int)>('malloc');
  final free = libSystem.lookupFunction<_CFree, void Function(Pointer<Uint8>)>(
    'free',
  );

  final allocations = <Pointer<Uint8>>[];
  Pointer<Uint8> cString(String value) {
    final bytes = utf8.encode(value);
    final buffer = malloc(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      buffer[i] = bytes[i];
    }
    buffer[bytes.length] = 0;
    allocations.add(buffer);
    return buffer;
  }

  String? dartString(Pointer<Void> utf8Ptr) {
    if (utf8Ptr == nullptr) {
      return null;
    }
    final bytes = utf8Ptr.cast<Uint8>();
    var length = 0;
    while (bytes[length] != 0) {
      length++;
    }
    return utf8.decode(
      List<int>.generate(length, (i) => bytes[i], growable: false),
    );
  }

  final pool = poolPush();
  try {
    final nsString = objcGetClass(cString('NSString'));
    final nsFileManager = objcGetClass(cString('NSFileManager'));
    if (nsString == nullptr || nsFileManager == nullptr) {
      return null;
    }
    final groupNsString = msgSend1(
      nsString,
      selRegisterName(cString('stringWithUTF8String:')),
      cString(macosBrowserStoreAppGroup).cast(),
    );
    final fileManager = msgSend0(
      nsFileManager,
      selRegisterName(cString('defaultManager')),
    );
    if (groupNsString == nullptr || fileManager == nullptr) {
      return null;
    }
    // The call whose side effect is the whole point: containermanagerd
    // records this process as a member of the group.
    final url = msgSend1(
      fileManager,
      selRegisterName(
        cString('containerURLForSecurityApplicationGroupIdentifier:'),
      ),
      groupNsString,
    );
    if (url == nullptr) {
      return null;
    }
    final path = msgSend0(url, selRegisterName(cString('path')));
    if (path == nullptr) {
      return null;
    }
    return dartString(msgSend0(path, selRegisterName(cString('UTF8String'))));
  } finally {
    poolPop(pool);
    for (final allocation in allocations) {
      free(allocation);
    }
  }
}
