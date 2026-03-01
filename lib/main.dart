import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'platform/file_exporter.dart';
import 'package:e2e_web/platform/file_exporter.dart';




void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BumbleE2EApp());
}

///
/// Bumble-inspired palette
///
class BumbleColors {
  static const yellow = Color(0xFFFFC629);
  static const black = Color(0xFF0B0B0B);
  static const white = Color(0xFFFFFFFF);
  static const softBg = Color(0xFFFFF7DD);
  static const card = Color(0xFFFFFFFF);
  static const subtleText = Color(0xFF6B6B6B);
  static const border = Color(0x22000000);
}

class BumbleE2EApp extends StatelessWidget {
  const BumbleE2EApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: BumbleColors.softBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BumbleColors.yellow,
        brightness: Brightness.light,
        primary: BumbleColors.yellow,
        onPrimary: BumbleColors.black,
        surface: BumbleColors.card,
        onSurface: BumbleColors.black,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontWeight: FontWeight.w800),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BumbleColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: BumbleColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: BumbleColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xAA000000), width: 1.2),
        ),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'E2E Encrypt',
      theme: theme,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Keep pages alive; avoid recreating widgets every build.
  final List<Widget> _pages = const [EncryptView(), DecryptView(), AboutView()];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: BumbleColors.softBg,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: BumbleColors.yellow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                  const Icon(Icons.lock_rounded, color: BumbleColors.black),
                ),
                const SizedBox(width: 12),
                const Text('E2E File Encrypt'),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: () => _showQuickKeyDialog(context),
                  icon: const Icon(Icons.key_rounded),
                  label: Text(isNarrow ? 'Key' : 'Generate Key'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BumbleColors.yellow,
                    foregroundColor: BumbleColors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IndexedStack(index: _index, children: _pages),
                ),
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.lock_outline_rounded),
                selectedIcon: Icon(Icons.lock_rounded),
                label: 'Encrypt',
              ),
              NavigationDestination(
                icon: Icon(Icons.lock_open_rounded),
                selectedIcon: Icon(Icons.lock_open_rounded),
                label: 'Decrypt',
              ),
              NavigationDestination(
                icon: Icon(Icons.info_outline_rounded),
                selectedIcon: Icon(Icons.info_rounded),
                label: 'About',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showQuickKeyDialog(BuildContext context) async {
    final key = KeyUtils.generateHumanKey(groups: 4, groupLen: 4);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Generated Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                key,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text(
                'Share the encrypted file and key via separate channels.',
                style: TextStyle(color: BumbleColors.subtleText),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: key));
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Key copied to clipboard.')),
                  );
                }
              },
              child: const Text('Copy & Close'),
            ),
          ],
        );
      },
    );
  }
}

///
/// Core crypto service:
/// - PBKDF2-HMAC-SHA256 derives 32-byte key from user passphrase + random salt
/// - AES-256-GCM encrypts bytes (confidentiality + integrity)
///
class E2ECryptoService {
  static const int saltLength = 16;
  static const int defaultPbkdf2Iterations = 100000;

