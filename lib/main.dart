import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HyperLinkApp());
}

class HyperLinkApp extends StatelessWidget {
  const HyperLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HyperLink Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121C29),
        primaryColor: const Color(0xFF5CEBFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5CEBFF),
          secondary: Color(0xFFFF9800),
          surface: Color(0xFF1F2833),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F2833),
          foregroundColor: Color(0xFF5CEBFF),
          elevation: 2,
          centerTitle: true,
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: MainDashboard(),
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;

  // تنظیمات سرور و احراز هویت
  String _baseUrl = "https://testtok-production1.up.railway.app";
  String _subscriptionKey = "";
  String _adminKey = "";

  // اطلاعات اشتراک فعال
  Map<String, dynamic>? _subInfo;
  bool _loadingSub = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _baseUrl = prefs.getString('base_url') ?? "https://testtok-production1.up.railway.app";
      _subscriptionKey = prefs.getString('subscription_key') ?? "";
      _adminKey = prefs.getString('admin_key') ?? "";
    });
    if (_subscriptionKey.isNotEmpty) {
      _fetchSubscriptionStatus();
    }
  }

  Future<void> _saveCredentials(String url, String subKey, String admKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', url.trim().replaceAll(RegExp(r'/$'), ''));
    await prefs.setString('subscription_key', subKey.trim());
    await prefs.setString('admin_key', admKey.trim());
    setState(() {
      _baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
      _subscriptionKey = subKey.trim();
      _adminKey = admKey.trim();
    });
    if (_subscriptionKey.isNotEmpty) {
      await _fetchSubscriptionStatus();
    }
  }

  Future<void> _fetchSubscriptionStatus() async {
    if (_subscriptionKey.isEmpty) return;
    setState(() => _loadingSub = true);
    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/api/subscription/status?sub_key=$_subscriptionKey"),
      );
      if (res.statusCode == 200) {
        setState(() => _subInfo = jsonDecode(utf8.decode(res.bodyBytes)));
      } else {
        setState(() => _subInfo = null);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSub = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ExtractorTab(
        baseUrl: _baseUrl,
        subscriptionKey: _subscriptionKey,
        subInfo: _subInfo,
        onLicenseCreated: _fetchSubscriptionStatus,
      ),
      LicenseListTab(
        baseUrl: _baseUrl,
        subscriptionKey: _subscriptionKey,
        adminKey: _adminKey,
      ),
      AdminSubscriptionTab(
        baseUrl: _baseUrl,
        adminKey: _adminKey,
      ),
      SettingsTab(
        baseUrl: _baseUrl,
        subscriptionKey: _subscriptionKey,
        adminKey: _adminKey,
        subInfo: _subInfo,
        loadingSub: _loadingSub,
        onSave: _saveCredentials,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "HyperLink Extractor ⚡",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (_subInfo != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Chip(
                backgroundColor: const Color(0xFF002B31),
                side: const BorderSide(color: Color(0xFF5CEBFF)),
                label: Text(
                  "باقی‌مانده: ${_subInfo!['remaining']} / ${_subInfo!['max_licenses']}",
                  style: const TextStyle(color: Color(0xFF5CEBFF), fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1F2833),
        selectedItemColor: const Color(0xFF5CEBFF),
        unselectedItemColor: const Color(0xFFAAB9C8),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt),
            label: "ساخت لایسنس",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.vpn_key),
            label: "لایسنس‌ها",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.SupervisorAccount),
            label: "پنل اشتراک (ادمین)",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "تنظیمات و اشتراک",
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// تب ۱: مرورگر داخلی تپسی + استخراج خودکار نشست و ساخت لایسنس
// ============================================================================
class ExtractorTab extends StatefulWidget {
  final String baseUrl;
  final String subscriptionKey;
  final Map<String, dynamic>? subInfo;
  final VoidCallback onLicenseCreated;

  const ExtractorTab({
    super.key,
    required this.baseUrl,
    required this.subscriptionKey,
    required this.subInfo,
    required this.onLicenseCreated,
  });

  @override
  State<ExtractorTab> createState() => _ExtractorTabState();
}

class _ExtractorTabState extends State<ExtractorTab> {
  late final WebViewController _webController;
  late final WebViewCookieManager _cookieManager = WebViewCookieManager();

  String _statusMessage = "وضعیت: وارد حساب تپسی شوید و دکمه استخراج را بزنید";
  Color _statusColor = const Color(0xFFAAB9C8);
  String? _lastLicenseKey;
  Map<String, dynamic>? _lastExtractedPayload;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36")
      ..loadRequest(Uri.parse("https://app.tapsi.cab"));
  }

  Future<void> _extractAndCreateLicense() async {
    if (widget.subscriptionKey.isEmpty) {
      setState(() {
        _statusMessage = "❌ ابتدا کد اشتراک خود را در تب «تنظیمات و اشتراک» وارد کنید.";
        _statusColor = const Color(0xFFFFB4AB);
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "⏳ در حال استخراج نشست و بررسی سهمیه اشتراک...";
      _statusColor = const Color(0xFFFFC400);
      _lastLicenseKey = null;
    });

    try {
      // ۱. استخراج LocalStorage و شماره موبایل با جاوااسکریپت از داخل WebView
      final jsResult = await _webController.runJavaScriptReturningResult('''
        (function() {
          var ls = {};
          var phone = "unknown";
          for (var i = 0; i < window.localStorage.length; i++) {
            var k = window.localStorage.key(i);
            var v = window.localStorage.getItem(k);
            ls[k] = v;
            if (v && (v.indexOf("09") !== -1 || v.indexOf("+98") !== -1)) {
              var m = v.match(/(?:\+98|0)?9\d{9}/);
              if (m) phone = m[0];
            }
          }
          return JSON.stringify({
            cookies: document.cookie || "",
            local_storage: JSON.stringify(ls),
            phone_number: phone
          });
        })();
      ''');

      String rawJson = jsResult.toString();
      if (rawJson.startsWith('"') && rawJson.endsWith('"')) {
        rawJson = jsonDecode(rawJson);
      }
      final Map<String, dynamic> extracted = jsonDecode(rawJson);

      if ((extracted['local_storage'] == "{}" || extracted['local_storage'] == "") &&
          (extracted['cookies'] == "")) {
        setState(() {
          _statusMessage = "❌ نشست فعالی یافت نشد! ابتدا در صفحه زیر وارد حساب تپسی شوید.";
          _statusColor = const Color(0xFFFFB4AB);
          _isProcessing = false;
        });
        return;
      }

      final payload = {
        "cookies": extracted['cookies'] ?? "empty",
        "local_storage": extracted['local_storage'] ?? "{}",
        "phone_number": extracted['phone_number'] ?? "unknown",
        "subscription_key": widget.subscriptionKey,
      };

      _lastExtractedPayload = payload;

      // ۲. ارسال به سرور برای صدور لایسنس و کسر از سهمیه اشتراک
      final response = await http.post(
        Uri.parse("${widget.baseUrl}/api/tapsi/create-license"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _lastLicenseKey = data['license_key'];
          _statusMessage = "✅ لایسنس با موفقیت ساخته شد! (${payload['phone_number']})";
          _statusColor = const Color(0xFF00E676);
        });
        widget.onLicenseCreated();
      } else {
        setState(() {
          _statusMessage = "❌ خطا: ${data['detail'] ?? 'خطای نامشخص از سمت سرور'}";
          _statusColor = const Color(0xFFFFB4AB);
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "❌ خطای ارتباطی: $e";
        _statusColor = const Color(0xFFFFB4AB);
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _deepCleanSession() async {
    setState(() {
      _statusMessage = "🧹 در حال پاک‌سازی عمیق کوکی‌ها و حافظه مرورگر...";
      _statusColor = const Color(0xFFFFC400);
    });

    try {
      await _cookieManager.clearCookies();
      await _webController.runJavaScript('''
        window.localStorage.clear();
        window.sessionStorage.clear();
      ''');
      await _webController.clearCache();
      await _webController.clearLocalStorage();
      await _webController.loadRequest(Uri.parse("https://app.tapsi.cab"));

      setState(() {
        _statusMessage = "✅ پاک‌سازی کامل شد! آماده ورود با شماره بعدی.";
        _statusColor = const Color(0xFF00E676);
        _lastLicenseKey = null;
        _lastExtractedPayload = null;
      });
    } catch (e) {
      setState(() {
        _statusMessage = "❌ خطا در پاک‌سازی: $e";
        _statusColor = const Color(0xFFFFB4AB);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // پنل کنترل بالای صفحه
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF1F2833),
          child: Column(
            children: [
              Text(
                _statusMessage,
                style: TextStyle(color: _statusColor, fontSize: 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (_lastLicenseKey != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _lastLicenseKey!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ کد لایسنس کپی شد!")),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF002B31),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF5CEBFF)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.copy, color: Color(0xFF5CEBFF), size: 18),
                        const SizedBox(width: 8),
                        SelectableText(
                          _lastLicenseKey!,
                          style: const TextStyle(
                            color: Color(0xFF5CEBFF),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5CEBFF),
                        foregroundColor: const Color(0xFF002B31),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _isProcessing ? null : _extractAndCreateLicense,
                      icon: const Icon(Icons.bolt),
                      label: const Text(
                        "استخراج و ساخت لایسنس",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF9800),
                        side: const BorderSide(color: Color(0xFFFF9800)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _deepCleanSession,
                      icon: const Icon(Icons.cleaning_services, size: 18),
                      label: const Text("پاک‌سازی"),
                    ),
                  ),
                ],
              ),
              if (_lastExtractedPayload != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: const JsonEncoder.withIndent('  ').convert(_lastExtractedPayload),
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("📋 اطلاعات خام نشست کپی شد")),
                        );
                      },
                      icon: const Icon(Icons.code, size: 16, color: Color(0xFF5CEBFF)),
                      label: const Text(
                        "کپی اطلاعات خام استخراج‌شده",
                        style: TextStyle(color: Color(0xFF5CEBFF), fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // مرورگر داخلی تپسی
        Expanded(
          child: WebViewWidget(controller: _webController),
        ),
      ],
    );
  }
}

// ============================================================================
// تب ۲: مدیریت و مشاهده لایسنس‌های ساخته شده
// ============================================================================
class LicenseListTab extends StatefulWidget {
  final String baseUrl;
  final String subscriptionKey;
  final String adminKey;

  const LicenseListTab({
    super.key,
    required this.baseUrl,
    required this.subscriptionKey,
    required this.adminKey,
  });

  @override
  State<LicenseListTab> createState() => _LicenseListTabState();
}

class _LicenseListTabState extends State<LicenseListTab> {
  List<dynamic> _licenses = [];
  bool _loading = false;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchLicenses();
  }

  Future<void> _fetchLicenses() async {
    if (widget.subscriptionKey.isEmpty && widget.adminKey.isEmpty) return;
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        "${widget.baseUrl}/api/licenses?sub_key=${widget.subscriptionKey}&admin_key=${widget.adminKey}",
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _licenses = data['licenses'] ?? []);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteLicense(String licenseKey) async {
    try {
      final res = await http.delete(
        Uri.parse(
          "${widget.baseUrl}/api/licenses/$licenseKey?sub_key=${widget.subscriptionKey}&admin_key=${widget.adminKey}",
        ),
      );
      if (res.statusCode == 200) {
        _fetchLicenses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("🗑️ لایسنس حذف شد")),
          );
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _licenses.where((item) {
      final q = _searchQuery.toLowerCase();
      final key = (item['license_key'] ?? '').toString().toLowerCase();
      final phone = (item['phone_number'] ?? '').toString().toLowerCase();
      return key.contains(q) || phone.contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "جستجوی شماره موبایل یا کد لایسنس...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFF1F2833),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _fetchLicenses,
                icon: const Icon(Icons.refresh, color: Color(0xFF5CEBFF)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(child: Text("هیچ لایسنسی یافت نشد."))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final lic = filtered[i];
                        return Card(
                          color: const Color(0xFF1F2833),
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          child: ListTile(
                            title: Text(
                              lic['license_key'] ?? '',
                              style: const TextStyle(
                                color: Color(0xFF5CEBFF),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "📱 شماره: ${lic['phone_number'] ?? 'نامشخص'}  |  📅 ${lic['created_at'] ?? ''}",
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.white70),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: lic['license_key'] ?? ''),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("کپی شد!")),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _deleteLicense(lic['license_key']),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ============================================================================
// تب ۳: پنل ادمین (ساخت اشتراک مثلاً ۱۰۰۰ لایسنسی برای فروش به کاربران)
// ============================================================================
class AdminSubscriptionTab extends StatefulWidget {
  final String baseUrl;
  final String adminKey;

  const AdminSubscriptionTab({
    super.key,
    required this.baseUrl,
    required this.adminKey,
  });

  @override
  State<AdminSubscriptionTab> createState() => _AdminSubscriptionTabState();
}

class _AdminSubscriptionTabState extends State<AdminSubscriptionTab> {
  final _ownerController = TextEditingController();
  final _quotaController = TextEditingController(text: "1000");
  List<dynamic> _subscriptions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.adminKey.isNotEmpty) {
      _fetchSubscriptions();
    }
  }

  Future<void> _fetchSubscriptions() async {
    if (widget.adminKey.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse("${widget.baseUrl}/api/admin/subscriptions?admin_key=${widget.adminKey}"),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _subscriptions = data['subscriptions'] ?? []);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createSubscription() async {
    if (widget.adminKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ ابتدا کلید ادمین را در تب تنظیمات وارد کنید.")),
      );
      return;
    }

    final maxLicenses = int.tryParse(_quotaController.text.trim()) ?? 1000;
    final ownerName = _ownerController.text.trim().isEmpty
        ? "کاربر ویژه"
        : _ownerController.text.trim();

    try {
      final res = await http.post(
        Uri.parse("${widget.baseUrl}/api/admin/subscriptions"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "admin_key": widget.adminKey,
          "owner_name": ownerName,
          "max_licenses": maxLicenses,
        }),
      );

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && data['success'] == true) {
        _ownerController.clear();
        _fetchSubscriptions();
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1F2833),
              title: const Text("✅ اشتراک جدید ساخته شد"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("نام خریدار: $ownerName"),
                  Text("ظرفیت ساخت: $maxLicenses لایسنس"),
                  const SizedBox(height: 12),
                  SelectableText(
                    data['subscription_key'],
                    style: const TextStyle(
                      color: Color(0xFF5CEBFF),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: data['subscription_key']));
                    Navigator.pop(context);
                  },
                  child: const Text("کپی کد اشتراک و بستن"),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ خطا: ${data['detail'] ?? 'عدم دسترسی'}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ خطای ارتباط با سرور: $e")),
        );
      }
    }
  }

  Future<void> _toggleOrDeleteSub(String subKey, bool delete) async {
    try {
      if (delete) {
        await http.delete(
          Uri.parse("${widget.baseUrl}/api/admin/subscriptions/$subKey?admin_key=${widget.adminKey}"),
        );
      } else {
        await http.patch(
          Uri.parse("${widget.baseUrl}/api/admin/subscriptions/$subKey/toggle?admin_key=${widget.adminKey}"),
        );
      }
      _fetchSubscriptions();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2833),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "➕ ساخت اشتراک فروش (تولید کد اشتراک برای مشتری)",
                  style: TextStyle(
                    color: Color(0xFF5CEBFF),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ownerController,
                  decoration: const InputDecoration(
                    labelText: "نام مشتری یا توضیحات (مثلاً: نماینده ۱)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _quotaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "ظرفیت ساخت لایسنس (مثلاً: 1000)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5CEBFF),
                      foregroundColor: const Color(0xFF002B31),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _createSubscription,
                    icon: const Icon(Icons.add_card),
                    label: const Text(
                      "تولید کد اشتراک جدید",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "📋 لیست اشتراک‌های صادرشده:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              IconButton(
                onPressed: _fetchSubscriptions,
                icon: const Icon(Icons.refresh, color: Color(0xFF5CEBFF)),
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _subscriptions.isEmpty
                    ? const Center(
                        child: Text("هیچ اشتراکی یافت نشد (کلید ادمین را بررسی کنید)."),
                      )
                    : ListView.builder(
                        itemCount: _subscriptions.length,
                        itemBuilder: (context, i) {
                          final sub = _subscriptions[i];
                          final used = sub['used_licenses'] ?? 0;
                          final max = sub['max_licenses'] ?? 0;
                          final active = sub['is_active'] == true;
                          return Card(
                            color: const Color(0xFF1F2833),
                            child: ListTile(
                              title: Text(
                                "${sub['owner_name']} (${sub['subscription_key']})",
                                style: TextStyle(
                                  color: active ? const Color(0xFF5CEBFF) : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                "مصرف شده: $used از $max لایسنس | وضعیت: ${active ? 'فعال ✅' : 'مسدود ⛔'}",
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.copy),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: sub['subscription_key']),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("کد اشتراک کپی شد")),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      active ? Icons.block : Icons.check_circle,
                                      color: Colors.orangeAccent,
                                    ),
                                    onPressed: () =>
                                        _toggleOrDeleteSub(sub['subscription_key'], false),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () =>
                                        _toggleOrDeleteSub(sub['subscription_key'], true),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// تب ۴: تنظیمات اتصال و وارد کردن کد اشتراک کاربر
// ============================================================================
class SettingsTab extends StatefulWidget {
  final String baseUrl;
  final String subscriptionKey;
  final String adminKey;
  final Map<String, dynamic>? subInfo;
  final bool loadingSub;
  final Future<void> Function(String, String, String) onSave;

  const SettingsTab({
    super.key,
    required this.baseUrl,
    required this.subscriptionKey,
    required this.adminKey,
    required this.subInfo,
    required this.loadingSub,
    required this.onSave,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _urlCtrl;
  late TextEditingController _subCtrl;
  late TextEditingController _admCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.baseUrl);
    _subCtrl = TextEditingController(text: widget.subscriptionKey);
    _admCtrl = TextEditingController(text: widget.adminKey);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subInfo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF002B31),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF5CEBFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "👤 اشتراک فعال: ${widget.subInfo!['owner_name']}",
                    style: const TextStyle(
                      color: Color(0xFF5CEBFF),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text("کل ظرفیت اشتراک: ${widget.subInfo!['max_licenses']} لایسنس"),
                  Text("تعداد مصرف‌شده: ${widget.subInfo!['used_licenses']} لایسنس"),
                  Text(
                    "ظرفیت باقی‌مانده: ${widget.subInfo!['remaining']} لایسنس",
                    style: const TextStyle(
                      color: Color(0xFF00E676),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          const Text(
            "🔑 کد اشتراک کاربری (مخصوص مشتریان):",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subCtrl,
            decoration: const InputDecoration(
              hintText: "مثلاً: SUB-HYPER-XXXXXX",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.card_membership),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "🛡️ رمز مدیریت ادمین (فقط برای مدیر اصلی جهت ساخت اشتراک):",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _admCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: "در صورت ادمین بودن وارد کنید",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.admin_panel_settings),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "🌐 آدرس سرور (Railway Backend):",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.cloud),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5CEBFF),
                foregroundColor: const Color(0xFF002B31),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                await widget.onSave(_urlCtrl.text, _subCtrl.text, _admCtrl.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ تنظیمات ذخیره و بررسی شد.")),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text(
                "ذخیره و بررسی اشتراک",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
