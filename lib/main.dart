import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// 分析模式枚举
enum AnalysisMode {
  faceDetection, // 人脸检测模式
  manualPoint,   // 手动点击模式
  manualRect,    // 手动框选模式
}

/// 肤色分析结果数据类
class SkinColorResult {
  final String id;
  final Offset position;
  final Color averageColor;
  final String rgbValue;
  final String hsvValue;
  final String hexValue;
  final String toneType;
  final String warmCoolType;
  final String emoji;
  final DateTime createdAt;

  SkinColorResult({
    required this.id,
    required this.position,
    required this.averageColor,
    required this.rgbValue,
    required this.hsvValue,
    required this.hexValue,
    required this.toneType,
    required this.warmCoolType,
    required this.emoji,
    required this.createdAt,
  });
}

/// 莫兰迪色系主题配置
class MorandiTheme {
  // 主要背景色 - 柔和米色
  static const Color primaryBackground = Color(0xFFF8F6F0);
  static const Color secondaryBackground = Color(0xFFF2F0EA);
  
  // 卡片和容器色
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color softGray = Color(0xFFE8E6E0);
  
  // 强调色 - 柔和粉色系
  static const Color accentPink = Color(0xFFE8D5D3);
  static const Color softPink = Color(0xFFF0E6E4);
  
  // 文字色
  static const Color primaryText = Color(0xFF5D5A52);
  static const Color secondaryText = Color(0xFF8B8680);
  static const Color lightText = Color(0xFFA8A39A);
  
  // 功能色
  static const Color warmTone = Color(0xFFE8B4A0);
  static const Color coolTone = Color(0xFFA8C8E1);
  static const Color neutralTone = Color(0xFFD4C4B0);
  
  // 阴影色
  static const Color shadowColor = Color(0x10000000);
}

void main() {
  runApp(const SkinAnalyzerApp());
}

class SkinAnalyzerApp extends StatelessWidget {
  const SkinAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '肌肤色调分析师',
      theme: ThemeData(
        primarySwatch: Colors.brown,
        scaffoldBackgroundColor: MorandiTheme.primaryBackground,
        cardTheme: CardTheme(
          color: MorandiTheme.cardBackground,
          elevation: 8,
          shadowColor: MorandiTheme.shadowColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: MorandiTheme.primaryBackground,
          foregroundColor: MorandiTheme.primaryText,
          elevation: 0,
          centerTitle: true,
        ),
        useMaterial3: true,
      ),
      home: const SkinColorAnalyzer(),
    );
  }
}

class SkinColorAnalyzer extends StatefulWidget {
  const SkinColorAnalyzer({super.key});

  @override
  State<SkinColorAnalyzer> createState() => _SkinColorAnalyzerState();
}