  final Cipher _cipher = AesGcm.with256bits();
  static final Random _rng = Random.secure();

  Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (int i = 0; i < length; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  Future<SecretKey> _deriveKey({
    required String passphrase,
    required Uint8List salt,
    required int iterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );

    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  Future<EncryptedPayload> encryptBytes({
    required Uint8List data,
    required String passphrase,
    String? originalFileName,
    int iterations = defaultPbkdf2Iterations,
  }) async {
    final salt = randomBytes(saltLength);
    final key = await _deriveKey(
      passphrase: passphrase,
      salt: salt,
      iterations: iterations,
    );

    final nonce = randomBytes(12); // AES-GCM standard nonce length
    final box = await _cipher.encrypt(
      data,
      secretKey: key,
      nonce: nonce,
    );

    return EncryptedPayload(
      v: 1,
      saltB64: base64Encode(salt),
      nonceB64: base64Encode(box.nonce),
      cipherTextB64: base64Encode(box.cipherText),
      macB64: base64Encode(box.mac.bytes),
      fileName: originalFileName,
      createdAtIso: DateTime.now().toIso8601String(),
      kdf: 'PBKDF2-HMAC-SHA256',
      kdfIterations: iterations,
      cipher: 'AES-256-GCM',
    );
  }

  Future<Uint8List> decryptPayload({
    required EncryptedPayload payload,
    required String passphrase,
  }) async {
    final salt = base64Decode(payload.saltB64);
    final nonce = base64Decode(payload.nonceB64);
    final cipherText = base64Decode(payload.cipherTextB64);
    final macBytes = base64Decode(payload.macB64);

    final key = await _deriveKey(
      passphrase: passphrase,
      salt: Uint8List.fromList(salt),
      iterations: payload.kdfIterations,
    );

    final box = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    try {
      final clear = await _cipher.decrypt(
        box,
        secretKey: key,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Wrong key or corrupted file (authentication check failed).',
      );
    }
  }
}

class EncryptedPayload {
  final int v;
  final String saltB64;
  final String nonceB64;
  final String cipherTextB64;
  final String macB64;

  final String? fileName;
  final String createdAtIso;

  final String cipher;
  final String kdf;
  final int kdfIterations;

  EncryptedPayload({
    required this.v,
    required this.saltB64,
    required this.nonceB64,
    required this.cipherTextB64,
    required this.macB64,
    required this.createdAtIso,
    required this.cipher,
    required this.kdf,
    required this.kdfIterations,
    this.fileName,
  });

  Map<String, dynamic> toJson() => {
    'v': v,
    'salt': saltB64,
    'nonce': nonceB64,
    'ct': cipherTextB64,
    'mac': macB64,
    'fileName': fileName,
    'createdAt': createdAtIso,
    'cipher': cipher,
    'kdf': kdf,
    'kdfIterations': kdfIterations,
  };

  static EncryptedPayload fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) {
      throw const FormatException('Unsupported payload version.');
    }

    final iters = (json['kdfIterations'] is int)
        ? (json['kdfIterations'] as int)
        : E2ECryptoService.defaultPbkdf2Iterations;

    return EncryptedPayload(
      v: 1,
      saltB64: json['salt'] as String,
      nonceB64: json['nonce'] as String,
      cipherTextB64: json['ct'] as String,
      macB64: json['mac'] as String,
      fileName: json['fileName'] as String?,
      createdAtIso:
      (json['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
      cipher: (json['cipher'] as String?) ?? 'AES-256-GCM',
      kdf: (json['kdf'] as String?) ?? 'PBKDF2-HMAC-SHA256',
      kdfIterations: iters,
    );
  }
}

class KeyUtils {
  static final Random _rng = Random.secure();
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // avoid ambiguities

  static String generateHumanKey({int groups = 4, int groupLen = 4}) {
    final parts = <String>[];
    for (int g = 0; g < groups; g++) {
      final sb = StringBuffer();
      for (int i = 0; i < groupLen; i++) {
        sb.write(_alphabet[_rng.nextInt(_alphabet.length)]);
      }
      parts.add(sb.toString());
    }
    return parts.join('-');
  }
}

class WebFileUtils {
  static Future<void> downloadBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final safeName = _sanitizeFileName(fileName);

    await FileExporter.exportBytes(
      filename: safeName,        // <-- must be `filename`
      bytes: bytes.toList(),     // <-- exporter expects List<int>
      mimeType: mimeType,
    );
  }

  static String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_');
    return cleaned.isEmpty ? 'download.bin' : cleaned;
  }
}


///
/// Shared UI building blocks
///
class BumbleCard extends StatelessWidget {
  final Widget child;
  const BumbleCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      color: BumbleColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x12000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class PrimaryCta extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final bool fullWidth;

  const PrimaryCta({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final btn = FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: BumbleColors.yellow,
        foregroundColor: BumbleColors.black,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      icon: icon,
      label: Text(label),
    );

    if (!fullWidth) return btn;

    return SizedBox(width: double.infinity, child: btn);
  }
}

