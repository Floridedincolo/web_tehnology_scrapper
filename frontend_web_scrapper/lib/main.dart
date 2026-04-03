import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io' show File;

void main() {
  runApp(const ScraperApp());
}

class ScraperApp extends StatelessWidget {
  const ScraperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tech Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
      ),
      home: const ScannerHomePage(),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  double _progress = 0.0;
  int _currentScanned = 0;
  int _totalToScan = 0;
  bool _cancelRequested = false;

  Map<String, dynamic>? _results;
  String? _error;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'parquet'],
    );

    if (result != null) {
      if (result.files.single.extension == 'parquet') {
        await _uploadParquetFile(result);
      } else if (result.files.single.bytes != null) {
        final content = utf8.decode(result.files.single.bytes!);
        setState(() {
          _controller.text = content;
        });
      } else if (result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        setState(() {
          _controller.text = content;
        });
      }
    }
  }

  Future<void> _uploadParquetFile(FilePickerResult result) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('http://localhost:8000/upload-parquet'));

      if (result.files.single.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          result.files.single.bytes!,
          filename: result.files.single.name,
        ));
      } else if (result.files.single.path != null) {
        request.files.add(await http.MultipartFile.fromPath('file', result.files.single.path!));
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody);
        if (decoded['domains'] != null) {
          final List<dynamic> domainsList = decoded['domains'];
          setState(() {
            _controller.text = domainsList.join('\n');
            _isLoading = false;
          });
        } else if (decoded['error'] != null) {
          setState(() {
            _error = 'Parquet Error: ${decoded['error']}';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Failed to upload parquet: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _scanDomains() async {
    final domains = _controller.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (domains.isEmpty) return;

    setState(() {
      _isLoading = true;
      _cancelRequested = false;
      _error = null;
      _results = {};
      _totalToScan = domains.length;
      _currentScanned = 0;
      _progress = 0.0;
    });

    Map<String, dynamic> tempResults = {};

    for (int i = 0; i < domains.length; i++) {
      if (_cancelRequested) break;

      final domain = domains[i];

      try {
        final response = await http.post(
          Uri.parse('http://localhost:8000/scan'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'domains': [domain]}),
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> decoded = jsonDecode(response.body);
          tempResults.addAll(decoded);
        } else {
          tempResults[domain] = {'error': 'HTTP Error: ${response.statusCode}'};
        }
      } catch (e) {
        tempResults[domain] = {'error': 'Nu s-a putut conecta la API local'};
      }

      if (mounted) {
        setState(() {
          _currentScanned = i + 1;
          _progress = _currentScanned / _totalToScan;
          _results = Map.from(tempResults);
        });
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _cancelScan() {
    setState(() {
      _cancelRequested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tech Scanner',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth > 800;
          // MODIFICARE AICI: Am adaugat SingleChildScrollView pentru a face sectiunile complet scrollabile
          final content = isLargeScreen
              ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  flex: 1,
                  child: SingleChildScrollView(child: _buildInputSection())
              ),
              const SizedBox(width: 32),
              Expanded(
                  flex: 2,
                  child: SingleChildScrollView(child: _buildResultsSection())
              ),
            ],
          )
              : SingleChildScrollView(
            child: Column(
              children: [
                _buildInputSection(),
                const SizedBox(height: 24),
                _buildResultsSection(),
              ],
            ),
          );
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0), child: content);
        },
      ),
    );
  }

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Domenii țintă',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 10,
          enabled: !_isLoading,
          style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            hintText: 'emag.ro\nshopify.com',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _pickFile,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Încarcă fișier'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300),
                  foregroundColor: const Color(0xFF475569),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _isLoading
            ? ElevatedButton.icon(
          onPressed: _cancelScan,
          icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
          label: const Text('Oprește Scanarea', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        )
            : ElevatedButton(
          onPressed: _scanDomains,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Lansează Scanarea', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildStatistics() {
    if (_results == null || _results!.isEmpty) return const SizedBox.shrink();

    int totalDomains = _results!.length;
    int successCount = 0;
    int errorCount = 0;

    int totalDetections = 0;
    Map<String, int> techCounts = {};

    for (var entry in _results!.entries) {
      final data = entry.value;
      if (data.containsKey('error') && data['error'] != null) {
        errorCount++;
        continue;
      }
      successCount++;
      final techs = data['technologies'] as Map<String, dynamic>? ?? {};

      totalDetections += techs.length;

      for (var techEntry in techs.entries) {
        final techName = techEntry.key;
        techCounts[techName] = (techCounts[techName] ?? 0) + 1;
      }
    }

    int uniqueTechnologies = techCounts.length;

    final sortedTechs = techCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topTechs = sortedTechs.take(5).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Prezentare Generală', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatBadge('Domenii', totalDomains, const Color(0xFF475569)),
                _buildStatBadge('Succes', successCount, const Color(0xFF10B981)),
                _buildStatBadge('Eșuate', errorCount, const Color(0xFFEF4444)),
              ],
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200)
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatBadge('Total Detecții', totalDetections, const Color(0xFF8B5CF6)),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  _buildStatBadge('Tehnologii Unice', uniqueTechnologies, const Color(0xFF3B82F6)),
                ],
              ),
            ),

            if (topTechs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),
              const Text('Top Tehnologii', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              const SizedBox(height: 20),
              SizedBox(
                height: 160,
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 35,
                          sections: topTechs.asMap().entries.map((e) {
                            final idx = e.key;
                            final entry = e.value;
                            final colors = [
                              const Color(0xFF6366F1), const Color(0xFF38BDF8),
                              const Color(0xFF34D399), const Color(0xFFFBBF24), const Color(0xFFF472B6),
                            ];
                            return PieChartSectionData(
                              color: colors[idx % colors.length],
                              value: entry.value.toDouble(),
                              title: '${entry.value}',
                              radius: 40,
                              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: topTechs.asMap().entries.map((e) {
                          final idx = e.key;
                          final entry = e.value;
                          final colors = [
                            const Color(0xFF6366F1), const Color(0xFF38BDF8),
                            const Color(0xFF34D399), const Color(0xFFFBBF24), const Color(0xFFF472B6),
                          ];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[idx % colors.length], shape: BoxShape.circle)),
                                const SizedBox(width: 12),
                                Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 13, color: Color(0xFF334155)), overflow: TextOverflow.ellipsis)),
                                Text('${entry.value}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge(String label, int count, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(count.toString(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Se scanează... $_currentScanned din $_totalToScan',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              Text(
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFEEF2FF),
              color: const Color(0xFF6366F1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_results == null && !_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 24),
            Text('Niciun rezultat momentan.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text('Introdu domeniile în stânga și apasă Scanare.', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isLoading) _buildProgressBar(),

        _buildStatistics(),

        if (_results != null && _results!.isNotEmpty) ...[
          const Text('Rezultate Detaliate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 12),

          // MODIFICARE AICI: Am scos "Expanded" si am adaugat "shrinkWrap" si "physics"
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _results!.keys.length,
            itemBuilder: (context, index) {
              final domain = _results!.keys.elementAt(_results!.keys.length - 1 - index);
              final data = _results![domain];

              if (data.containsKey('error') && data['error'] != null) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFFECACA), width: 1),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                    title: Text(domain, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF991B1B))),
                    subtitle: Text(data['error'].toString(), style: const TextStyle(color: Color(0xFFB91C1C))),
                  ),
                );
              }

              final techs = data['technologies'] as Map<String, dynamic>? ?? {};

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(color: Color(0xFFEEF2FF), shape: BoxShape.circle),
                      child: Text(techs.length.toString(), style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    title: Text(domain, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1E293B))),
                    subtitle: Text('Tehnologii detectate', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    childrenPadding: const EdgeInsets.only(bottom: 16),
                    children: techs.entries.map((e) {
                      final techName = e.key;
                      final techData = e.value as Map<String, dynamic>;
                      final categories = (techData['categories'] as List<dynamic>?)?.join(', ') ?? 'Necunoscut';

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(techName, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF334155))),
                                  Text(categories, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ]
      ],
    );
  }
}