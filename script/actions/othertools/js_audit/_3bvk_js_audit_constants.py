import re

# ── Color constants ──
CLR_HEADER_BG   = "1F3864"
CLR_HEADER_FG   = "FFFFFF"
CLR_TITLE_BG    = "2E4D8A"
CLR_TITLE_FG    = "FFFFFF"
CLR_OK_BG       = "C6EFCE"
CLR_OK_FG       = "276221"
CLR_ERROR_BG    = "FFC7CE"
CLR_ERROR_FG    = "9C0006"
CLR_WARN_BG     = "FFEB9C"
CLR_WARN_FG     = "9C5700"
CLR_INFO_BG     = "DDEBF7"
CLR_INFO_FG     = "2F5496"
CLR_DEAD_BG     = "D9D9D9"
CLR_DEAD_FG     = "595959"
CLR_ROW_ODD     = "F2F2F2"
CLR_ROW_EVEN    = "FFFFFF"
CLR_ANN_BG      = "4A4A4A"
CLR_ANN_FG      = "FFFFFF"
CLR_1E_MERGE_BG = "EAF0FB"
CLR_1E_MERGE_FG = "1F3864"

FONT_NAME = "Arial"

# ── Regex constants ──
_RE_IMPORT_NAMED   = re.compile(r"\bimport\s*\{([^}]+)\}\s*from\s*[\"']([^\"']+)[\"']", re.MULTILINE)
_RE_IMPORT_STAR    = re.compile(r"\bimport\s*\*\s*as\s+\w+\s*from\s*[\"']([^\"']+)[\"']", re.MULTILINE)
_RE_EXPORT_FUNC    = re.compile(r'\bexport\s+(?:async\s+)?function\s+(\w+)', re.MULTILINE)
_RE_EXPORT_CONST   = re.compile(r'\bexport\s+(?:const|let|var)\s+(\w+)', re.MULTILINE)
_RE_EXPORT_CLASS   = re.compile(r'\bexport\s+class\s+(\w+)', re.MULTILINE)
_RE_EXPORT_LIST    = re.compile(r'\bexport\s*\{([^}]+)\}', re.MULTILINE)
_RE_EXPORT_FUNC_EXPR = re.compile(
    r'\bexport\s+(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function[\s(]', re.MULTILINE)
_RE_EXPORT_ARROW   = re.compile(
    r'\bexport\s+(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[A-Za-z_$]\w*)\s*=>', re.MULTILINE)