class SecondaryCta extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;

  const SecondaryCta({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: BumbleColors.black,
        side: const BorderSide(color: BumbleColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      icon: icon,
      label: Text(label),
    );
  }
}

///
/// Scrollable page scaffold with keyboard-aware bottom padding (prevents CTA overlap).
///
class ScrollablePage extends StatelessWidget {
  final List<Widget> children;
  const ScrollablePage({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 24 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

///
/// Responsive 1-col (mobile) / 2-col (desktop) layout.
///
class ResponsiveTwoPanel extends StatelessWidget {
  final Widget left;
  final Widget right;
  const ResponsiveTwoPanel({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: 12),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class StepHeader extends StatelessWidget {
  final String title;
  final bool complete;
  final String? subtitle;

  const StepHeader({
    super.key,
    required this.title,
    required this.complete,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: const TextStyle(color: BumbleColors.subtleText)),
              ],
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: complete
              ? Container(
            key: const ValueKey('done'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x1200A000),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x2200A000)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF0A7A2A)),
                SizedBox(width: 6),
                Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          )
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),
      ],
    );
  }
}

class TrustLine extends StatelessWidget {
  final String text;
  const TrustLine(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.lock_outline_rounded, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: BumbleColors.subtleText),
          ),
        ),
      ],
    );
  }
}

///
/// ENCRYPT VIEW
///
class EncryptView extends StatefulWidget {
  const EncryptView({super.key});

  @override
  State<EncryptView> createState() => _EncryptViewState();
}

class _EncryptViewState extends State<EncryptView> {
  final _crypto = E2ECryptoService();
  final _keyCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  PlatformFile? _picked;
  bool _busy = false;
  bool _keyVisible = false;

  String? _status;
  String? _busyPhase; // "Deriving key…", "Encrypting…"

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  bool get _hasFile => _picked != null && (_picked!.bytes != null);
  bool get _hasKey => _keyCtrl.text.trim().isNotEmpty;
  bool get _canEncrypt => _hasFile && _hasKey && !_busy;

  String get _ctaLabel {
    if (_busy) return _busyPhase ?? 'Encrypting…';
    if (!_hasFile) return 'Select a file';
    if (!_hasKey) return 'Enter key to continue';
    return 'Encrypt & Download';
  }

  String? get _ctaHelper {
    if (_busy) return 'Please keep this tab open until the download starts.';
    if (!_hasFile) return 'Select a file to enable encryption.';
    if (!_hasKey) return 'Enter a key to enable encryption.';
    return 'Runs locally in your browser. Nothing is uploaded.';
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    setState(() {
      _picked = res.files.first;
      _status = null;
    });
  }