class _SkinColorAnalyzerState extends State<SkinColorAnalyzer> with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _imageKey = GlobalKey();
  
  // 图片相关
  File? _selectedImage;
  Size? _imageSize;
  Size? _displaySize;
  
  // 多区域分析结果
  List<SkinColorResult> _analysisResults = [];
  bool _isAnalyzing = false;
  
  // 分析模式
  AnalysisMode _analysisMode = AnalysisMode.faceDetection;
  
  // 人脸检测结果
  List<Face> _detectedFaces = [];
  
  // 框选相关
  Offset? _rectStartPoint;
  Offset? _currentDragPoint;
  bool _isSelectingRect = false;
  
  // 动画控制器
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  /// 从相机拍照
  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        await _loadNewImage(File(image.path));
      }
    } catch (e) {
      _showErrorDialog('拍照失败: $e');
    }
  }

  /// 从相册选择
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        await _loadNewImage(File(image.path));
      }
    } catch (e) {
      _showErrorDialog('选择图片失败: $e');
    }
  }

  /// 加载新图片
  Future<void> _loadNewImage(File imageFile) async {
    setState(() {
      _selectedImage = imageFile;
      _analysisResults.clear();
      _detectedFaces.clear();
      _isSelectingRect = false;
      _rectStartPoint = null;
      _currentDragPoint = null;
    });
    
    await _loadImageSize();
    _fadeController.forward();
    
    // 自动进行人脸检测
    await _performFaceDetection();
  }

  /// 加载图片尺寸
  Future<void> _loadImageSize() async {
    if (_selectedImage == null) return;
    
    final bytes = await _selectedImage!.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image != null) {
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    }
  }

  /// 自动人脸检测并分析脸颊区域
  Future<void> _performFaceDetection() async {
    if (_selectedImage == null) return;
    
    setState(() {
      _isAnalyzing = true;
    });

    try {
      final inputImage = InputImage.fromFile(_selectedImage!);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      
      setState(() {
        _detectedFaces = faces;
      });
      
      if (faces.isNotEmpty && _analysisMode == AnalysisMode.faceDetection) {
        final face = faces.first;
        final boundingBox = face.boundingBox;
        
        // 计算脸颊区域位置
        final leftCheekX = boundingBox.left + boundingBox.width * 0.2;
        final rightCheekX = boundingBox.right - boundingBox.width * 0.2;
        final cheekY = boundingBox.top + boundingBox.height * 0.5;
        
        // 转换为显示坐标并分析
        if (_displaySize != null && _imageSize != null) {
          final scaleX = _displaySize!.width / _imageSize!.width;
          final scaleY = _displaySize!.height / _imageSize!.height;
          
          final leftCheekDisplay = Offset(leftCheekX * scaleX, cheekY * scaleY);
          final rightCheekDisplay = Offset(rightCheekX * scaleX, cheekY * scaleY);
          
          await _analyzeSkinColorAtPoint(leftCheekDisplay, '左脸颊');
          await _analyzeSkinColorAtPoint(rightCheekDisplay, '右脸颊');
        }
      }
      
      await faceDetector.close();
    } catch (e) {
      print('人脸检测失败: $e');
    }

    setState(() {
      _isAnalyzing = false;
    });
  }

  /// 处理图片点击事件
  void _onImageTap(TapDownDetails details) {
    if (_selectedImage == null) return;

    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    setState(() {
      _displaySize = renderBox.size;
    });

    if (_analysisMode == AnalysisMode.manualPoint) {
      // 点击模式：分析点击位置
      _scaleController.forward().then((_) {
        _scaleController.reverse();
      });
      _analyzeSkinColorAtPoint(localPosition, '自定义区域 ${_analysisResults.length + 1}');
    } else if (_analysisMode == AnalysisMode.manualRect) {
      // 框选模式：开始框选
      if (!_isSelectingRect) {
        setState(() {
          _rectStartPoint = localPosition;
          _currentDragPoint = localPosition;
          _isSelectingRect = true;
        });
      }
    }
  }

  /// 处理拖拽更新事件
  void _onPanUpdate(DragUpdateDetails details) {
    if (_selectedImage == null || !_isSelectingRect) return;

    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    setState(() {
      _currentDragPoint = localPosition;
    });
  }

  /// 处理拖拽结束事件
  void _onPanEnd(DragEndDetails details) {
    if (_isSelectingRect && _rectStartPoint != null && _currentDragPoint != null) {
      final rect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
      
      // 分析矩形区域内的肤色
      _analyzeRectRegion(rect);
      
      setState(() {
        _isSelectingRect = false;
        _rectStartPoint = null;
        _currentDragPoint = null;
      });
    }
  }

  /// 分析矩形区域的肤色
  Future<void> _analyzeRectRegion(Rect rect) async {
    final center = rect.center;
    await _analyzeSkinColorAtPoint(center, '框选区域 ${_analysisResults.length + 1}');
  }

  /// 分析指定点的肤色
  Future<void> _analyzeSkinColorAtPoint(Offset displayPoint, String label) async {
    if (_selectedImage == null || _imageSize == null || _displaySize == null) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      // 转换显示坐标到图片坐标
      final scaleX = _imageSize!.width / _displaySize!.width;
      final scaleY = _imageSize!.height / _displaySize!.height;
      
      final imageX = (displayPoint.dx * scaleX).round();
      final imageY = (displayPoint.dy * scaleY).round();

      // 读取图片数据
      final bytes = await _selectedImage!.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image != null) {
        // 在点击位置周围采样50x50区域
        final sampleSize = 25; // 半径
        final samples = <Color>[];
        
        for (int dy = -sampleSize; dy <= sampleSize; dy += 2) {
          for (int dx = -sampleSize; dx <= sampleSize; dx += 2) {
            final x = imageX + dx;
            final y = imageY + dy;
            
            if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
              final pixel = image.getPixel(x, y);
              samples.add(Color.fromARGB(
                255,
                pixel.r.toInt(),
                pixel.g.toInt(),
                pixel.b.toInt(),
              ));
            }
          }
        }

        if (samples.isNotEmpty) {
          // 使用KMeans聚类获取主要肤色
          final dominantColor = _performKMeansClustering(samples);
          final result = _analyzeSkinTone(dominantColor, displayPoint, label);
          
          setState(() {
            _analysisResults.add(result);
          });
        }
      }
    } catch (e) {
      print('肤色分析失败: $e');
    }

    setState(() {
      _isAnalyzing = false;
    });
  }

  /// 简化的KMeans聚类算法
  Color _performKMeansClustering(List<Color> samples) {
    if (samples.isEmpty) return Colors.transparent;
    
    // 简化版：计算加权平均，过滤极值
    samples.sort((a, b) {
      final brightnessA = (a.red + a.green + a.blue) / 3;
      final brightnessB = (b.red + b.green + b.blue) / 3;
      return brightnessA.compareTo(brightnessB);
    });
    
    // 去除最亮和最暗的20%像素
    final startIndex = (samples.length * 0.1).round();
    final endIndex = (samples.length * 0.9).round();
    final filteredSamples = samples.sublist(startIndex, endIndex);
    
    // 计算平均值
    int totalR = 0, totalG = 0, totalB = 0;
    for (final color in filteredSamples) {
      totalR += color.red;
      totalG += color.green;
      totalB += color.blue;
    }
    
    final count = filteredSamples.length;
    return Color.fromARGB(
      255,
      (totalR / count).round(),
      (totalG / count).round(),
      (totalB / count).round(),
    );
  }

  /// 分析肤色色调
  SkinColorResult _analyzeSkinTone(Color color, Offset position, String label) {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    
    // 转换为HSV
    final hsv = HSVColor.fromColor(color);
    final hue = hsv.hue;
    final saturation = hsv.saturation;
    final value = hsv.value;
    
    // 计算红黄比例
    final redYellowRatio = r / (g + 1); // 避免除零
    final yellowRatio = (r + g) / (b + 1);
    
    // 肤色分类逻辑
    String toneType;
    String warmCoolType;
    String emoji;
    
    if (hue >= 15 && hue <= 35 && yellowRatio > 1.8) {
      // 偏黄调
      toneType = '偏黄调';
      warmCoolType = '暖色调';
      emoji = '☀️';
    } else if (hue >= 340 || hue <= 15) {
      // 偏粉调
      toneType = '偏粉调';
      warmCoolType = '冷色调';
      emoji = '❄️';
    } else if (redYellowRatio > 1.2 && saturation > 0.3) {
      // 偏红调
      toneType = '偏红调';
      warmCoolType = '暖色调';
      emoji = '🌸';
    } else {
      // 中性调
      toneType = '中性调';
      warmCoolType = '平衡色调';
      emoji = '🌿';
    }
    
    return SkinColorResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: position,
      averageColor: color,
      rgbValue: 'RGB($r, $g, $b)',
      hsvValue: 'HSV(${hue.round()}°, ${(saturation * 100).round()}%, ${(value * 100).round()}%)',
      hexValue: '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
      toneType: toneType,
      warmCoolType: warmCoolType,
      emoji: emoji,
      createdAt: DateTime.now(),
    );
  }

  /// 清除所有分析结果
  void _clearResults() {
    setState(() {
      _analysisResults.clear();
    });
  }

  /// 删除指定分析结果
  void _removeResult(String id) {
    setState(() {
      _analysisResults.removeWhere((result) => result.id == id);
    });
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🌸 肌肤色调分析师',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: MorandiTheme.primaryText,
          ),
        ),
        actions: [
          if (_analysisResults.isNotEmpty)
            IconButton(
              onPressed: _clearResults,
              icon: const Icon(Icons.clear_all_rounded),
              tooltip: '清除所有结果',
            ),
        ],
      ),
      body: Column(
        children: [
          // 顶部操作区域
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: MorandiTheme.secondaryBackground,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // 拍照和选择按钮
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.camera_alt_rounded,
                        label: '拍照分析',
                        onPressed: _pickFromCamera,
                        color: MorandiTheme.warmTone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.photo_library_rounded,
                        label: '相册选择',
                        onPressed: _pickFromGallery,
                        color: MorandiTheme.coolTone,
                      ),
                    ),
                  ],
                ),
                
                // 分析模式选择
                if (_selectedImage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: MorandiTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: MorandiTheme.shadowColor,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildModeButton(
                            icon: Icons.face_rounded,
                            label: '人脸',
                            mode: AnalysisMode.faceDetection,
                          ),
                        ),
                        Expanded(
                          child: _buildModeButton(
                            icon: Icons.touch_app_rounded,
                            label: '点选',
                            mode: AnalysisMode.manualPoint,
                          ),
                        ),
                        Expanded(
                          child: _buildModeButton(
                            icon: Icons.crop_free_rounded,
                            label: '框选',
                            mode: AnalysisMode.manualRect,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // 主要内容区域
          Expanded(
            child: _selectedImage == null
                ? _buildWelcomeScreen()
                : _buildAnalysisScreen(),
          ),
        ],
      ),
    );
  }

  /// 构建模式选择按钮
  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required AnalysisMode mode,
  }) {
    final isSelected = _analysisMode == mode;
    
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected ? MorandiTheme.accentPink : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _analysisMode = mode;
              // 切换模式时清理状态
              _isSelectingRect = false;
              _rectStartPoint = null;
              _currentDragPoint = null;
            });
            
            // 如果切换到人脸模式且有图片，重新进行人脸检测
            if (mode == AnalysisMode.faceDetection && _selectedImage != null) {
              _performFaceDetection();
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : MorandiTheme.secondaryText,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : MorandiTheme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: MorandiTheme.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建欢迎界面
  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: MorandiTheme.softPink,
                borderRadius: BorderRadius.circular(60),
                boxShadow: [
                  BoxShadow(
                    color: MorandiTheme.shadowColor,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.face_rounded,
                size: 60,
                color: MorandiTheme.primaryText,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              '发现你的专属色调',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: MorandiTheme.primaryText,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '拍照或选择照片，点击皮肤区域\n即可分析肤色冷暖调和色彩特征',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: MorandiTheme.secondaryText,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _buildFeatureList(),
          ],
        ),
      ),
    );
  }

  /// 构建功能特色列表
  Widget _buildFeatureList() {
    final features = [
      {'icon': '🎯', 'text': '多点取色对比分析'},
      {'icon': '🌈', 'text': '精准色调分类识别'},
      {'icon': '💄', 'text': '专业护肤建议参考'},
    ];

    return Column(
      children: features.map((feature) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(feature['icon']!, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 16),
            Text(
              feature['text']!,
              style: TextStyle(
                fontSize: 16,
                color: MorandiTheme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  /// 构建分析界面
  Widget _buildAnalysisScreen() {
    return Column(
      children: [
        // 图片显示区域
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: MorandiTheme.shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // 图片
                GestureDetector(
                  key: _imageKey,
                  onTapDown: _onImageTap,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: Stack(
                      children: [
                        Image.file(
                          _selectedImage!,
                          width: double.infinity,
                          height: 300,
                          fit: BoxFit.cover,
                        ),
                        // Canvas绘制层
                        Positioned.fill(
                          child: CustomPaint(
                            painter: AnalysisPainter(
                              detectedFaces: _detectedFaces,
                              imageSize: _imageSize,
                              displaySize: _displaySize,
                              rectStartPoint: _rectStartPoint,
                              currentDragPoint: _currentDragPoint,
                              isSelectingRect: _isSelectingRect,
                              analysisMode: _analysisMode,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // 分析点标记
                ..._analysisResults.map((result) => Positioned(
                  left: result.position.dx - 8,
                  top: result.position.dy - 8,
                  child: ScaleTransition(
                    scale: _scaleController,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: result.averageColor, width: 3),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
                
                // 加载指示器
                if (_isAnalyzing)
                  Container(
                    width: double.infinity,
                    height: 300,
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        
        // 分析结果区域
        Expanded(
          child: _analysisResults.isEmpty
              ? _buildEmptyResults()
              : _buildResultsList(),
        ),
      ],
    );
  }

  /// 构建空结果提示
  Widget _buildEmptyResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 48,
              color: MorandiTheme.lightText,
            ),
            const SizedBox(height: 16),
            Text(
              '点击图片上的皮肤区域\n开始分析肤色特征',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: MorandiTheme.secondaryText,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建结果列表
  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _analysisResults.length,
      itemBuilder: (context, index) {
        final result = _analysisResults[index];
        return _buildResultCard(result, index);
      },
    );
  }

  /// 构建结果卡片
  Widget _buildResultCard(SkinColorResult result, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 卡片头部
              Row(
                children: [
                  // 色块
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: result.averageColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: MorandiTheme.softGray,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MorandiTheme.shadowColor,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // 分类信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              result.emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              result.toneType,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: MorandiTheme.primaryText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.warmCoolType,
                          style: TextStyle(
                            fontSize: 14,
                            color: MorandiTheme.secondaryText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 删除按钮
                  IconButton(
                    onPressed: () => _removeResult(result.id),
                    icon: Icon(
                      Icons.close_rounded,
                      color: MorandiTheme.lightText,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // 色彩数值信息
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MorandiTheme.secondaryBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildColorInfoRow('RGB', result.rgbValue),
                    const SizedBox(height: 8),
                    _buildColorInfoRow('HSV', result.hsvValue),
                    const SizedBox(height: 8),
                    _buildColorInfoRow('HEX', result.hexValue),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建色彩信息行
  Widget _buildColorInfoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: MorandiTheme.primaryText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              color: MorandiTheme.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// 自定义绘制器，用于绘制人脸框和选择区域
class AnalysisPainter extends CustomPainter {
  final List<Face> detectedFaces;
  final Size? imageSize;
  final Size? displaySize;
  final Offset? rectStartPoint;
  final Offset? currentDragPoint;
  final bool isSelectingRect;
  final AnalysisMode analysisMode;

  AnalysisPainter({
    required this.detectedFaces,
    this.imageSize,
    this.displaySize,
    this.rectStartPoint,
    this.currentDragPoint,
    this.isSelectingRect = false,
    required this.analysisMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null || displaySize == null) return;

    final scaleX = size.width / imageSize!.width;
    final scaleY = size.height / imageSize!.height;

    // 绘制人脸框
    if (analysisMode == AnalysisMode.faceDetection && detectedFaces.isNotEmpty) {
      final facePaint = Paint()
        ..color = MorandiTheme.warmTone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      final cheekPaint = Paint()
        ..color = MorandiTheme.coolTone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final fillPaint = Paint()
        ..color = MorandiTheme.warmTone.withOpacity(0.1)
        ..style = PaintingStyle.fill;

      for (final face in detectedFaces) {
        final boundingBox = face.boundingBox;
        
        // 转换坐标
        final rect = Rect.fromLTWH(
          boundingBox.left * scaleX,
          boundingBox.top * scaleY,
          boundingBox.width * scaleX,
          boundingBox.height * scaleY,
        );

        // 绘制人脸框
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          facePaint,
        );

        // 绘制脸颊区域标记
        final leftCheekX = rect.left + rect.width * 0.2;
        final rightCheekX = rect.right - rect.width * 0.2;
        final cheekY = rect.top + rect.height * 0.5;
        
        // 左脸颊圆圈
        canvas.drawCircle(
          Offset(leftCheekX, cheekY),
          15,
          Paint()..color = MorandiTheme.coolTone.withOpacity(0.3)..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          Offset(leftCheekX, cheekY),
          15,
          cheekPaint,
        );
        
        // 右脸颊圆圈
        canvas.drawCircle(
          Offset(rightCheekX, cheekY),
          15,
          Paint()..color = MorandiTheme.coolTone.withOpacity(0.3)..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          Offset(rightCheekX, cheekY),
          15,
          cheekPaint,
        );

        // 绘制标签
        _drawText(canvas, '人脸检测', rect.topCenter + const Offset(0, -25), MorandiTheme.primaryText);
      }
    }

    // 绘制框选区域
    if (isSelectingRect && rectStartPoint != null && currentDragPoint != null) {
      final rect = Rect.fromPoints(rectStartPoint!, currentDragPoint!);
      
      final rectPaint = Paint()
        ..color = MorandiTheme.accentPink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final rectFillPaint = Paint()
        ..color = MorandiTheme.accentPink.withOpacity(0.2)
        ..style = PaintingStyle.fill;

      canvas.drawRect(rect, rectFillPaint);
      _drawDashedRect(canvas, rect, rectPaint);
      
      // 显示尺寸
      final width = rect.width.abs().toInt();
      final height = rect.height.abs().toInt();
      _drawText(canvas, '${width}×${height}', rect.center, MorandiTheme.primaryText);
    }
  }

  /// 绘制虚线矩形
  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashWidth = 8.0;
    const dashSpace = 4.0;
    
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dashWidth, dashSpace);
  }

  /// 绘制虚线
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dashWidth, double dashSpace) {
    final distance = (end - start).distance;
    final dashCount = (distance / (dashWidth + dashSpace)).floor();
    
    for (int i = 0; i < dashCount; i++) {
      final startRatio = i * (dashWidth + dashSpace) / distance;
      final endRatio = (i * (dashWidth + dashSpace) + dashWidth) / distance;
      
      final dashStart = Offset.lerp(start, end, startRatio)!;
      final dashEnd = Offset.lerp(start, end, endRatio)!;
      
      canvas.drawLine(dashStart, dashEnd, paint);
    }
  }

  /// 绘制文字
  void _drawText(Canvas canvas, String text, Offset position, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              color: Colors.white.withOpacity(0.8),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      position - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}