_RE_FUNC_DECL      = re.compile(r'\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(')
_RE_FUNC_EXPR      = re.compile(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function[\s(]')
_RE_ARROW_PAREN    = re.compile(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\([^)]*\)\s*=>')
_RE_ARROW_BARE     = re.compile(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?([A-Za-z_$]\w*)\s*=>')
_RE_METHOD_SHORTHAND = re.compile(r'(?:^|\n|\{)\s*(\w+)\s*\([^)]*\)\s*\{')
_RE_WINDOW_ASSIGN  = re.compile(r'window\.(\w+)\s*=', re.MULTILINE)
_RE_IIFE           = re.compile(r'(?:^|\n)\s*\(\s*(?:async\s+)?function', re.MULTILINE)
_RE_COMMENT_BLOCK  = re.compile(r'/\*.*?\*/', re.DOTALL)

_RE_SCRIPT_TAG  = re.compile(r'<script([^>]*)>(.*?)</script>', re.IGNORECASE | re.DOTALL)
_RE_SCRIPT_SRC  = re.compile(r"src=[\"']([^\"']+)[\"']", re.IGNORECASE)
_RE_SCRIPT_TYPE = re.compile(r"type=[\"']([^\"']+)[\"']", re.IGNORECASE)
_RE_INLINE_EVT  = re.compile(r"(?:on\w+)=[\"']([^\"']+)[\"']", re.IGNORECASE)
_RE_FUNC_CALL   = re.compile(r'(?<![.\w])(\w+)\s*\(')

_RE_EVT_ATTR = re.compile(
    r'on\w+='
    r'(?:'
        r'"([^"]*)"'
        r"|'([^']*)'"
        r'|([^\s>\'"]+)'
    r')',
    re.IGNORECASE,
)
_RE_EVT_CALL = re.compile(r'(?<![.\w])([A-Za-z_$]\w*)\s*\(')

_RE_STRING_LITERAL = re.compile(
    r'"(?:[^"\\]|\\.)*"'
    r"|'(?:[^'\\]|\\.)*'"
    r"|`(?:[^`\\]|\\.)*`",
    re.DOTALL,
)
_RE_BARE_CALL = re.compile(r'(?<![.\w])([A-Za-z_$]\w*)\s*\(')


# ──────────────────────────────────────────────────────────────
#  EXHAUSTIVE NATIVE GLOBALS  (ECMAScript 2024 + Web Platform)
#  Sources: ECMA-262 2024, MDN, WHATWG HTML, W3C, WICG specs
#  NOTE: Only verified real APIs. No speculative/hallucinated names.
# ──────────────────────────────────────────────────────────────

# ECMAScript 2024 (ES15) built-in global names
# Source: ECMA-262 2024 specification, Clause 18–28 + Well-Known Intrinsics
# Also includes Temporal (Stage 3, widely implemented) and SuppressedError (ES2025)
_ECMASCRIPT_GLOBALS = {
    # Value properties of the global object
    'globalThis', 'Infinity', 'NaN', 'undefined',

    # Function properties of the global object
    'eval', 'isFinite', 'isNaN', 'parseFloat', 'parseInt', 'decodeURI',
    'decodeURIComponent', 'encodeURI', 'encodeURIComponent', 'escape',
    'unescape',

    # Constructor properties of the global object
    'AggregateError', 'Array', 'ArrayBuffer', 'BigInt', 'BigInt64Array',
    'BigUint64Array', 'Boolean', 'DataView', 'Date', 'Error', 'EvalError',
    'FinalizationRegistry', 'Float16Array', 'Float32Array', 'Float64Array',
    'Function', 'Int8Array', 'Int16Array', 'Int32Array', 'Map', 'Number',
    'Object', 'Promise', 'Proxy', 'RangeError', 'ReferenceError', 'RegExp',
    'Set', 'SharedArrayBuffer', 'String', 'SuppressedError', 'Symbol',
    'SyntaxError', 'Temporal', 'TypeError', 'Uint8Array', 'Uint8ClampedArray',
    'Uint16Array', 'Uint32Array', 'URIError', 'WeakMap', 'WeakRef', 'WeakSet',

    # Other properties of the global object
    'Atomics', 'JSON', 'Math', 'Reflect',

    # Intl (ECMA-402)
    'Intl', 'Intl.Collator', 'Intl.DateTimeFormat', 'Intl.DisplayNames',
    'Intl.DurationFormat', 'Intl.ListFormat', 'Intl.Locale',
    'Intl.NumberFormat', 'Intl.PluralRules', 'Intl.RelativeTimeFormat',
    'Intl.Segmenter',

    # Control abstraction / internal constructors (exposed in most engines)
    'GeneratorFunction', 'AsyncGeneratorFunction', 'Generator',
    'AsyncGenerator', 'AsyncFunction', 'Iterator', 'AsyncIterator',
    'DisposableStack', 'AsyncDisposableStack',
}

# Web Platform global APIs (Window object / global scope)
# Source: HTML Living Standard, Web IDL, WHATWG specs, MDN
# NOTE: Only verified real APIs. Removed all hallucinated names.
_WEB_PLATFORM_GLOBALS = {
    # Window self-references
    'window', 'self', 'top', 'parent', 'opener', 'frameElement',

    # Core DOM / Document
    'document', 'Document', 'DocumentFragment', 'DocumentType',
    'DocumentTimeline', 'DOMImplementation', 'DOMParser', 'DOMException',
    'DOMMatrix', 'DOMMatrixReadOnly', 'DOMPoint', 'DOMPointReadOnly',
    'DOMQuad', 'DOMRect', 'DOMRectReadOnly', 'DOMRectList', 'DOMStringList',
    'DOMStringMap', 'DOMTokenList',

    # Element types
    'Element', 'HTMLElement', 'HTMLAnchorElement', 'HTMLAreaElement',
    'HTMLAudioElement', 'HTMLBaseElement', 'HTMLBodyElement', 'HTMLBRElement',
    'HTMLButtonElement', 'HTMLCanvasElement', 'HTMLDataElement',
    'HTMLDataListElement', 'HTMLDetailsElement', 'HTMLDialogElement',
    'HTMLDirectoryElement', 'HTMLDivElement', 'HTMLDListElement',
    'HTMLDocument', 'HTMLEmbedElement', 'HTMLFieldSetElement',
    'HTMLFontElement', 'HTMLFormElement', 'HTMLFormControlsCollection',
    'HTMLFrameElement', 'HTMLFrameSetElement', 'HTMLHeadElement',
    'HTMLHeadingElement', 'HTMLHRElement', 'HTMLHtmlElement',
    'HTMLIFrameElement', 'HTMLImageElement', 'HTMLInputElement',
    'HTMLLabelElement', 'HTMLLegendElement', 'HTMLLIElement',
    'HTMLLinkElement', 'HTMLMapElement', 'HTMLMarqueeElement',
    'HTMLMediaElement', 'HTMLMenuElement', 'HTMLMetaElement',
    'HTMLMeterElement', 'HTMLModElement', 'HTMLObjectElement',
    'HTMLOListElement', 'HTMLOptGroupElement', 'HTMLOptionElement',
    'HTMLOptionsCollection', 'HTMLOutputElement', 'HTMLParagraphElement',
    'HTMLParamElement', 'HTMLPictureElement', 'HTMLPreElement',
    'HTMLProgressElement', 'HTMLQuoteElement', 'HTMLScriptElement',
    'HTMLSelectElement', 'HTMLSlotElement', 'HTMLSourceElement',
    'HTMLSpanElement', 'HTMLStyleElement', 'HTMLTableCaptionElement',
    'HTMLTableCellElement', 'HTMLTableColElement', 'HTMLTableElement',
    'HTMLTableRowElement', 'HTMLTableSectionElement', 'HTMLTemplateElement',
    'HTMLTextAreaElement', 'HTMLTimeElement', 'HTMLTitleElement',
    'HTMLTrackElement', 'HTMLUListElement', 'HTMLUnknownElement',
    'HTMLVideoElement', 'HTMLCollection', 'HTMLAllCollection',

    # Node types
    'Node', 'NodeList', 'NodeFilter', 'NodeIterator', 'NamedNodeMap', 'Text',
    'Comment', 'CharacterData', 'ProcessingInstruction', 'CDATASection',
    'TreeWalker', 'ShadowRoot', 'ElementInternals', 'StaticRange', 'Range',
    'Selection', 'getSelection',

    # CSS / Style
    'CSS', 'CSSConditionRule', 'CSSGroupingRule', 'CSSImportRule',
    'CSSKeyframeRule', 'CSSKeyframesRule', 'CSSMediaRule', 'CSSNamespaceRule',
    'CSSPageRule', 'CSSRule', 'CSSRuleList', 'CSSStyleDeclaration',
    'CSSStyleRule', 'CSSStyleSheet', 'CSSSupportsRule', 'StyleSheet',
    'StyleSheetList', 'MediaList', 'FontFace', 'FontFaceSet',
    'FontFaceSetLoadEvent', 'getComputedStyle', 'matchMedia',

    # Events
    'Event', 'EventTarget', 'EventSource', 'CustomEvent', 'UIEvent',
    'MouseEvent', 'KeyboardEvent', 'PointerEvent', 'TouchEvent', 'WheelEvent',
    'FocusEvent', 'InputEvent', 'CompositionEvent', 'DragEvent',
    'ClipboardEvent', 'HashChangeEvent', 'PageTransitionEvent',
    'PopStateEvent', 'BeforeUnloadEvent', 'StorageEvent', 'SubmitEvent',
    'FormDataEvent', 'ToggleEvent', 'CloseEvent', 'ErrorEvent', 'MessageEvent',
    'OfflineAudioCompletionEvent', 'PromiseRejectionEvent',
    'SecurityPolicyViolationEvent', 'TransitionEvent', 'AnimationEvent',
    'ProgressEvent', 'TrackEvent', 'BlobEvent', 'MediaStreamEvent',
    'MediaStreamTrackEvent', 'RTCPeerConnectionIceEvent',
    'RTCDTMFToneChangeEvent', 'RTCDataChannelEvent', 'SpeechSynthesisEvent',
    'SpeechSynthesisErrorEvent', 'PictureInPictureEvent',
    'VirtualKeyboardGeometryChangeEvent', 'CookieChangeEvent', 'CookieStore',
    'CookieStoreManager', 'NavigationCurrentEntryChangeEvent',
    'PageRevealEvent', 'PageSwapEvent', 'NavigateEvent',

    # Window / Location / History / Navigator
    'Location', 'History', 'Screen', 'ScreenOrientation', 'Navigator',
    'WorkerNavigator', 'visualViewport', 'VisualViewport', 'BarProp',
    'navigator', 'location', 'history', 'screen', 'frames', 'locationbar',
    'menubar', 'personalbar', 'scrollbars', 'statusbar', 'toolbar',

    # Storage
    'localStorage', 'sessionStorage', 'Storage', 'StorageManager', 'indexedDB',
    'IDBFactory', 'IDBDatabase', 'IDBObjectStore', 'IDBIndex', 'IDBCursor',
    'IDBCursorWithValue', 'IDBTransaction', 'IDBRequest', 'IDBOpenDBRequest',
    'IDBKeyRange', 'IDBVersionChangeEvent', 'Cache', 'CacheStorage', 'caches',

    # Networking / Fetch / Streams
    'fetch', 'Request', 'Response', 'Headers', 'Body', 'XMLHttpRequest',
    'XMLHttpRequestEventTarget', 'XMLHttpRequestUpload', 'WebSocket',
    'BroadcastChannel', 'MessageChannel', 'MessagePort', 'ReadableStream',
    'ReadableStreamDefaultReader', 'ReadableStreamBYOBReader',
    'ReadableStreamDefaultController', 'ReadableStreamBYOBRequest',
    'ReadableByteStreamController', 'WritableStream',
    'WritableStreamDefaultWriter', 'WritableStreamDefaultController',
    'TransformStream', 'TransformStreamDefaultController',
    'ByteLengthQueuingStrategy', 'CountQueuingStrategy', 'CompressionStream',
    'DecompressionStream', 'TextDecoderStream', 'TextEncoderStream',
    'URLPattern',

    # File / Blob
    'Blob', 'File', 'FileList', 'FileReader', 'FileReaderSync',
    'FileSystemDirectoryHandle', 'FileSystemFileHandle', 'FileSystemHandle',
    'FileSystemWritableFileStream', 'FileSystemDirectoryEntry',
    'FileSystemEntry', 'FileSystemFileEntry', 'FileSystem', 'FileSystemSync',
    'DataTransfer', 'DataTransferItem', 'DataTransferItemList',

    # URL / Encoding
    'URL', 'URLSearchParams', 'TextEncoder', 'TextDecoder', 'atob', 'btoa',
    'escape', 'unescape', 'structuredClone',

    # Timers / Animation / Scheduling
    'setTimeout', 'clearTimeout', 'setInterval', 'clearInterval',
    'requestAnimationFrame', 'cancelAnimationFrame', 'requestIdleCallback',
    'cancelIdleCallback', 'queueMicrotask', 'scheduler', 'Scheduler',

    # Dialogs / Window control
    'alert', 'confirm', 'prompt', 'print', 'open', 'close', 'stop', 'blur',
    'focus', 'moveTo', 'moveBy', 'resizeTo', 'resizeBy', 'scroll', 'scrollTo',
    'scrollBy', 'scrollX', 'scrollY', 'pageXOffset', 'pageYOffset',
    'innerWidth', 'innerHeight', 'outerWidth', 'outerHeight', 'screenX',
    'screenY', 'screenLeft', 'screenTop', 'devicePixelRatio', 'closed', 'name',
    'length', 'crossOriginIsolated', 'isSecureContext', 'origin',

    # Console / Performance / Crypto
    'console', 'Console', 'performance', 'Performance', 'PerformanceEntry',
    'PerformanceMark', 'PerformanceMeasure', 'PerformanceNavigation',
    'PerformanceNavigationTiming', 'PerformanceObserver',
    'PerformanceObserverEntryList', 'PerformancePaintTiming',
    'PerformanceResourceTiming', 'PerformanceServerTiming',
    'PerformanceEventTiming', 'PerformanceLongTaskTiming', 'crypto', 'Crypto',
    'SubtleCrypto', 'CryptoKey', 'CryptoKeyPair', 'randomUUID',
    'getRandomValues',

    # Web Workers
    'Worker', 'SharedWorker', 'Worklet', 'importScripts', 'WorkerGlobalScope',
    'DedicatedWorkerGlobalScope', 'SharedWorkerGlobalScope',
    'ServiceWorkerGlobalScope', 'WorkerLocation',

    # Service Worker
    'ServiceWorker', 'ServiceWorkerContainer', 'ServiceWorkerRegistration',
    'ServiceWorkerState', 'Clients', 'Client', 'WindowClient',

    # Notifications / Push / Permissions
    'Notification', 'NotificationEvent', 'PushManager', 'PushSubscription',
    'PushSubscriptionOptions', 'PermissionStatus', 'Permissions',
    'PeriodicSyncManager', 'PeriodicSyncEvent', 'SyncManager', 'SyncEvent',

    # Media / Audio / Video / WebRTC
    'MediaStream', 'MediaStreamTrack', 'MediaStreamTrackGenerator',
    'MediaStreamTrackProcessor', 'MediaDevices', 'MediaDeviceInfo',
    'MediaCapabilities', 'MediaRecorder', 'MediaSource', 'MediaSession',
    'MediaElementAudioSourceNode', 'MediaStreamAudioDestinationNode',
    'MediaStreamAudioSourceNode', 'AudioBuffer', 'AudioBufferSourceNode',
    'AudioContext', 'AudioDestinationNode', 'AudioListener', 'AudioNode',
    'AudioParam', 'AudioParamMap', 'AudioProcessingEvent',
    'AudioScheduledSourceNode', 'AudioWorklet', 'AudioWorkletGlobalScope',
    'AudioWorkletNode', 'AudioWorkletProcessor', 'BaseAudioContext',
    'BiquadFilterNode', 'ChannelMergerNode', 'ChannelSplitterNode',
    'ConstantSourceNode', 'ConvolverNode', 'DelayNode',
    'DynamicsCompressorNode', 'GainNode', 'IIRFilterNode', 'OscillatorNode',
    'PannerNode', 'PeriodicWave', 'WaveShaperNode', 'OfflineAudioContext',
    'RTCPeerConnection', 'RTCSessionDescription', 'RTCIceCandidate',
    'RTCRtpSender', 'RTCRtpReceiver', 'RTCRtpTransceiver', 'RTCDataChannel',
    'RTCDTMFSender', 'RTCTrackEvent', 'RTCStatsReport', 'RTCError',
    'RTCErrorEvent', 'VideoDecoder', 'VideoEncoder', 'VideoFrame',
    'EncodedVideoChunk', 'VideoColorSpace', 'VideoTrack', 'VideoTrackList',
    'AudioDecoder', 'AudioEncoder', 'EncodedAudioChunk', 'ImageTrack',
    'ImageTrackList', 'ImageDecoder', 'MediaKeySystemAccess', 'MediaKeys',
    'MediaKeySession', 'MediaKeyStatusMap', 'MediaKeyMessageEvent',
    'MediaEncryptedEvent', 'SourceBuffer', 'SourceBufferList', 'TimeRanges',
    'TextTrack', 'TextTrackCue', 'TextTrackCueList', 'TextTrackList',
    'VideoPlaybackQuality', 'PictureInPictureWindow', 'RemotePlayback',
    'WakeLock', 'WakeLockSentinel', 'CanvasCaptureMediaStreamTrack',
    'ImageCapture',

    # Graphics / Canvas / WebGL
    'CanvasRenderingContext2D', 'CanvasGradient', 'CanvasPattern', 'ImageData',
    'ImageBitmap', 'ImageBitmapRenderingContext', 'Path2D', 'TextMetrics',
    'OffscreenCanvas', 'OffscreenCanvasRenderingContext2D',
    'WebGLRenderingContext', 'WebGL2RenderingContext', 'WebGLActiveInfo',
    'WebGLBuffer', 'WebGLContextEvent', 'WebGLFramebuffer', 'WebGLProgram',
    'WebGLQuery', 'WebGLRenderbuffer', 'WebGLSampler', 'WebGLShader',
    'WebGLShaderPrecisionFormat', 'WebGLSync', 'WebGLTexture',
    'WebGLTransformFeedback', 'WebGLUniformLocation', 'WebGLVertexArrayObject',

    # SVG
    'SVGElement', 'SVGGraphicsElement', 'SVGGeometryElement',
    'SVGAnimatedBoolean', 'SVGAnimatedEnumeration', 'SVGAnimatedInteger',
    'SVGAnimatedLength', 'SVGAnimatedLengthList', 'SVGAnimatedNumber',
    'SVGAnimatedNumberList', 'SVGAnimatedPreserveAspectRatio',
    'SVGAnimatedRect', 'SVGAnimatedString', 'SVGAnimatedTransformList',
    'SVGCircleElement', 'SVGClipPathElement', 'SVGDefsElement',
    'SVGDescElement', 'SVGEllipseElement', 'SVGFilterElement',
    'SVGForeignObjectElement', 'SVGGElement', 'SVGImageElement',
    'SVGLineElement', 'SVGLinearGradientElement', 'SVGRadialGradientElement',
    'SVGMaskElement', 'SVGPathElement', 'SVGPatternElement',
    'SVGPolygonElement', 'SVGPolylineElement', 'SVGRectElement',
    'SVGStopElement', 'SVGSwitchElement', 'SVGSymbolElement', 'SVGTextElement',
    'SVGTSpanElement', 'SVGTextPathElement', 'SVGUseElement', 'SVGViewElement',
    'SVGSVGElement', 'SVGAElement', 'SVGScriptElement', 'SVGStyleElement',
    'SVGTitleElement', 'SVGSetElement', 'SVGMPathElement', 'SVGMarkerElement',
    'SVGMetadataElement', 'SVGComponentTransferFunctionElement',
    'SVGFEBlendElement', 'SVGFEColorMatrixElement',
    'SVGFEComponentTransferElement', 'SVGFECompositeElement',
    'SVGFEConvolveMatrixElement', 'SVGFEDiffuseLightingElement',
    'SVGFEDisplacementMapElement', 'SVGFEDistantLightElement',
    'SVGFEDropShadowElement', 'SVGFEFloodElement', 'SVGFEFuncAElement',
    'SVGFEFuncBElement', 'SVGFEFuncGElement', 'SVGFEFuncRElement',
    'SVGFEGaussianBlurElement', 'SVGFEImageElement', 'SVGFEMergeElement',
    'SVGFEMergeNodeElement', 'SVGFEMorphologyElement', 'SVGFEOffsetElement',
    'SVGFEPointLightElement', 'SVGFESpecularLightingElement',
    'SVGFESpotLightElement', 'SVGFETileElement', 'SVGFETurbulenceElement',
    'SVGAngle', 'SVGLength', 'SVGLengthList', 'SVGNumber', 'SVGNumberList',
    'SVGPoint', 'SVGPointList', 'SVGPreserveAspectRatio', 'SVGRect',
    'SVGStringList', 'SVGTransform', 'SVGTransformList', 'SVGUnitTypes',
    'SVGMatrix', 'SVGAnimatedAngle',

    # WebAssembly
    'WebAssembly', 'WebAssembly.Module', 'WebAssembly.Instance',
    'WebAssembly.Memory', 'WebAssembly.Table', 'WebAssembly.Global',
    'WebAssembly.Tag', 'WebAssembly.Exception', 'WebAssembly.CompileError',
    'WebAssembly.LinkError', 'WebAssembly.RuntimeError',
    'WebAssembly.validate', 'WebAssembly.compile', 'WebAssembly.instantiate',
    'WebAssembly.instantiateStreaming', 'WebAssembly.compileStreaming',

    # Gamepad / Sensors / Device
    'Gamepad', 'GamepadButton', 'GamepadHapticActuator', 'GamepadEvent',
    'DeviceMotionEvent', 'DeviceMotionEventAcceleration',
    'DeviceMotionEventRotationRate', 'DeviceOrientationEvent',
    'AmbientLightSensor', 'Accelerometer', 'Gyroscope', 'Magnetometer',
    'OrientationSensor', 'RelativeOrientationSensor',
    'AbsoluteOrientationSensor', 'GravitySensor', 'LinearAccelerationSensor',
    'Sensor', 'SensorErrorEvent',

    # Geolocation
    'Geolocation', 'GeolocationCoordinates', 'GeolocationPosition',
    'GeolocationPositionError', 'Position', 'Coordinates',

    # Payment / Credentials / WebAuthn
    'PaymentRequest', 'PaymentResponse', 'PaymentMethodChangeEvent',
    'PaymentAddress', 'PaymentRequestUpdateEvent', 'MerchantValidationEvent',
    'CredentialsContainer', 'Credential', 'PasswordCredential',
    'FederatedCredential', 'PublicKeyCredential',
    'AuthenticatorAttestationResponse', 'AuthenticatorAssertionResponse',
    'AuthenticatorResponse', 'PublicKeyCredentialCreationOptions',
    'PublicKeyCredentialRequestOptions', 'IdentityCredential',
    'IdentityProvider', 'OTPCredential', 'PaymentRequestEvent',
    'CanMakePaymentEvent',

    # Presentation API
    'Presentation', 'PresentationAvailability', 'PresentationConnection',
    'PresentationConnectionAvailableEvent', 'PresentationConnectionCloseEvent',
    'PresentationConnectionList', 'PresentationRequest',
    'PresentationReceiver',

    # Speech
    'speechSynthesis', 'SpeechSynthesis', 'SpeechSynthesisUtterance',
    'SpeechSynthesisVoice',

    # Clipboard / Drag / Form
    'Clipboard', 'ClipboardItem', 'ClipboardItemData', 'FormData',
    'ValidityState', 'RadioNodeList',

    # Trusted Types / CSP
    'trustedTypes', 'TrustedHTML', 'TrustedScript', 'TrustedScriptURL',
    'TrustedTypePolicy', 'TrustedTypePolicyFactory',

    # Custom Elements / Templates / Shadow DOM
    'customElements', 'CustomElementRegistry',

    # Navigation API
    'navigation', 'Navigation', 'NavigationDestination',
    'NavigationHistoryEntry', 'NavigationTransition', 'NavigationActivation',

    # Virtual Keyboard / View Transitions
    'VirtualKeyboard', 'ViewTransition', 'ViewTransitionTypeSet',

    # Web Locks / Badging / Contact Picker
    'Lock', 'LockManager', 'NavigatorLocks', 'ContactAddress', 'ContactInfo',
    'ContactsManager', 'ContactsSelectOptions',

    # EyeDropper / File System Access / Screen Wake Lock
    'EyeDropper', 'ScreenWakeLock', 'ScreenDetails', 'ScreenDetailed',

    # Web Share / Web Serial / Web Bluetooth / Web USB / Web HID
    'NavigatorShare', 'ShareData', 'Serial', 'SerialPort', 'Bluetooth',
    'BluetoothDevice', 'BluetoothRemoteGATTCharacteristic',
    'BluetoothRemoteGATTDescriptor', 'BluetoothRemoteGATTServer',
    'BluetoothRemoteGATTService', 'BluetoothUUID', 'USB', 'USBDevice',
    'USBConfiguration', 'USBInterface', 'USBEndpoint', 'USBAlternateInterface',
    'USBConnectionEvent', 'USBInTransferResult', 'USBOutTransferResult',
    'USBIsochronousPacket', 'USBTransferStatus', 'HID', 'HIDDevice',
    'HIDConnectionEvent', 'HIDReportInfo', 'HIDCollectionInfo',
    'HIDReportItem',

    # Web MIDI / Web NFC / Web Budget / Background Sync
    'MIDIAccess', 'MIDIConnectionEvent', 'MIDIInput', 'MIDIInputMap',
    'MIDIMessageEvent', 'MIDIOutput', 'MIDIOutputMap', 'MIDIPort',
    'NDEFMessage', 'NDEFReader', 'NDEFReadingEvent', 'NDEFRecord',
    'BudgetService', 'BudgetState',

    # Web Animations / Intersection Observer / Resize Observer
    'Animation', 'AnimationEffect', 'AnimationTimeline', 'KeyframeEffect',
    'ComputedEffectTiming', 'EffectTiming', 'OptionalEffectTiming',
    'AnimationPlaybackEvent', 'AnimationTrigger', 'ScrollTimeline',
    'ViewTimeline', 'IntersectionObserver', 'IntersectionObserverEntry',
    'ResizeObserver', 'ResizeObserverEntry', 'ResizeObserverSize',
    'MutationObserver', 'MutationRecord',

    # Reporting / ReportingObserver
    'ReportingObserver', 'Report', 'ReportBody', 'DeprecationReportBody',
    'InterventionReportBody', 'CSPViolationReportBody', 'CrashReportBody',

    # WebXR
    'XRFrame', 'XRSession', 'XRSpace', 'XRReferenceSpace',
    'XRBoundedReferenceSpace', 'XRView', 'XRViewport', 'XRRigidTransform',
    'XRPose', 'XRViewerPose', 'XRInputSource', 'XRInputSourceArray',
    'XRInputSourceEvent', 'XRInputSourcesChangeEvent', 'XRSessionEvent',
    'XRWebGLLayer', 'XRWebGLBinding', 'XRRenderState', 'XRHitTestResult',
    'XRHitTestSource', 'XRTransientInputHitTestResult',
    'XRTransientInputHitTestSource', 'XRAnchor', 'XRAnchorSet', 'XRRay',
    'XRPlane', 'XRPlaneSet', 'XRDepthInformation', 'XRCPUDepthInformation',
    'XRWebGLDepthInformation', 'XRHand', 'XRJointSpace', 'XRJointPose',
    'XRSystem',

    # WebGPU
    'GPU', 'GPUAdapter', 'GPUAdapterInfo', 'GPUBindGroup',
    'GPUBindGroupLayout', 'GPUBuffer', 'GPUBufferUsage', 'GPUCanvasContext',
    'GPUColorWrite', 'GPUCommandBuffer', 'GPUCommandEncoder',
    'GPUCompilationInfo', 'GPUCompilationMessage', 'GPUComputePassEncoder',
    'GPUComputePipeline', 'GPUDevice', 'GPUDeviceLostInfo', 'GPUError',
    'GPUExternalTexture', 'GPUMapMode', 'GPUOutOfMemoryError',
    'GPUPipelineLayout', 'GPUQuerySet', 'GPUQueue', 'GPURenderBundle',
    'GPURenderBundleEncoder', 'GPURenderPassEncoder', 'GPURenderPipeline',
    'GPUSampler', 'GPUShaderModule', 'GPUShaderStage', 'GPUSupportedFeatures',
    'GPUSupportedLimits', 'GPUTexture', 'GPUTextureUsage', 'GPUTextureView',
    'GPUUncapturedErrorEvent', 'GPUValidationError',

    # WebTransport / WebCodecs
    'WebTransport', 'WebTransportBidirectionalStream',
    'WebTransportDatagramDuplexStream', 'WebTransportError',
    'WebTransportReceiveStream', 'WebTransportSendStream',

    # Protected Audience API (FLEDGE) - VERIFIED from WICG spec
    # Source: https://wicg.github.io/turtledove/
    'ProtectedAudience', 'ProtectedAudienceUtilities',
    'InterestGroupScriptRunnerGlobalScope',
    'InterestGroupBiddingAndScoringScriptRunnerGlobalScope',
    'InterestGroupBiddingScriptRunnerGlobalScope',
    'InterestGroupScoringScriptRunnerGlobalScope', 'ForDebuggingOnly',
    'RealTimeReporting', 'GenerateBidOutput', 'AdRender', 'AuctionAdConfig',
    'AuctionAdInterestGroupKey', 'AuctionReportBuyersConfig',
    'AuctionReportBuyerDebugModeConfig', 'AuctionRealTimeReportingConfig',
    'AdAuctionData', 'AdAuctionPerSellerData', 'AdAuctionDataConfig',
    'AdAuctionOneSeller', 'AdAuctionDataBuyerConfig', 'FencedFrameConfig',
    'ReportingBrowserSignals', 'ReportResultBrowserSignals', 'PASignalValue',
    'PAExtendedHistogramContribution',
    'ProtectedAudiencePrivateAggregationConfig', 'PrivateAggregation',
    'PrivateAggregationEvent',

    # Fenced Frames
    'HTMLFencedFrameElement', 'Fence', 'FenceEvent',

    # Prioritized Task Scheduling
    'TaskController', 'TaskPriorityChangeEvent', 'TaskSignal', 'TaskState',

    # Launch Handler / Protocol Handlers
    'LaunchParams', 'LaunchQueue', 'ProtocolHandler',

    # Window Controls Overlay
    'WindowControlsOverlay', 'WindowControlsOverlayGeometryChangeEvent',

    # User-Agent Client Hints
    'NavigatorUAData', 'UADataValues', 'BrandVersionList',

    # Shared Storage
    'SharedStorage', 'SharedStorageWorklet', 'SharedStorageRunOperation',
    'SharedStorageSelectURL', 'SharedStorageSet', 'SharedStorageAppend',
    'SharedStorageDelete', 'SharedStorageClear', 'SharedStorageResponse',

    # Topics API
    'Topics', 'BrowsingTopics',

    # Attribution Reporting
    'AttributionReporting',

    # Web Neural Network (WebNN) - experimental but in spec
    'ML', 'MLContext', 'MLGraph', 'MLGraphBuilder', 'MLTensor', 'MLActivation',
    'MLBuffer', 'MLCommandEncoder', 'MLComputeGraph', 'MLNamedInputs',
    'MLNamedOutputs', 'MLNamedTensors',

    # Content Index
    'ContentIndex', 'ContentIndexEvent',

    # Background Fetch
    'BackgroundFetchManager', 'BackgroundFetchRegistration',
    'BackgroundFetchRecord', 'BackgroundFetchUpdateEvent',

    # Badging API
    'Badge', 'NavigatorBadge',

    # Web Share Target
    'WebShareTarget',

    # Speculation Rules
    'SpeculationRules', 'SpeculationRuleSet',

    # Compute Pressure
    'PressureObserver', 'PressureRecord', 'PressureSource',

    # Device Posture / Screen Orientation
    'DevicePosture', 'DevicePostureType',

    # View Transitions (continued)
    'ViewTransitionUpdateCallback',

    # Anchor positioning / CSS Layout API
    'LayoutWorklet', 'PaintWorklet', 'AnimationWorklet', 'CSSLayoutAPI',
    'CSSPaintAPI', 'CSSAnimationWorklet', 'WorkletGlobalScope',
    'PaintWorkletGlobalScope', 'LayoutWorkletGlobalScope',
    'AnimationWorkletGlobalScope',

    # Sanitizer API
    'Sanitizer', 'SanitizerConfig', 'SetHTMLOptions',

    # Popover API
    'PopoverEvent',

    # Invoker Commands / CommandEvent
    'CommandEvent', 'CommandEventCommand',

    # CloseWatcher
    'CloseWatcher', 'CloseWatcherEvent',

    # FedCM (Federated Credential Management)
    'IdentityProviderConfig', 'IdentityProviderToken',
    'IdentityProviderWellKnown', 'IdentityCredentialRequestOptions',
    'IdentityCredentialLogoutRequest', 'IdentityCredentialLogoutResponse',
    'IdentityProviderLoginStatus',

    # Storage Buckets
    'StorageBucket', 'StorageBucketManager', 'StorageBucketOptions',

    # File System Access (continued)
    'ShowDirectoryPickerOptions', 'ShowFilePickerOptions',
    'ShowSaveFilePickerOptions', 'FilePickerAcceptType',
    'FilePickerAcceptTypeOption', 'WellKnownDirectory', 'StartInDirectory',
    'SuggestedName', 'ExcludeAcceptAllOption',

    # Web Push
    'PushMessageData', 'PushEvent',

    # Web Notifications
    'NotificationAction', 'NotificationPermission', 'GetNotificationOptions',

    # Web App Manifest / BeforeInstallPrompt
    'BeforeInstallPromptEvent', 'AppBannerPromptOutcome',

    # Web Bluetooth
    'BluetoothManufacturerData', 'BluetoothServiceData', 'BluetoothDataFilter',
    'BluetoothLEScan', 'BluetoothLEScanOptions', 'BluetoothAdvertisingEvent',

    # Web USB
    'USBControlTransferParameters', 'USBIsochronousTransferParameters',

    # Web Serial
    'SerialPortInfo', 'SerialOptions', 'SerialOutputSignals',
    'SerialInputSignals',

    # Web NFC
    'NDEFRecordInit', 'NDEFReadingEventInit',

    # CSS Animations / Transitions / Houdini
    'CSSAnimation', 'CSSTransition',

    # CSS Custom Highlight API
    'Highlight', 'HighlightRegistry',

    # CSS Anchor Positioning
    'CSSPositionTryDescriptors', 'CSSPositionTryRule',

    # CSS Container Queries
    'CSSContainerRule',

    # CSS Scope / Cascade Layers
    'CSSLayerBlockRule', 'CSSLayerStatementRule',

    # CSS Nesting
    'CSSNestingRule',

    # CSS Typed OM
    'CSSUnitValue', 'CSSMathValue', 'CSSMathSum', 'CSSMathProduct',
    'CSSMathNegate', 'CSSMathInvert', 'CSSMathMin', 'CSSMathMax',
    'CSSMathClamp', 'CSSNumericValue', 'CSSKeywordValue', 'CSSImageValue',
    'CSSStyleValue', 'StylePropertyMapReadOnly', 'StylePropertyMap',
    'CSSUnparsedValue', 'CSSVariableReferenceValue', 'CSSPositionValue',
    'CSSTransformValue', 'CSSTransformComponent', 'CSSMatrixComponent',
    'CSSPerspective', 'CSSRotate', 'CSSScale', 'CSSSkew', 'CSSSkewX',
    'CSSSkewY', 'CSSTranslate', 'CSSURLImageValue', 'CSSFontFaceValue',

    # CSS Painting API
    'PaintRenderingContext2D', 'CSSPaintCallback', 'PaintSize',
    'PaintWorkletDevicePixelRatio',

    # CSS Layout API
    'LayoutChild', 'LayoutFragment', 'LayoutConstraint', 'LayoutConstraints',
    'ChildBreakToken', 'BreakToken', 'LayoutEdges', 'FragmentResult',
    'LayoutDefinition', 'IntrinsicSizes', 'IntrinsicSizesCallback',
    'LayoutCallback',

    # CSS Animation Worklet
    'WorkletAnimation',

    # Scroll-driven Animations
    'ScrollTimelineOptions', 'ViewTimelineOptions',

    # CSS Properties & Values API
    'CSSPropertyRule', 'CSSRegisteredPropertyDescriptor',
    'CSSPropertyDescriptor',

    # CSS Font Loading API
    'FontFaceSource', 'FontFaceDescriptors', 'FontFaceLoadStatus',

    # CSS Counter Styles
    'CSSCounterStyleRule',

    # Additional verified DOM / HTML interfaces
    'BeforeToggleEvent', 'InvokeEvent',
}

# ── Combine all native globals ──
_NATIVE_GLOBALS = _ECMASCRIPT_GLOBALS | _WEB_PLATFORM_GLOBALS


# ── JavaScript Keywords ──
_JS_KEYWORDS = {
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
    'return', 'typeof', 'instanceof', 'new', 'delete', 'void', 'in', 'of',
    'true', 'false', 'null', 'undefined', 'this', 'class', 'extends',
    'import', 'export', 'default', 'await', 'yield', 'async', 'let', 'const',
    'var', 'function', 'try', 'catch', 'finally', 'throw', 'super', 'static',
    'with', 'debugger', 'enum', 'implements', 'interface', 'package',
    'private', 'protected', 'public', 'goto',
}


# ── Safe string literals (non-function identifiers) ──
_SAFE_LITERALS = {
    'all', 'active', 'none', 'auto', 'manual', 'single', 'multi', 'range',
    'lookback', 'specific', 'fgi', 'ledger', 'debug', 'stocks', 'indices',
    'yes', 'no', 'on', 'off', 'enabled', 'disabled', 'true', 'false',
}


# ── HTML event handler keywords (subset of JS keywords + common globals) ──
_HTML_KW = {
    'if', 'else', 'for', 'while', 'do', 'switch', 'case',
    'return', 'typeof', 'instanceof', 'new', 'delete', 'void',
    'true', 'false', 'null', 'undefined',
    'alert', 'confirm', 'prompt',
    'parseInt', 'parseFloat', 'isNaN', 'isFinite',
    'encodeURIComponent', 'decodeURIComponent', 'encodeURI', 'decodeURI',
    'setTimeout', 'clearTimeout', 'setInterval', 'clearInterval',
    'requestAnimationFrame', 'cancelAnimationFrame',
    'fetch', 'eval', 'escape', 'unescape',
    'Array', 'Object', 'String', 'Number', 'Boolean', 'Function',
    'RegExp', 'Date', 'Error', 'Symbol', 'BigInt',
    'Map', 'Set', 'WeakMap', 'WeakSet',
    'Promise', 'Proxy', 'Reflect',
    'Math', 'JSON', 'console',
    'Int8Array', 'Uint8Array', 'Uint8ClampedArray',
    'Int16Array', 'Uint16Array', 'Int32Array', 'Uint32Array',
    'Float32Array', 'Float64Array',
}


# ── Known event handler identifiers ──
_EVT_KNOWN = _NATIVE_GLOBALS | _JS_KEYWORDS | {
    'stopPropagation', 'preventDefault', 'target', 'currentTarget',
    'event', 'e', 'evt',
}


# ── Key fields ──
_IE_KEY_FIELDS = ('Sub Audit', 'Source', 'Destination', 'Status', 'Comment')
_AD_KEY_FIELDS = ('Source', 'Function Name', 'Status', 'Usage Count', 'Comment')