  void _removeFile() {
    setState(() {
      _picked = null;
      _status = null;
    });
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (data?.text ?? '').trim();
    if (t.isEmpty) return;
    _keyCtrl.text = t;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key pasted.')),
      );
      setState(() {}); // update CTA
    }
  }

  void _clearKey() {
    _keyCtrl.clear();
    setState(() {});
  }

  Future<void> _generateKeyIntoField() async {
    final key = KeyUtils.generateHumanKey(groups: 4, groupLen: 4);
    _keyCtrl.text = key;
    await Clipboard.setData(ClipboardData(text: key));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generated key set and copied to clipboard.')),
      );
      setState(() {}); // update CTA
    }
  }

  Future<void> _encrypt() async {
    final picked = _picked;
    if (picked == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _status = 'Could not read file bytes.');
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
      _busyPhase = 'Deriving key…';
    });

    try {
      final data = (bytes is Uint8List) ? bytes : Uint8List.fromList(bytes);

      // Phase hint (PBKDF2)
      final payload = await _crypto.encryptBytes(
        data: data,
        passphrase: _keyCtrl.text.trim(),
        originalFileName: picked.name,
      );

      setState(() => _busyPhase = 'Preparing download…');

      final jsonBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(payload.toJson())),
      );
      final outName = '${picked.name}.e2e.json';

      await WebFileUtils.downloadBytes(
        bytes: jsonBytes,
        fileName: outName,
        mimeType: 'application/json',
      );

      if (mounted) {
        setState(() => _status = 'Encrypted payload downloaded: $outName');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download started: $outName')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Encryption failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyPhase = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        final fileStepDone = _hasFile;
        final keyStepDone = _hasKey;

        final ctaIcon = _busy
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Icon(Icons.lock_rounded);

        final stickyCta = isNarrow
            ? _StickyBottomCta(
          enabled: _canEncrypt,
          label: _ctaLabel,
          icon: ctaIcon,
          helper: _ctaHelper,
          onPressed: _canEncrypt ? _encrypt : null,
        )
            : null;

        return Stack(
          children: [
            ScrollablePage(
              children: [
                const SizedBox(height: 4),
                Text('Encrypt a file',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text(
                  'Your file is encrypted locally in your browser. Share the encrypted file and the key via separate channels.',
                  style: TextStyle(color: BumbleColors.subtleText),
                ),
                const SizedBox(height: 14),
                ResponsiveTwoPanel(
                  left: BumbleCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StepHeader(
                          title: '1) Select file',
                          complete: fileStepDone,
                          subtitle: _picked == null
                              ? 'Choose a file to encrypt'
                              : 'Ready to encrypt',
                        ),
                        const SizedBox(height: 12),
                        SecondaryCta(
                          onPressed: _busy ? null : _pickFile,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: _picked == null ? 'Choose file' : 'Change file',
                        ),
                        const SizedBox(height: 10),
                        if (_picked != null)
                          _FilePill(
                            name: _picked!.name,
                            sizeBytes: _picked!.size,
                            onRemove: _busy ? null : _removeFile,
                          ),
                      ],
                    ),
                  ),
                  right: BumbleCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StepHeader(
                            title: '2) Enter key / PIN',
                            complete: keyStepDone,
                            subtitle: 'Recommended: 16+ characters',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _keyCtrl,
                            enabled: !_busy,
                            obscureText: !_keyVisible,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Key (required)',
                              hintText: 'Example: 7K2D-Q9PZ-3M8A-HJ4R',
                              helperText:
                              'Tip: generate a key and share it separately from the file.',
                              suffixIcon: _KeyFieldActions(
                                busy: _busy,
                                visible: _keyVisible,
                                hasText: _keyCtrl.text.trim().isNotEmpty,
                                onToggleVisible: () =>
                                    setState(() => _keyVisible = !_keyVisible),
                                onGenerate: _generateKeyIntoField,
                                onPaste: _pasteKey,
                                onClear: _clearKey,
                              ),
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'Key is required.';
                              if (t.length < 8) return 'Use a longer key.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          if (!isNarrow) ...[
                            PrimaryCta(
                              onPressed: _canEncrypt ? _encrypt : null,
                              icon: ctaIcon,
                              label: _ctaLabel,
                              fullWidth: true,
                            ),
                            const SizedBox(height: 8),
                            if (_ctaHelper != null)
                              Text(
                                _ctaHelper!,
                                style: const TextStyle(
                                  color: BumbleColors.subtleText,
                                ),
                              ),
                          ],
                          const SizedBox(height: 10),
                          if (_status != null) _StatusText(_status!),
                          const SizedBox(height: 10),
                          const TrustLine(
                            'Runs locally in your browser. Nothing is uploaded.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _SecurityNoteExpandable(),
                const SizedBox(height: 90), // breathing room above sticky CTA
              ],
            ),
            if (stickyCta != null) Align(alignment: Alignment.bottomCenter, child: stickyCta),
          ],
        );
      },
    );
  }
}

///
/// DECRYPT VIEW
///
class DecryptView extends StatefulWidget {
  const DecryptView({super.key});

  @override
  State<DecryptView> createState() => _DecryptViewState();
}

class _DecryptViewState extends State<DecryptView> {
  final _crypto = E2ECryptoService();
  final _keyCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  PlatformFile? _picked;
  bool _busy = false;
  bool _keyVisible = false;

