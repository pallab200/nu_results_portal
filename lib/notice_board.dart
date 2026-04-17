import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'pdf_viewer.dart';
import 'theme_provider.dart';

class Notice {
  Notice({
    required this.title,
    required this.date,
    required this.url,
    required this.isPdf,
  });

  final String title;
  final String date;
  final String url;
  final bool isPdf;
}

/// A simple, responsive notice board that fetches notices from the
/// National University recent notices page and renders a list of
/// titles, dates and links. The widget periodically refreshes.
class NoticeBoard extends StatefulWidget {
  final Uri source;
  final String title;

  const NoticeBoard({super.key, required this.source, this.title = 'Notices'});

  @override
  State<NoticeBoard> createState() => _NoticeBoardState();
}

class _NoticeBoardState extends State<NoticeBoard>
    with TickerProviderStateMixin {
  static final Map<String, List<Notice>> _memoryCache = {};
  static final Map<String, String?> _memoryCacheTimestamps = {};

  // source is provided by the widget via `widget.source`

  final List<Notice> _notices = [];
  bool _loading = false;
  bool _usingCache = false;
  String? _cacheTimestamp;
  String? _error;
  Timer? _timer;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FocusNode _searchFocus = FocusNode();
  AnimationController? _staggerCtrl;

  String get _cacheScopeKey =>
      base64Url.encode(utf8.encode(widget.source.toString()));
  String get _cacheKey => 'notice_cache_v2_$_cacheScopeKey';
  String get _cacheTsKey => 'notice_cache_ts_v2_$_cacheScopeKey';

  @override
  void initState() {
    super.initState();
    _loadInitialNotices();
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _fetchNotices(showLoader: false),
    );
  }

  Future<void> _loadInitialNotices() async {
    await _hydrateCachedNotices();
    if (!mounted) return;
    await _fetchNotices(showLoader: _notices.isEmpty);
  }

  Future<void> _hydrateCachedNotices() async {
    final memoryCached = _memoryCache[_cacheScopeKey];
    if (memoryCached != null && memoryCached.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _notices
          ..clear()
          ..addAll(memoryCached);
        _loading = false;
        _usingCache = true;
        _cacheTimestamp = _memoryCacheTimestamps[_cacheScopeKey];
        _error = null;
      });
      _restartStagger();
      return;
    }

    final cached = await _loadCache();
    if (!mounted || cached.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_cacheTsKey);
    _memoryCache[_cacheScopeKey] = List<Notice>.unmodifiable(cached);
    _memoryCacheTimestamps[_cacheScopeKey] = ts;

    setState(() {
      _notices
        ..clear()
        ..addAll(cached);
      _loading = false;
      _usingCache = true;
      _cacheTimestamp = ts;
      _error = null;
    });
    _restartStagger();
  }

  void _restartStagger() {
    _staggerCtrl?.dispose();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  String _decodeResponseBody(Map<String, String> headers, List<int> bytes) {
    try {
      final contentType =
          (headers['content-type'] ?? headers['Content-Type'] ?? '')
              .toLowerCase();
      final charsetMatch = RegExp(r'charset=([\w\-]+)').firstMatch(contentType);
      final charset = charsetMatch?.group(1)?.toLowerCase() ?? '';

      if (charset.contains('utf')) {
        return utf8.decode(bytes);
      }
      if (charset.contains('iso-8859-1') || charset.contains('latin1')) {
        return latin1.decode(bytes);
      }
      if (charset.contains('windows-1252') || charset.contains('cp1252')) {
        // best-effort: latin1 is similar for many Western encodings
        return latin1.decode(bytes);
      }

      // Default: try UTF-8 then fall back to Latin-1
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return latin1.decode(bytes);
      }
    } catch (_) {
      // Last resort
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return latin1.decode(bytes);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _staggerCtrl?.dispose();
    super.dispose();
  }

  Future<void> _fetchNotices({bool showLoader = true}) async {
    if (mounted) {
      setState(() {
        _loading = showLoader && _notices.isEmpty;
        _error = null;
      });
    }
    // robust fetch: try https normal GET -> streamed GET -> http fallback
    Future<String> attemptFetch(Uri uri) async {
      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36 nu_results_flutter/1.0',
        // ask server not to use compressed transfer to avoid decompression issues
        'Accept-Encoding': 'identity',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Connection': 'close',
      };

      final client = http.Client();
      try {
        // Build candidate URIs to try (original, encoded parens, with/without www, trailing slash)
        final candidates = <Uri>[];
        candidates.add(uri);

        if (uri.path.contains('(') || uri.path.contains(')')) {
          final encPath = uri.path
              .replaceAll('(', '%28')
              .replaceAll(')', '%29');
          candidates.add(uri.replace(path: encPath));
        }

        if (!uri.path.endsWith('/')) {
          candidates.add(uri.replace(path: '${uri.path}/'));
        }

        if (uri.host.startsWith('www.')) {
          candidates.add(uri.replace(host: uri.host.replaceFirst('www.', '')));
        } else {
          candidates.add(uri.replace(host: 'www.${uri.host}'));
        }

        // Deduplicate while preserving order
        final seen = <String>{};
        final unique = <Uri>[];
        for (final c in candidates) {
          if (seen.add(c.toString())) unique.add(c);
        }

        Exception? lastError;

        // Hosts for which we allow a temporary insecure TLS fallback.
        // Restricting this reduces security risk; expand only if necessary.
        final Set<String> insecureAllowlist = {'nu.ac.bd', 'www.nu.ac.bd'};

        for (final c in unique) {
          try {
            final resp = await client
                .get(c, headers: headers)
                .timeout(const Duration(seconds: 60));
            if (resp.statusCode == 200) {
              return _decodeResponseBody(resp.headers, resp.bodyBytes);
            }
            lastError = Exception('HTTP ${resp.statusCode}');
          } catch (e) {
            // If this looks like a TLS/handshake error, try a host-limited insecure fallback.
            final errStr = e.toString();
            final isTlsHandshake =
                (e is io.HandshakeException) ||
                errStr.contains('CERTIFICATE_VERIFY_FAILED') ||
                errStr.contains('HandshakeException');

            if (isTlsHandshake && insecureAllowlist.contains(c.host)) {
              try {
                final insecureHttp = io.HttpClient();
                insecureHttp.badCertificateCallback =
                    (io.X509Certificate cert, String host, int port) =>
                        host == c.host;
                final insecureClient = IOClient(insecureHttp);
                try {
                  final resp = await insecureClient
                      .get(c, headers: headers)
                      .timeout(const Duration(seconds: 60));
                  if (resp.statusCode == 200) {
                    return _decodeResponseBody(resp.headers, resp.bodyBytes);
                  }
                  lastError = Exception('HTTP ${resp.statusCode} (insecure)');
                } catch (ie) {
                  // streamed fallback on insecure client
                  try {
                    final req = http.Request('GET', c);
                    req.headers.addAll(headers);
                    final streamed = await insecureClient
                        .send(req)
                        .timeout(const Duration(seconds: 60));
                    if (streamed.statusCode == 200) {
                      final bytes = await streamed.stream.toBytes();
                      return _decodeResponseBody(streamed.headers, bytes);
                    }
                    lastError = Exception(
                      'HTTP ${streamed.statusCode} (insecure)',
                    );
                  } catch (e2) {
                    lastError = e2 is Exception ? e2 : Exception(e2.toString());
                  }
                } finally {
                  insecureClient.close();
                }
              } catch (outer) {
                lastError = outer is Exception
                    ? outer
                    : Exception(outer.toString());
              }
            } else {
              // try streamed fallback for this candidate
              try {
                final req = http.Request('GET', c);
                req.headers.addAll(headers);
                final streamed = await client
                    .send(req)
                    .timeout(const Duration(seconds: 60));
                if (streamed.statusCode == 200) {
                  final bytes = await streamed.stream.toBytes();
                  return _decodeResponseBody(streamed.headers, bytes);
                }
                lastError = Exception('HTTP ${streamed.statusCode}');
              } catch (streamErr) {
                lastError = streamErr is Exception
                    ? streamErr
                    : Exception(streamErr.toString());
              }
            }
          }
        }

        // final fallback: try http scheme if https didn't succeed
        if (uri.scheme != 'http') {
          final httpFallback = uri.replace(scheme: 'http');
          try {
            final resp = await client
                .get(httpFallback, headers: headers)
                .timeout(const Duration(seconds: 60));
            if (resp.statusCode == 200) {
              return _decodeResponseBody(resp.headers, resp.bodyBytes);
            }
            lastError = Exception('HTTP ${resp.statusCode}');
          } catch (e) {
            try {
              final req = http.Request('GET', httpFallback);
              req.headers.addAll(headers);
              final streamed = await client
                  .send(req)
                  .timeout(const Duration(seconds: 60));
              if (streamed.statusCode == 200) {
                final bytes = await streamed.stream.toBytes();
                return _decodeResponseBody(streamed.headers, bytes);
              }
              lastError = Exception('HTTP ${streamed.statusCode}');
            } catch (e2) {
              lastError = e2 is Exception ? e2 : Exception(e2.toString());
            }
          }
        }

        throw lastError ?? Exception('Failed to fetch $uri');
      } finally {
        client.close();
      }
    }

    try {
      String body;
      try {
        body = await attemptFetch(widget.source);
      } catch (e) {
        // try http fallback if https failed
        final httpFallback = widget.source.replace(scheme: 'http');
        body = await attemptFetch(httpFallback);
      }

      final doc = html_parser.parse(body);
      final parsed = _extractNotices(doc);
      final cacheTimestamp = DateTime.now().toIso8601String();

      if (!mounted) return;

      await _saveCache(parsed, cacheTimestamp);
      _memoryCache[_cacheScopeKey] = List<Notice>.unmodifiable(parsed);
      _memoryCacheTimestamps[_cacheScopeKey] = cacheTimestamp;

      if (!mounted) return;

      setState(() {
        _notices
          ..clear()
          ..addAll(parsed);
        _loading = false;
        _usingCache = false;
        _cacheTimestamp = cacheTimestamp;
      });
      _restartStagger();
    } catch (e) {
      final cached = _notices.isNotEmpty
          ? List<Notice>.of(_notices)
          : await _loadCache();
      if (!mounted) return;
      if (cached.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final ts =
            _memoryCacheTimestamps[_cacheScopeKey] ??
            prefs.getString(_cacheTsKey);
        setState(() {
          _notices
            ..clear()
            ..addAll(cached);
          _loading = false;
          _usingCache = true;
          _cacheTimestamp = ts;
          _error = null;
        });
        _restartStagger();
      } else {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveCache(List<Notice> notices, String cacheTimestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = notices
          .map(
            (n) => {
              'title': n.title,
              'date': n.date,
              'url': n.url,
              'isPdf': n.isPdf,
            },
          )
          .toList();
      await prefs.setString(_cacheKey, jsonEncode(list));
      await prefs.setString(_cacheTsKey, cacheTimestamp);
    } catch (_) {}
  }

  Future<List<Notice>> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return <Notice>[];
      final data = (jsonDecode(raw) as List).cast<Map>();
      return data
          .map(
            (m) => Notice(
              title: (m['title'] ?? '').toString(),
              date: (m['date'] ?? '').toString(),
              url: (m['url'] ?? '').toString(),
              isPdf: (m['isPdf'] ?? false) as bool,
            ),
          )
          .toList();
    } catch (_) {
      return <Notice>[];
    }
  }

  List<Notice> _extractNotices(dom.Document doc) {
    final base = Uri.parse('https://www.nu.ac.bd/');
    final seen = <String>{};
    final List<Notice> results = [];

    final dateRx1 = RegExp(r"\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b");
    final dateRx2 = RegExp(
      r"\b\d{1,2}\s+(?:Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|September|Oct|October|Nov|November|Dec|December)\s+\d{4}\b",
      caseSensitive: false,
    );
    // Match formats like "March 26, 2026" (Month day, year)
    final dateRx3 = RegExp(
      r"\b(?:Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2},\s*\d{4}\b",
      caseSensitive: false,
    );

    // 1) Try table-based extraction (common pattern for notices)
    final tables = doc.querySelectorAll('table');
    for (final table in tables) {
      for (final row in table.querySelectorAll('tr')) {
        final anchor = row.querySelector('a');
        if (anchor == null) {
          continue;
        }
        final rawHref = anchor.attributes['href']?.trim() ?? '';
        if (rawHref.isEmpty ||
            rawHref.startsWith('#') ||
            rawHref.toLowerCase().startsWith('javascript')) {
          continue;
        }

        String url;
        try {
          url = base.resolve(rawHref).toString();
        } catch (_) {
          continue;
        }
        if (seen.contains(url)) continue;

        final title = anchor.text.trim();

        String date = '';
        final cells = row.querySelectorAll('td,th');
        for (final cell in cells) {
          final txt = cell.text.trim();
          final m1 = dateRx1.firstMatch(txt);
          final m2 = dateRx2.firstMatch(txt);
          final m3 = dateRx3.firstMatch(txt);
          if (m3 != null) {
            date = m3.group(0) ?? '';
            break;
          } else if (m2 != null) {
            date = m2.group(0) ?? '';
            break;
          } else if (m1 != null) {
            date = m1.group(0) ?? '';
            break;
          }
        }

        results.add(
          Notice(
            title: title.isEmpty ? url : title,
            date: date,
            url: url,
            isPdf: url.toLowerCase().endsWith('.pdf'),
          ),
        );
        seen.add(url);
      }
      if (results.isNotEmpty) return results;
    }

    // 2) Fallback: scan anchors and use heuristics
    final anchors = doc.querySelectorAll('a');
    for (final anchor in anchors) {
      final rawHref = anchor.attributes['href']?.trim() ?? '';
      if (rawHref.isEmpty ||
          rawHref.startsWith('#') ||
          rawHref.toLowerCase().startsWith('javascript') ||
          rawHref.toLowerCase().startsWith('mailto:')) {
        continue;
      }

      String url;
      try {
        url = base.resolve(rawHref).toString();
      } catch (_) {
        continue;
      }
      if (seen.contains(url)) {
        continue;
      }

      var title = anchor.text.trim();
      if (title.length < 3) {
        title = anchor.attributes['title']?.trim() ?? '';
      }
      if (title.length < 3) {
        final parent = anchor.parent;
        title = (parent?.text ?? '').trim();
        if (title.length > 200) {
          title = title.substring(0, 200).trim();
        }
      }

      // find nearby dates
      final ancestorText =
          '${anchor.parent?.text ?? ''} ${anchor.parent?.parent?.text ?? ''} ${anchor.parent?.parent?.parent?.text ?? ''}';
      String date = '';
      final m1 = dateRx1.firstMatch(ancestorText);
      final m2 = dateRx2.firstMatch(ancestorText);
      final m3 = dateRx3.firstMatch(ancestorText);
      if (m3 != null) {
        date = m3.group(0) ?? '';
      } else if (m2 != null) {
        date = m2.group(0) ?? '';
      } else if (m1 != null) {
        date = m1.group(0) ?? '';
      }

      final lowerTitle = title.toLowerCase();
      final parentLower = (anchor.parent?.text ?? '').toLowerCase();

      // heuristics: prefer links that mention 'notice', point to pdfs, or are list items
      final isNoticeLink =
          lowerTitle.contains('notice') ||
          parentLower.contains('notice') ||
          url.toLowerCase().endsWith('.pdf') ||
          url.toLowerCase().contains('notice') ||
          anchor.parent?.localName == 'li';
      if (isNoticeLink) {
        results.add(
          Notice(
            title: title.isEmpty ? url : title,
            date: date,
            url: url,
            isPdf: url.toLowerCase().endsWith('.pdf'),
          ),
        );
        seen.add(url);
      }
    }

    return results;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _searchQuery.trim().toLowerCase();
    final List<Notice> displayed = query.isEmpty
        ? _notices
        : _notices.where((n) {
            final t = n.title.toLowerCase();
            final d = n.date.toLowerCase();
            final u = n.url.toLowerCase();
            return t.contains(query) || d.contains(query) || u.contains(query);
          }).toList();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: AppColors.subtleBg(isDark)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 52, child: Center(child: _NoticeBannerAd())),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Builder(
                builder: (ctx) {
                  final src = widget.source.toString().toLowerCase();
                  final titleLower = widget.title.toLowerCase();
                  final isSyllabus =
                      src.contains('syllabus') ||
                      titleLower.contains('syllabus') ||
                      titleLower.contains('honour') ||
                      titleLower.contains('honours') ||
                      titleLower.contains('degree') ||
                      titleLower.contains('masters') ||
                      titleLower.contains('preliminary') ||
                      titleLower.contains('post graduate') ||
                      titleLower.contains('post-graduate') ||
                      titleLower.contains('pgd') ||
                      titleLower.contains('professional') ||
                      src.contains('honours') ||
                      src.contains('degree-pass') ||
                      src.contains('preliminary') ||
                      src.contains('post-graduate') ||
                      src.contains('postgraduate') ||
                      src.contains('pgd') ||
                      src.contains('profession');
                  final isNotice =
                      titleLower.contains('notice') ||
                      titleLower.contains('notices') ||
                      titleLower.contains('admission') ||
                      titleLower.contains('exam') ||
                      titleLower.contains('examination') ||
                      titleLower.contains('recent') ||
                      src.contains('notice') ||
                      src.contains('recent-news') ||
                      src.contains('admission') ||
                      src.contains('exam') ||
                      src.contains('examination');
                  final showSearch = isSyllabus || isNotice;
                  if (!showSearch) return const SizedBox.shrink();

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.searchBg(isDark),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cardShadow(isDark),
                          blurRadius: 6,
                          offset: const Offset(0, 4),
                          spreadRadius: -1,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary(isDark),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search notices...',
                        hintStyle: TextStyle(
                          color: AppColors.textTertiary(isDark),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.textTertiary(isDark),
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                onPressed: () => setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                }),
                                icon: Icon(
                                  Icons.clear_rounded,
                                  size: 20,
                                  color: AppColors.textTertiary(isDark),
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_usingCache)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cacheBg(isDark),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cacheBorder(isDark)),
                  ),
                  child: Text(
                    _cacheTimestamp != null
                        ? 'Showing cached notices (updated ${_formatTs(_cacheTimestamp!)})'
                        : 'Showing cached notices',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.cacheText(isDark),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? _PulseShimmer(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 6,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, __) =>
                            _NoticeShimmerCard(isDark: isDark),
                      ),
                    )
                  : _error != null && _notices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Failed to load notices',
                              style: TextStyle(
                                color: AppColors.textPrimary(isDark),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _friendlyError(_error!),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton(
                                  onPressed: _fetchNotices,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Retry'),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: () =>
                                      _openUrl(widget.source.toString()),
                                  child: const Text('Open on website'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchNotices,
                      child: displayed.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 40),
                                Center(
                                  child: Text(
                                    query.isEmpty
                                        ? 'No notices found'
                                        : 'No matches for "$_searchQuery"',
                                    style: TextStyle(
                                      color: AppColors.textSecondary(isDark),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                              itemCount: displayed.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = displayed[index];

                                Widget card = Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.card(isDark),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.border(isDark),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.cardShadow(isDark),
                                        blurRadius: 6,
                                        offset: const Offset(0, 4),
                                        spreadRadius: -1,
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        final isAcademicCalendar = widget.source
                                            .toString()
                                            .contains('academic-calendar');
                                        if (item.isPdf && !isAcademicCalendar) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (ctx) => PdfViewerPage(
                                                url: item.url,
                                                title: item.title,
                                                academicCalendarFix: widget
                                                    .source
                                                    .toString()
                                                    .contains(
                                                      'academic-calendar',
                                                    ),
                                                referer: widget.source
                                                    .toString(),
                                              ),
                                            ),
                                          );
                                        } else {
                                          _openUrl(item.url);
                                        }
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        AppColors.noticeCircle(
                                                          isDark,
                                                        ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '${index + 1}',
                                                    style: TextStyle(
                                                      color:
                                                          AppColors.noticeCircleText(
                                                            isDark,
                                                          ),
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item.title,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color:
                                                              AppColors.noticeTitleText(
                                                                isDark,
                                                              ),
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Text(
                                                        item.date.isNotEmpty
                                                            ? 'Published: ${item.date}'
                                                            : 'Published: Unknown',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              AppColors.noticeDateText(
                                                                isDark,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: AppColors.divider(isDark),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                Text(
                                                  'View Details',
                                                  style: TextStyle(
                                                    color: AppColors.accentText(
                                                      isDark,
                                                    ),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons
                                                      .arrow_forward_ios_rounded,
                                                  size: 14,
                                                  color: AppColors.accentText(
                                                    isDark,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );

                                if (_staggerCtrl != null) {
                                  final start = (index * 0.05).clamp(0.0, 0.7);
                                  final end = (start + 0.3).clamp(0.0, 1.0);
                                  final fade = Tween<double>(begin: 0, end: 1)
                                      .animate(
                                        CurvedAnimation(
                                          parent: _staggerCtrl!,
                                          curve: Interval(
                                            start,
                                            end,
                                            curve: Curves.easeOut,
                                          ),
                                        ),
                                      );
                                  final slide =
                                      Tween<Offset>(
                                        begin: const Offset(0, 0.2),
                                        end: Offset.zero,
                                      ).animate(
                                        CurvedAnimation(
                                          parent: _staggerCtrl!,
                                          curve: Interval(
                                            start,
                                            end,
                                            curve: Curves.easeOut,
                                          ),
                                        ),
                                      );
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: card,
                                    ),
                                  );
                                }
                                return card;
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTs(String iso) {
    try {
      final dt = DateTime.tryParse(iso);
      if (dt == null) return iso;
      final s = dt.toLocal().toString();
      return s.split('.').first;
    } catch (_) {
      return iso;
    }
  }

  String _friendlyError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('certificate_verify_failed') || s.contains('handshake')) {
      return 'Secure connection failed (certificate verification). You can open the page in your browser.';
    }
    if (s.contains('http 404') || s.contains('http 404') || s.contains('404')) {
      return 'No notices found at the source (404). You can open the page in your browser.';
    }
    if (s.contains('timed out') || s.contains('timeout')) {
      return 'Connection timed out. Check your network and try again.';
    }
    return raw;
  }
}

class _PulseShimmer extends StatefulWidget {
  final Widget child;
  const _PulseShimmer({required this.child});
  @override
  State<_PulseShimmer> createState() => _PulseShimmerState();
}

class _PulseShimmerState extends State<_PulseShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl),
      child: widget.child,
    );
  }
}

class _NoticeShimmerCard extends StatelessWidget {
  final bool isDark;
  const _NoticeShimmerCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final baseColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(isDark)),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow(isDark),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: baseColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 16,
                  color: baseColor,
                  margin: const EdgeInsets.only(top: 2, bottom: 8),
                ),
                Container(width: 150, height: 16, color: baseColor),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(width: 60, height: 12, color: baseColor),
                    const SizedBox(width: 16),
                    Container(width: 80, height: 12, color: baseColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBannerAd extends StatefulWidget {
  const _NoticeBannerAd();
  @override
  State<_NoticeBannerAd> createState() => _NoticeBannerAdState();
}

class _NoticeBannerAdState extends State<_NoticeBannerAd> {
  BannerAd? _banner;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      adUnitId: 'ca-app-pub-5879343068930294/3672304278',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _banner == null) return const SizedBox.shrink();
    return SizedBox(
      width: _banner!.size.width.toDouble(),
      height: _banner!.size.height.toDouble(),
      child: AdWidget(ad: _banner!),
    );
  }
}