  String? _status;
  String? _busyPhase;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  bool get _hasPayload => _picked != null && (_picked!.bytes != null);
  bool get _hasKey => _keyCtrl.text.trim().isNotEmpty;
  bool get _canDecrypt => _hasPayload && _hasKey && !_busy;

  String get _ctaLabel {
    if (_busy) return _busyPhase ?? 'Decrypting…';
    if (!_hasPayload) return 'Select payload';
    if (!_hasKey) return 'Enter key to continue';
    return 'Decrypt & Download';
  }

  String? get _ctaHelper {
    if (_busy) return 'Please keep this tab open until the download starts.';
    if (!_hasPayload) return 'Select the encrypted .json payload to enable decryption.';
    if (!_hasKey) return 'Enter the key used for encryption.';
    return 'Runs locally in your browser. Nothing is uploaded.';
  }

  Future<void> _pickEncrypted() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      allowedExtensions: const ['json'],
      type: FileType.custom,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() {
      _picked = res.files.first;
      _status = null;
    });
  }

  void _removePayload() {
    setState(() {
      _picked = null;
      _status = null;
    });
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (data?.text ?? '').trim();
    if (t.isEmpty) return;
    _keyCtrl.text = t;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key pasted.')),
      );
      setState(() {});
    }
  }

  void _clearKey() {
    _keyCtrl.clear();
    setState(() {});
  }

  Future<void> _decrypt() async {
    final picked = _picked;
    if (picked == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _status = 'Could not read file bytes.');
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
      _busyPhase = 'Parsing payload…';
    });

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid encrypted payload JSON.');
      }

      final payload = EncryptedPayload.fromJson(decoded.cast<String, dynamic>());

      setState(() => _busyPhase = 'Deriving key…');

      final clear = await _crypto.decryptPayload(
        payload: payload,
        passphrase: _keyCtrl.text.trim(),
      );

      setState(() => _busyPhase = 'Preparing download…');

      final outName = payload.fileName ?? 'decrypted_file';

      await WebFileUtils.downloadBytes(
        bytes: clear,
        fileName: outName,
        mimeType: 'application/octet-stream',
      );

      if (mounted) {
        setState(() => _status = 'Decrypted file downloaded: $outName');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download started: $outName')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Decryption failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyPhase = null;
        });
      }
    }
  }

  Future<void> _shareEncryptedFile() async {
    final picked = _picked;
    if (picked == null || picked.bytes == null) return;

    try {
      final xFile = XFile.fromData(
        picked.bytes!,
        name: picked.name,
        mimeType: 'application/json',
      );
      await Share.shareXFiles([xFile], text: 'Encrypted file payload');
    } catch (e) {
      if (mounted) setState(() => _status = 'Share not supported here: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        final payloadStepDone = _hasPayload;
        final keyStepDone = _hasKey;

        final ctaIcon = _busy
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Icon(Icons.lock_open_rounded);

        final stickyCta = isNarrow
            ? _StickyBottomCta(
          enabled: _canDecrypt,
          label: _ctaLabel,
          icon: ctaIcon,
          helper: _ctaHelper,
          onPressed: _canDecrypt ? _decrypt : null,
        )
            : null;

        return Stack(
          children: [
            ScrollablePage(
              children: [
                const SizedBox(height: 4),
                Text('Decrypt a file',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text(
                  'Select the encrypted .json payload and enter the key used for encryption.',
                  style: TextStyle(color: BumbleColors.subtleText),
                ),
                const SizedBox(height: 14),
                ResponsiveTwoPanel(
                  left: BumbleCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StepHeader(
                          title: '1) Select encrypted payload',
                          complete: payloadStepDone,
                          subtitle: 'Choose the .e2e.json file',
                        ),
                        const SizedBox(height: 12),
                        SecondaryCta(
                          onPressed: _busy ? null : _pickEncrypted,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: _picked == null
                              ? 'Choose .json payload'
                              : 'Change payload',
                        ),
                        const SizedBox(height: 10),
                        if (_picked != null)
                          _FilePill(
                            name: _picked!.name,
                            sizeBytes: _picked!.size,
                            onRemove: _busy ? null : _removePayload,
                          ),
                        const SizedBox(height: 10),
                        if (_picked != null)
                          SecondaryCta(
                            onPressed: _busy ? null : _shareEncryptedFile,
                            icon: const Icon(Icons.share_rounded),
                            label: 'Share payload (optional)',
                          ),
                      ],
                    ),
                  ),
                  right: BumbleCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StepHeader(
                            title: '2) Enter key / PIN',
                            complete: keyStepDone,
                            subtitle: 'Must match the encryption key',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _keyCtrl,
                            enabled: !_busy,
                            obscureText: !_keyVisible,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Key (required)',
                              suffixIcon: _KeyFieldActions(
                                busy: _busy,
                                visible: _keyVisible,
                                hasText: _keyCtrl.text.trim().isNotEmpty,
                                onToggleVisible: () =>
                                    setState(() => _keyVisible = !_keyVisible),
                                onGenerate: null, // do not generate on decrypt by default
                                onPaste: _pasteKey,
                                onClear: _clearKey,
                              ),
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'Key is required.';
                              if (t.length < 8) return 'Use a longer key.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          if (!isNarrow) ...[
                            PrimaryCta(
                              onPressed: _canDecrypt ? _decrypt : null,
                              icon: ctaIcon,
                              label: _ctaLabel,
                              fullWidth: true,
                            ),
                            const SizedBox(height: 8),
                            if (_ctaHelper != null)
                              Text(
                                _ctaHelper!,
                                style: const TextStyle(
                                  color: BumbleColors.subtleText,
                                ),
                              ),
                          ],
                          const SizedBox(height: 10),
                          if (_status != null) _StatusText(_status!),
                          const SizedBox(height: 10),
                          const TrustLine(
                            'Runs locally in your browser. Nothing is uploaded.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _SecurityNoteExpandable(),
                const SizedBox(height: 90),
              ],
            ),
            if (stickyCta != null) Align(alignment: Alignment.bottomCenter, child: stickyCta),
          ],
        );
      },
    );
  }
}

///
/// Key field action buttons: show/hide, paste, clear, generate.
///
class _KeyFieldActions extends StatelessWidget {
  final bool busy;
  final bool visible;
  final bool hasText;

  final VoidCallback onToggleVisible;
  final Future<void> Function()? onGenerate;
  final Future<void> Function() onPaste;
  final VoidCallback onClear;

  const _KeyFieldActions({
    required this.busy,
    required this.visible,
    required this.hasText,
    required this.onToggleVisible,
    required this.onPaste,
    required this.onClear,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: visible ? 'Hide key' : 'Show key',
          onPressed: busy ? null : onToggleVisible,
          icon: Icon(visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
        ),
        IconButton(
          tooltip: 'Paste',
          onPressed: busy ? null : () => onPaste(),
          icon: const Icon(Icons.content_paste_rounded),
        ),
        if (hasText)
          IconButton(
            tooltip: 'Clear',
            onPressed: busy ? null : onClear,
            icon: const Icon(Icons.clear_rounded),
          ),
        if (onGenerate != null)
          IconButton(
            tooltip: 'Generate secure key',
            onPressed: busy ? null : () => onGenerate!(),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
      ],
    );
  }
}

///
/// Sticky CTA for mobile: thumb-friendly, always visible.
///
class _StickyBottomCta extends StatelessWidget {
  final bool enabled;
  final String label;
  final Widget icon;
  final String? helper;
  final VoidCallback? onPressed;

  const _StickyBottomCta({
    required this.enabled,
    required this.label,
    required this.icon,
    required this.helper,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Material(
      color: BumbleColors.softBg.withOpacity(0.92),
      child: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + (bottom > 0 ? 0 : 6)),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0x14000000)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryCta(
                onPressed: enabled ? onPressed : null,
                icon: icon,
                label: label,
                fullWidth: true,
              ),
              if (helper != null) ...[
                const SizedBox(height: 6),
                Text(
                  helper!,
                  style: const TextStyle(color: BumbleColors.subtleText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilePill extends StatelessWidget {
  final String name;
  final int sizeBytes;
  final VoidCallback? onRemove;

  const _FilePill({
    required this.name,
    required this.sizeBytes,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final kb = sizeBytes / 1024.0;
    final pretty = kb < 1024
        ? '${kb.toStringAsFixed(1)} KB'
        : '${(kb / 1024).toStringAsFixed(2)} MB';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x0A000000),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_rounded, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Text(pretty, style: const TextStyle(color: BumbleColors.subtleText)),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  final String status;
  const _StatusText(this.status);

  @override
  Widget build(BuildContext context) {
    final isSuccess =
        status.startsWith('Encrypted') || status.startsWith('Decrypted');
    return Text(
      status,
      style: TextStyle(
        color: isSuccess ? Colors.green[800] : Colors.red[800],
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

///
/// ABOUT VIEW
///
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScrollablePage(
      children: [
        SizedBox(height: 4),
        Text(
          'About',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 12),
        BumbleCard(child: _AboutContent()),
        SizedBox(height: 12),
        BumbleCard(child: _DisclaimerAndPractices()),
      ],
    );
  }
}

class _AboutContent extends StatelessWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What this does',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text(
          'This web app encrypts and decrypts files locally in your browser using AES-256-GCM. '
              'The encryption key is derived from your key/PIN using PBKDF2 (100k iterations) and a random salt.',
          style: TextStyle(color: BumbleColors.subtleText),
        ),
        SizedBox(height: 14),
        Text('How to use (E2E workflow)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text(
          '1) Encrypt a file and download the .e2e.json payload.\n'
              '2) Send the encrypted payload to the recipient.\n'
              '3) Send the key via a separate channel (never in the same message thread).\n'
              '4) Recipient decrypts locally with the key.',
          style: TextStyle(color: BumbleColors.subtleText, height: 1.35),
        ),
      ],
    );
  }
}

class _DisclaimerAndPractices extends StatelessWidget {
  const _DisclaimerAndPractices();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Disclaimer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text(
          'This tool is provided as-is for educational and utility purposes. It does not constitute legal, compliance, '
              'or security advice. You are responsible for validating suitability for your use case, threat model, and '
              'regulatory obligations.',
          style: TextStyle(color: BumbleColors.subtleText, height: 1.35),
        ),
        SizedBox(height: 14),
        Text('Good practice notes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text(
          '• Use a long, unique key (prefer 16+ characters or multiple groups).\n'
              '• Never reuse keys across unrelated files or recipients.\n'
              '• Send the encrypted payload and the key via separate channels.\n',
          style: TextStyle(color: BumbleColors.subtleText, height: 1.35),
        ),
      ],
    );
  }
}

///
/// Collapsible security note (reduces visual weight, improves hierarchy).
///
class _SecurityNoteExpandable extends StatelessWidget {
  const _SecurityNoteExpandable();

  @override
  Widget build(BuildContext context) {
    return BumbleCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          initiallyExpanded: false,
          leading: const Icon(Icons.shield_rounded),
          title: const Text(
            'Security note',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: const Text(
            'Read before sharing keys or sensitive files',
            style: TextStyle(color: BumbleColors.subtleText),
          ),
          children: const [
            SizedBox(height: 8),
            _SecurityNoteBody(),
          ],
        ),
      ),
    );
  }
}

class _SecurityNoteBody extends StatelessWidget {
  const _SecurityNoteBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• If you lose the key, the encrypted data cannot be recovered.\n'
              '• Share the encrypted file and the key via separate channels.\n'
              '• Use a long, unique key (the generator helps).\n'
              '• Verify the recipient and channel before sharing secrets.\n'
              '• This is client-side encryption; you are responsible for key management.',
          style: TextStyle(color: BumbleColors.subtleText, height: 1.35),
        ),
      ],
    );
  }
}
