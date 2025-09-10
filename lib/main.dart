import 'dart:async';
import 'dart:io';
import 'dart:math' as Math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// 分析模式枚举
enum AnalysisMode {
  faceDetection, // 人脸检测模式
  smartAnalysis, // 智能分析模式
  manualPoint,   // 手动点击模式
  manualRect,    // 手动框选模式
}
/// 肤色类别
class SkinToneCategory {
  final String name;
  final String tone;
  final String emoji;

  SkinToneCategory(this.name, this.tone, this.emoji);
}

class SkinToneThreshold {
  final double minIta;
  final String name;
  final String tone;
  final String emoji;

  const SkinToneThreshold(this.minIta, this.name, this.tone, this.emoji);
}

class SkinToneClassifier {
  static const _thresholds = [
    SkinToneThreshold(55, '瓷白 · 透亮', '极浅亮调', '✨'),
    SkinToneThreshold(41, '自然浅肤 · 清透', '浅亮调', '🌟'),
    SkinToneThreshold(28, '均衡中性 · 健康', '中性调', '🌼'),
    SkinToneThreshold(10, '阳光小麦 · 活力', '健康小麦调', '🌞'),
    SkinToneThreshold(-30, '古铜健康 · 魅力', '古铜深调', '🌹'),
  ];

  static SkinToneCategory classify(double ita) {
    for (final t in _thresholds) {
      if (ita > t.minIta) return SkinToneCategory(t.name, t.tone, t.emoji);
    }
    return SkinToneCategory('浓郁深肤 · 高级', '深邃浓调', '🖤');
  }
}

/// 冷暖色调分析
class TemperatureAnalyzer {
  static String analyze(double warmScore, double coolScore) {
    if (warmScore > coolScore + 0.2) {
      return '暖调 · 偏金感';
    } else if (coolScore > warmScore + 0.2) {
      return '冷调 · 偏粉感';
    } else {
      return '中性 · 百搭感';
    }
  }
}

/// 偏色分析
class ColorBiasAnalyzer {
  static String analyze(double a, double bLab) {
    if (bLab > 15 && a > 5) {
      return '带一点金色温感';
    } else if (a > 10 && bLab < 10) {
      return '透出红润粉嫩感';
    } else if (a < 0) {
      return '略带清冷绿感';
    } else if (bLab < 0) {
      return '轻微冷蓝感';
    } else {
      return '均衡自然感';
    }
  }
}

/// 高级指标构建
class AdvancedMetricsBuilder {
  static Map<String, String> build({
    required double ita,
    required double skinConfidence,
    required double warmScore,
    required double coolScore,
    required double a,
    required double bLab,
    required double saturation,
    required double value,
    required double L,
  }) {
    return {
      'ITA': ita.toStringAsFixed(2),
      '肤色识别可信度': '${(skinConfidence * 100).toStringAsFixed(1)}%',
      '暖感指数': '${(warmScore * 100).toStringAsFixed(1)}',
      '冷感指数': '${(coolScore * 100).toStringAsFixed(1)}',
      '色彩饱和度': Math.sqrt(a * a + bLab * bLab).toStringAsFixed(2),
      '纯净度': '${(saturation * 100).toStringAsFixed(1)}',
      '亮度感': '${(value * 100).toStringAsFixed(1)}',
      '光学明度': L.toStringAsFixed(1),
    };
  }
}
/// 肤色分析结果数据类（进阶版）
class SkinColorResult {
  final String id;
  final Offset position;
  final Color averageColor;
  final String rgbValue;
  final String hsvValue;
  final String hexValue;
  final String labValue;
  final String ycbcrValue;
  final String toneType;
  final String warmCoolType;
  final String colorBias; // 偏色分析：偏黄/偏粉/中性
  final String skinCategory; // 肤色类别：白皙/浅色/中等/小麦/深色
  final double confidence; // 肤色置信度 0-1
  final String emoji;
  final DateTime createdAt;
  final Map<String, dynamic> advancedMetrics; // 高级指标

  SkinColorResult({
    required this.id,
    required this.position,
    required this.averageColor,
    required this.rgbValue,
    required this.hsvValue,
    required this.hexValue,
    required this.labValue,
    required this.ycbcrValue,
    required this.toneType,
    required this.warmCoolType,
    required this.colorBias,
    required this.skinCategory,
    required this.confidence,
    required this.emoji,
    required this.createdAt,
    required this.advancedMetrics,
  });
}

/// 高级颜色空间转换工具类
class ColorSpaceConverter {
  /// RGB转CIELAB色彩空间
  static List<double> rgbToLab(int r, int g, int b) {
    // 转换为标准RGB (0-1)
    double rNorm = r / 255.0;
    double gNorm = g / 255.0;
    double bNorm = b / 255.0;
    
    // sRGB到线性RGB的转换
    rNorm = rNorm <= 0.04045 ? rNorm / 12.92 : Math.pow((rNorm + 0.055) / 1.055, 2.4).toDouble();
    gNorm = gNorm <= 0.04045 ? gNorm / 12.92 : Math.pow((gNorm + 0.055) / 1.055, 2.4).toDouble();
    bNorm = bNorm <= 0.04045 ? bNorm / 12.92 : Math.pow((bNorm + 0.055) / 1.055, 2.4).toDouble();
    
    // 线性RGB到XYZ的转换 (D65标准光源)
    double x = rNorm * 0.4124564 + gNorm * 0.3575761 + bNorm * 0.1804375;
    double y = rNorm * 0.2126729 + gNorm * 0.7151522 + bNorm * 0.0721750;
    double z = rNorm * 0.0193339 + gNorm * 0.1191920 + bNorm * 0.9503041;
    
    // XYZ到Lab的转换
    // 参考白点D65
    const xn = 0.95047;
    const yn = 1.0;
    const zn = 1.08883;
    
    x = x / xn;
    y = y / yn;
    z = z / zn;
    
    const delta = 6.0 / 29.0;
    const deltaSquared = delta * delta;
    const deltaCubed = delta * delta * delta;
    
    x = x > deltaCubed ? Math.pow(x, 1/3).toDouble() : (x / (3 * deltaSquared)) + (4.0 / 29.0);
    y = y > deltaCubed ? Math.pow(y, 1/3).toDouble() : (y / (3 * deltaSquared)) + (4.0 / 29.0);
    z = z > deltaCubed ? Math.pow(z, 1/3).toDouble() : (z / (3 * deltaSquared)) + (4.0 / 29.0);
    
    final L = (116 * y) - 16;
    final a = 500 * (x - y);
    final b_component = 200 * (y - z);
    
    return [L, a, b_component];
  }
  
  /// RGB转YCbCr色彩空间
  static List<double> rgbToYCbCr(int r, int g, int b) {
    final Y = 0.299 * r + 0.587 * g + 0.114 * b;
    final Cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    final Cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    
    return [Y, Cb, Cr];
  }
  
  /// 计算颜色在YCbCr空间的肤色置信度
  static double calculateSkinConfidence(List<double> ycbcr) {
    final cb = ycbcr[1];
    final cr = ycbcr[2];
    
    // 基于研究的肤色分布范围
    const cbMin = 77.0, cbMax = 127.0;
    const crMin = 133.0, crMax = 173.0;
    
    // 计算在肤色范围内的程度
    double cbScore = 0.0;
    double crScore = 0.0;
    
    if (cb >= cbMin && cb <= cbMax) {
      cbScore = 1.0 - (Math.min((cb - cbMin).abs(), (cb - cbMax).abs()) / ((cbMax - cbMin) / 2));
    }
    
    if (cr >= crMin && cr <= crMax) {
      crScore = 1.0 - (Math.min((cr - crMin).abs(), (cr - crMax).abs()) / ((crMax - crMin) / 2));
    }
    
    return (cbScore * crScore).clamp(0.0, 1.0);
  }
}

/// 高级肤色检测器
class AdvancedSkinDetector {
  /// 高斯模糊预处理
  static List<Color> applyGaussianBlur(List<Color> pixels, int width, int height) {
    if (pixels.isEmpty) return pixels;
    
    // 简化的高斯核 (3x3)
    final kernel = [
      [1, 2, 1],
      [2, 4, 2],
      [1, 2, 1]
    ];
    const kernelSum = 16;
    
    final blurred = List<Color>.filled(pixels.length, Colors.transparent);
    
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        int r = 0, g = 0, b = 0;
        
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixelIndex = (y + ky) * width + (x + kx);
            if (pixelIndex >= 0 && pixelIndex < pixels.length) {
              final pixel = pixels[pixelIndex];
              final weight = kernel[ky + 1][kx + 1];
              
              r += pixel.red * weight;
              g += pixel.green * weight;
              b += pixel.blue * weight;
            }
          }
        }
        
        blurred[y * width + x] = Color.fromARGB(
          255,
          (r / kernelSum).round().clamp(0, 255),
          (g / kernelSum).round().clamp(0, 255),
          (b / kernelSum).round().clamp(0, 255),
        );
      }
    }
    
    return blurred;
  }
  
  /// 基于YCbCr的肤色像素过滤
  static List<Color> filterSkinPixels(List<Color> pixels) {
    final skinPixels = <Color>[];
    
    for (final pixel in pixels) {
      final ycbcr = ColorSpaceConverter.rgbToYCbCr(pixel.red, pixel.green, pixel.blue);
      final confidence = ColorSpaceConverter.calculateSkinConfidence(ycbcr);
      
      // 只保留肤色置信度大于0.3的像素
      if (confidence > 0.3) {
        skinPixels.add(pixel);
      }
    }
    
    return skinPixels;
  }
  
  /// 高级K-means聚类（专门针对肤色）
  static List<List<Color>> performSkinColorClustering(List<Color> skinPixels, int k) {
    if (skinPixels.length < k) return [skinPixels];
    
    // 在LAB色彩空间进行聚类以获得更好的感知一致性
    final labPixels = skinPixels.map((color) {
      final lab = ColorSpaceConverter.rgbToLab(color.red, color.green, color.blue);
      return {
        'color': color,
        'lab': lab,
        'ycbcr': ColorSpaceConverter.rgbToYCbCr(color.red, color.green, color.blue),
      };
    }).toList();
    
    // 初始化聚类中心（使用K-means++）
    final centers = <Map<String, dynamic>>[];
    final random = Math.Random();
    
    // 第一个中心随机选择
    centers.add(labPixels[random.nextInt(labPixels.length)]);
    
    // 后续中心使用K-means++策略
    for (int i = 1; i < k; i++) {
      final distances = <double>[];
      double totalDistance = 0;
      
      for (final pixel in labPixels) {
        double minDistance = double.infinity;
        for (final center in centers) {
          final distance = _calculateLabDistance(
            pixel['lab'] as List<double>,
            center['lab'] as List<double>
          );
          if (distance < minDistance) {
            minDistance = distance;
          }
        }
        distances.add(minDistance * minDistance);
        totalDistance += minDistance * minDistance;
      }
      
      // 轮盘赌选择
      final threshold = random.nextDouble() * totalDistance;
      double sum = 0;
      int selectedIndex = labPixels.length - 1;
      
      for (int j = 0; j < labPixels.length; j++) {
        sum += distances[j];
        if (sum >= threshold) {
          selectedIndex = j;
          break;
        }
      }
      
      centers.add(labPixels[selectedIndex]);
    }
    
    // 迭代聚类
    const maxIterations = 20;
    const convergenceThreshold = 1.0;
    
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      final clusters = List.generate(k, (index) => <Map<String, dynamic>>[]);
      
      // 分配像素到最近的聚类中心
      for (final pixel in labPixels) {
        int closestCenter = 0;
        double minDistance = _calculateLabDistance(
          pixel['lab'] as List<double>,
          centers[0]['lab'] as List<double>
        );
        
        for (int i = 1; i < centers.length; i++) {
          final distance = _calculateLabDistance(
            pixel['lab'] as List<double>,
            centers[i]['lab'] as List<double>
          );
          
          if (distance < minDistance) {
            minDistance = distance;
            closestCenter = i;
          }
        }
        
        clusters[closestCenter].add(pixel);
      }
      
      // 更新聚类中心
      bool converged = true;
      for (int i = 0; i < k; i++) {
        if (clusters[i].isNotEmpty) {
          final newCenter = _calculateClusterCenter(clusters[i]);
          final distance = _calculateLabDistance(
            centers[i]['lab'] as List<double>,
            newCenter['lab'] as List<double>
          );
          
          if (distance > convergenceThreshold) {
            centers[i] = newCenter;
            converged = false;
          }
        }
      }
      
      if (converged) break;
    }
    
    // 返回颜色聚类结果
    final result = <List<Color>>[];
    for (int i = 0; i < k; i++) {
      final cluster = <Color>[];
      for (final pixel in labPixels) {
        int closestCenter = 0;
        double minDistance = _calculateLabDistance(
          pixel['lab'] as List<double>,
          centers[0]['lab'] as List<double>
        );
        
        for (int j = 1; j < centers.length; j++) {
          final distance = _calculateLabDistance(
            pixel['lab'] as List<double>,
            centers[j]['lab'] as List<double>
          );
          
          if (distance < minDistance) {
            minDistance = distance;
            closestCenter = j;
          }
        }
        
        if (closestCenter == i) {
          cluster.add(pixel['color'] as Color);
        }
      }
      
      if (cluster.isNotEmpty) {
        result.add(cluster);
      }
    }
    
    return result;
  }
  
  /// 计算LAB色彩空间距离
  static double _calculateLabDistance(List<double> lab1, List<double> lab2) {
    final dL = lab1[0] - lab2[0];
    final da = lab1[1] - lab2[1];
    final db = lab1[2] - lab2[2];
    
    // 使用CIEDE2000色差公式的简化版本
    return Math.sqrt(dL * dL + da * da + db * db);
  }
  
  /// 计算聚类中心
  static Map<String, dynamic> _calculateClusterCenter(List<Map<String, dynamic>> cluster) {
    if (cluster.isEmpty) {
      return {
        'color': Colors.grey,
        'lab': [50.0, 0.0, 0.0],
        'ycbcr': [128.0, 128.0, 128.0],
      };
    }
    
    double totalL = 0, totalA = 0, totalB = 0;
    double totalY = 0, totalCb = 0, totalCr = 0;
    int totalR = 0, totalG = 0, totalBlue = 0;
    
    for (final pixel in cluster) {
      final lab = pixel['lab'] as List<double>;
      final ycbcr = pixel['ycbcr'] as List<double>;
      final color = pixel['color'] as Color;
      
      totalL += lab[0];
      totalA += lab[1];
      totalB += lab[2];
      
      totalY += ycbcr[0];
      totalCb += ycbcr[1];
      totalCr += ycbcr[2];
      
      totalR += color.red;
      totalG += color.green;
      totalBlue += color.blue;
    }
    
    final count = cluster.length;
    final avgL = totalL / count;
    final avgA = totalA / count;
    final avgB = totalB / count;
    
    final avgR = (totalR / count).round();
    final avgG = (totalG / count).round();
    final avgBlue = (totalBlue / count).round();
    
    return {
      'color': Color.fromARGB(255, avgR, avgG, avgBlue),
      'lab': [avgL, avgA, avgB],
      'ycbcr': [totalY / count, totalCb / count, totalCr / count],
    };
  }
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
  bool _isDraggingHandle = false;
  int? _draggingHandleIndex; // 0=topLeft, 1=topRight, 2=bottomLeft, 3=bottomRight
  bool _isHoveringHandle = false;
  int? _hoveringHandleIndex;
  
  // 长按拖拽相关
  bool _isLongPressing = false;
  bool _isDraggingRegion = false;
  Offset? _longPressStartPoint;
  Offset? _dragOffset;
  int? _draggingRegionIndex; // 正在拖拽的区域索引
  Timer? _longPressTimer;
  
  // 动画列表相关
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  
  // 动画控制器
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _rectAnimationController;
  late AnimationController _handleAnimationController;
  late AnimationController _scanAnimationController;
  late AnimationController _colorPointAnimationController;
  
  // 智能分析相关
  List<Map<String, dynamic>> _smartAnalysisPoints = [];
  bool _isShowingScanAnimation = false;
  int? _selectedColorPointIndex; // 选中的颜色指示点索引
  
  // 人脸轮廓动画相关
  late AnimationController _faceContourAnimationController;
  late Animation<double> _faceContourAnimation;
  late AnimationController _landmarkAnimationController;
  late Animation<double> _landmarkAnimation;
  bool _showFaceContours = false;
  List<Map<String, dynamic>> _faceContourPaths = [];
  bool _isDrawingContours = false;
  
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
    _rectAnimationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _handleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scanAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _colorPointAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // 人脸轮廓动画控制器
    _faceContourAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _faceContourAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _faceContourAnimationController,
      curve: Curves.easeInOut,
    ));
    
    // 关键点动画控制器
    _landmarkAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _landmarkAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _landmarkAnimationController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _rectAnimationController.dispose();
    _handleAnimationController.dispose();
    _scanAnimationController.dispose();
    _colorPointAnimationController.dispose();
    _faceContourAnimationController.dispose();
    _landmarkAnimationController.dispose();
    _longPressTimer?.cancel();
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
    
    // 根据当前模式进行相应的分析
    if (_analysisMode == AnalysisMode.faceDetection) {
      await _performFaceDetection();
    } else if (_analysisMode == AnalysisMode.smartAnalysis) {
      await _startSmartAnalysisWithAnimation();
    }
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
  /// 执行人脸检测 - 增强版（包含轮廓动画）
  Future<void> _performFaceDetection() async {
    if (_selectedImage == null) return;
    
    setState(() {
      _isAnalyzing = true;
      _showFaceContours = false;
      _faceContourPaths.clear();
    });

    try {
      final inputImage = InputImage.fromFile(_selectedImage!);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: true,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      
      setState(() {
        _detectedFaces = faces;
      });
      
      if (faces.isNotEmpty && _analysisMode == AnalysisMode.faceDetection) {
        // 生成人脸轮廓路径数据
        await _generateFaceContourPaths(faces);
        
        setState(() {
          _showFaceContours = true;
          _isDrawingContours = true;
        });
        
        // 启动轮廓绘制动画
        await _startFaceContourAnimation();
        
        // 检测到人脸，进行脸颊分析
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
      } else if (faces.isEmpty) {
        // 没有检测到人脸，自动切换到智能分析模式
        setState(() {
          _analysisMode = AnalysisMode.smartAnalysis;
        });
        // 执行智能色调分析
        await _performSmartAnalysis();
      }
      
      await faceDetector.close();
    } catch (e) {
      print('人脸检测失败: $e');
      // 检测失败也切换到智能模式
      setState(() {
        _analysisMode = AnalysisMode.smartAnalysis;
      });
      await _performSmartAnalysis();
    }

    setState(() {
      _isAnalyzing = false;
    });
  }

  /// 生成人脸轮廓路径数据
  Future<void> _generateFaceContourPaths(List<Face> faces) async {
    _faceContourPaths.clear();
    
    for (int faceIndex = 0; faceIndex < faces.length; faceIndex++) {
      final face = faces[faceIndex];
      final contourPaths = <Map<String, dynamic>>[];
      
      // 面部轮廓
      if (face.contours[FaceContourType.face] != null) {
        final faceContour = face.contours[FaceContourType.face]!;
        contourPaths.add({
          'type': 'face_outline',
          'points': faceContour.points.map((point) => Offset(point.x.toDouble(), point.y.toDouble())).toList(),
          'color': Colors.cyan.withOpacity(0.8),
          'strokeWidth': 2.5,
          'animationDelay': 0,
        });
      }
      
      // 左眼轮廓
      if (face.contours[FaceContourType.leftEye] != null) {
        final leftEyeContour = face.contours[FaceContourType.leftEye]!;
        contourPaths.add({
          'type': 'left_eye',
          'points': leftEyeContour.points.map((point) => Offset(point.x.toDouble(), point.y.toDouble())).toList(),
          'color': Colors.lightBlueAccent.withOpacity(0.9),
          'strokeWidth': 2.0,
          'animationDelay': 300,
        });
      }
      
      // 右眼轮廓
      if (face.contours[FaceContourType.rightEye] != null) {
        final rightEyeContour = face.contours[FaceContourType.rightEye]!;
        contourPaths.add({
          'type': 'right_eye',
          'points': rightEyeContour.points.map((point) => Offset(point.x.toDouble(), point.y.toDouble())).toList(),
          'color': Colors.lightBlueAccent.withOpacity(0.9),
          'strokeWidth': 2.0,
          'animationDelay': 300,
        });
      }
      
      // 鼻子轮廓
      if (face.contours[FaceContourType.noseBridge] != null) {
        final noseBridgeContour = face.contours[FaceContourType.noseBridge]!;
        contourPaths.add({
          'type': 'nose_bridge',
          'points': noseBridgeContour.points.map((point) => Offset(point.x.toDouble(), point.y.toDouble())).toList(),
          'color': Colors.tealAccent.withOpacity(0.8),
          'strokeWidth': 1.8,
          'animationDelay': 600,
        });
      }
      
      if (face.contours[FaceContourType.noseBottom] != null) {
        final noseBottomContour = face.contours[FaceContourType.noseBottom]!;
        contourPaths.add({
          'type': 'nose_bottom',
          'points': noseBottomContour.points.map((point) => Offset(point.x.toDouble(), point.y.toDouble())).toList(),
          'color': Colors.tealAccent.withOpacity(0.8),
          'strokeWidth': 1.8,
          'animationDelay': 700,
        });
      }
      
      // 嘴巴轮廓
      if (face.contours[FaceContourType.upperLipTop] != null) {
        final upperLipContour = face.contours[FaceContourType.upperLipTop]!;
        contourPaths.add({
          'type': 'upper_lip',
          'points': upperLipContour.points.map((point) => Offset(point.x.toDouble(), point.y.toDouble())).toList(),
          'color': Colors.pinkAccent.withOpacity(0.8),
          'strokeWidth': 2.0,
          'animationDelay': 900,
        });
      }
      
      if (face.contours[FaceContourType.lowerLipBottom] != null) {
        final lowerLipContour = face.contours[FaceContourType.lowerLipBottom]!;
        contourPaths.add({
          'type': 'lower_lip',
          'points': lowerLipContour.points.map((point) => Offset(point.x.toDouble(), point.y.toDouble())).toList(),
          'color': Colors.pinkAccent.withOpacity(0.8),
          'strokeWidth': 2.0,
          'animationDelay': 1000,
        });
      }
      
      // 添加关键点
      final landmarks = <Map<String, dynamic>>[];
      if (face.landmarks[FaceLandmarkType.leftEye] != null) {
        landmarks.add({
          'type': 'left_eye_center',
          'position': face.landmarks[FaceLandmarkType.leftEye]!.position,
          'color': Colors.yellowAccent,
          'size': 4.0,
          'animationDelay': 1200,
        });
      }
      
      if (face.landmarks[FaceLandmarkType.rightEye] != null) {
        landmarks.add({
          'type': 'right_eye_center',
          'position': face.landmarks[FaceLandmarkType.rightEye]!.position,
          'color': Colors.yellowAccent,
          'size': 4.0,
          'animationDelay': 1200,
        });
      }
      
      if (face.landmarks[FaceLandmarkType.noseBase] != null) {
        landmarks.add({
          'type': 'nose_base',
          'position': face.landmarks[FaceLandmarkType.noseBase]!.position,
          'color': Colors.orangeAccent,
          'size': 3.5,
          'animationDelay': 1400,
        });
      }
      
      if (face.landmarks[FaceLandmarkType.bottomMouth] != null) {
        landmarks.add({
          'type': 'mouth_center',
          'position': face.landmarks[FaceLandmarkType.bottomMouth]!.position,
          'color': Colors.redAccent,
          'size': 3.5,
          'animationDelay': 1600,
        });
      }
      
      _faceContourPaths.add({
        'faceIndex': faceIndex,
        'boundingBox': face.boundingBox,
        'contours': contourPaths,
        'landmarks': landmarks,
      });
    }
  }
  
  /// 启动人脸轮廓动画
  Future<void> _startFaceContourAnimation() async {
    // 重置动画
    _faceContourAnimationController.reset();
    _landmarkAnimationController.reset();
    
    // 启动轮廓动画
    _faceContourAnimationController.forward();
    
    // 延迟启动关键点动画
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      _landmarkAnimationController.forward();
    }
    
    // 动画完成后的处理
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        _isDrawingContours = false;
      });
    }
  }

  /// 带动画效果的智能分析
  Future<void> _startSmartAnalysisWithAnimation() async {
    if (_selectedImage == null) return;
    
    print('开始智能分析动画'); // 调试日志
    
    // 确保在主线程中更新状态
    if (mounted) {
      setState(() {
        _isShowingScanAnimation = true;
        _smartAnalysisPoints.clear();
        _analysisResults.clear(); // 清除之前的分析结果
      });
    }
    
    // 启动扫描动画
    _scanAnimationController.reset();
    await _scanAnimationController.forward();
    
    // 等待扫描动画完成一半后开始实际分析
    await Future.delayed(const Duration(milliseconds: 1000));
    
    // 执行智能分析
    await _performSmartAnalysis();
    
    // 扫描完成，显示颜色指示点
    if (mounted) {
      setState(() {
        _isShowingScanAnimation = false;
      });
    }
    
    // 启动颜色点出现动画
    _colorPointAnimationController.reset();
    await _colorPointAnimationController.forward();

    print('智能分析动画完成'); // 调试日志
  }

  /// 高级智能分析模式 - 进阶版肤色检测算法
  Future<void> _performSmartAnalysis() async {
    if (_selectedImage == null || _imageSize == null) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      // 读取图片数据
      final bytes = await _selectedImage!.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image != null) {
        print('开始高级肤色分析，图片尺寸: ${image.width}x${image.height}');
        
        // 第一步：预处理 - 采样和噪声过滤
        final rawSamples = <Color>[];
        final regionSamples = <String, List<Color>>{};
        
        // 自适应采样策略
        final sampleDensity = _calculateOptimalSampleDensity(image.width, image.height);
        final stepX = Math.max(1, (image.width / sampleDensity).round());
        final stepY = Math.max(1, (image.height / sampleDensity).round());
        
        // 分区域采样 (3x3网格)
        for (int regionY = 0; regionY < 3; regionY++) {
          for (int regionX = 0; regionX < 3; regionX++) {
            final regionKey = '$regionX-$regionY';
            final regionPixels = <Color>[];
            
            final startX = (regionX * image.width / 3).round();
            final startY = (regionY * image.height / 3).round();
            final endX = ((regionX + 1) * image.width / 3).round();
            final endY = ((regionY + 1) * image.height / 3).round();
            
            // 区域内采样
            for (int y = startY; y < endY; y += stepY) {
              for (int x = startX; x < endX; x += stepX) {
                if (x < image.width && y < image.height) {
                  final pixel = image.getPixel(x, y);
                  final color = Color.fromARGB(
                    255,
                    pixel.r.toInt(),
                    pixel.g.toInt(),
                    pixel.b.toInt(),
                  );
                  
                  regionPixels.add(color);
                  rawSamples.add(color);
                }
              }
            }
            
            regionSamples[regionKey] = regionPixels;
          }
        }
        
        print('采样完成，总样本数: ${rawSamples.length}');
        
        // 第二步：高斯模糊预处理（针对每个区域）
        final processedRegions = <String, List<Color>>{};
        for (final entry in regionSamples.entries) {
          if (entry.value.isNotEmpty) {
            // 简化的区域处理 - 应用均值滤波
            final filtered = _applyMeanFilter(entry.value);
            processedRegions[entry.key] = filtered;
          }
        }
        
        // 第三步：肤色像素过滤
        final regionAnalysis = <String, Map<String, dynamic>>{};
        for (final entry in processedRegions.entries) {
          final skinPixels = AdvancedSkinDetector.filterSkinPixels(entry.value);
          
          if (skinPixels.isNotEmpty) {
            // 第四步：K-means聚类提取主要肤色
            final clusters = AdvancedSkinDetector.performSkinColorClustering(skinPixels, 3);
            
            if (clusters.isNotEmpty) {
              // 选择最大的聚类作为该区域的代表色
              clusters.sort((a, b) => b.length.compareTo(a.length));
              final dominantCluster = clusters.first;
              final dominantColor = _calculateClusterAverage(dominantCluster);
              
              // 计算肤色置信度
              final ycbcr = ColorSpaceConverter.rgbToYCbCr(
                dominantColor.red, dominantColor.green, dominantColor.blue
              );
              final confidence = ColorSpaceConverter.calculateSkinConfidence(ycbcr);
              
              regionAnalysis[entry.key] = {
                'color': dominantColor,
                'count': skinPixels.length,
                'confidence': confidence,
                'isSkinTone': confidence > 0.5,
                'clusterSize': dominantCluster.length,
              };
            }
          }
        }
        
        print('肤色分析完成，有效区域数: ${regionAnalysis.length}');
        
        // 第五步：生成智能分析的颜色指示点
        if (_displaySize != null && regionAnalysis.isNotEmpty) {
          final newSmartAnalysisPoints = <Map<String, dynamic>>[];
          
          // 按置信度和样本数量排序
          final sortedRegions = regionAnalysis.entries.toList()
            ..sort((a, b) {
              final aScore = (a.value['confidence'] as double) * (a.value['count'] as int);
              final bScore = (b.value['confidence'] as double) * (b.value['count'] as int);
              return bScore.compareTo(aScore);
            });
          
          // 最多显示6个高质量指示点
          final maxPoints = Math.min(6, sortedRegions.length);
          
          for (int i = 0; i < maxPoints; i++) {
            final regionKey = sortedRegions[i].key;
            final regionData = sortedRegions[i].value;
            final color = regionData['color'] as Color;
            final confidence = regionData['confidence'] as double;
            
            // 只显示高置信度的肤色区域
            if (confidence > 0.3) {
              // 计算区域在显示坐标系中的位置
              final regionCoords = regionKey.split('-');
              final regionX = int.parse(regionCoords[0]);
              final regionY = int.parse(regionCoords[1]);
              
              final displayX = (regionX + 0.5) * _displaySize!.width / 3;
              final displayY = (regionY + 0.5) * _displaySize!.height / 3;
              
              final position = Offset(displayX, displayY);
              
              // 使用高级算法分析颜色特征
              final result = _analyzeSkinTone(color, position, '肤色区域 ${i + 1}');
              
              newSmartAnalysisPoints.add({
                'position': position,
                'color': color,
                'result': result,
                'regionKey': regionKey,
                'sampleCount': regionData['count'],
                'confidence': confidence,
                'isSkinTone': regionData['isSkinTone'],
              });
            }
          }
          
          // 更新状态
          if (mounted) {
            setState(() {
              _smartAnalysisPoints = newSmartAnalysisPoints;
            });
          }
          
          // 选择最佳肤色区域添加到分析结果
          if (sortedRegions.isNotEmpty) {
            final bestRegion = sortedRegions.first;
            final bestColor = bestRegion.value['color'] as Color;
            final bestConfidence = bestRegion.value['confidence'] as double;
            
            if (bestConfidence > 0.5) {
              final centerPoint = Offset(
                _displaySize!.width / 2,
                _displaySize!.height / 2,
              );
              
              final result = _analyzeSkinTone(bestColor, centerPoint, '主要肤色 (置信度: ${(bestConfidence * 100).toStringAsFixed(1)}%)');
              
              if (mounted) {
                setState(() {
                  _analysisResults.insert(0, result);
                });
                // 触发 AnimatedList 插入动画
                _listKey.currentState?.insertItem(0);
              }
            }
          }
          
          print('高级分析完成，生成了 ${newSmartAnalysisPoints.length} 个高质量指示点');
        }
      }
    } catch (e) {
      print('高级智能分析失败: $e');
    }

    setState(() {
      _isAnalyzing = false;
    });
  }
  
  /// 计算最优采样密度
  int _calculateOptimalSampleDensity(int width, int height) {
    final totalPixels = width * height;
    
    if (totalPixels > 1000000) { // 大于1MP
      return 200;
    } else if (totalPixels > 500000) { // 大于0.5MP
      return 150;
    } else {
      return 100;
    }
  }
  
  /// 简化的均值滤波
  List<Color> _applyMeanFilter(List<Color> pixels) {
    if (pixels.length < 9) return pixels;
    
    final filtered = <Color>[];
    const kernelSize = 3;
    
    for (int i = kernelSize; i < pixels.length - kernelSize; i += kernelSize) {
      int r = 0, g = 0, b = 0;
      int count = 0;
      
      for (int j = i - kernelSize; j <= i + kernelSize && j < pixels.length; j++) {
        r += pixels[j].red;
        g += pixels[j].green;
        b += pixels[j].blue;
        count++;
      }
      
      if (count > 0) {
        filtered.add(Color.fromARGB(
          255,
          (r / count).round(),
          (g / count).round(),
          (b / count).round(),
        ));
      }
    }
    
    return filtered.isNotEmpty ? filtered : pixels;
  }
  
  /// 计算聚类平均颜色
  Color _calculateClusterAverage(List<Color> cluster) {
    if (cluster.isEmpty) return Colors.grey;
    
    int totalR = 0, totalG = 0, totalB = 0;
    for (final color in cluster) {
      totalR += color.red;
      totalG += color.green;
      totalB += color.blue;
    }
    
    return Color.fromARGB(
      255,
      (totalR / cluster.length).round(),
      (totalG / cluster.length).round(),
      (totalB / cluster.length).round(),
    );
  }
  
  /// 判断颜色是否可能是肤色
  bool _isLikelySkinTone(Color color) {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    
    // 转换为HSV
    final hsv = HSVColor.fromColor(color);
    final hue = hsv.hue;
    final saturation = hsv.saturation;
    final value = hsv.value;
    
    // 肤色的色相通常在[0, 50]或[340, 360]范围内
    final validHue = (hue >= 0 && hue <= 50) || (hue >= 340 && hue <= 360);
    
    // 肤色的饱和度通常不会太高也不会太低
    final validSaturation = saturation >= 0.1 && saturation <= 0.6;
    
    // 肤色的亮度通常不会太暗也不会太亮
    final validValue = value >= 0.2 && value <= 0.95;
    
    // 肤色的RGB通常满足一定的比例关系
    final validRatio = r > g && g > b && r > 60 && (r - g) > 5;
    
    // 综合判断
    return validHue && validSaturation && validValue && validRatio;
  }

  /// 计算颜色饱和度
  double _calculateSaturation(Color color) {
    final r = color.red / 255.0;
    final g = color.green / 255.0;
    final b = color.blue / 255.0;
    
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    
    if (max == 0) return 0;
    return (max - min) / max;
  }

  /// 提取图片的主导色调 - 升级版
  Color _extractDominantColor(List<Color> samples) {
    if (samples.isEmpty) return Colors.grey;
    
    // 预处理：过滤极端颜色和异常值
    final filteredSamples = _filterOutlierColors(samples);
    
    // 使用改进的K-means++聚类算法，聚类成5个主要颜色以获得更精细的结果
    final clusters = _performAdvancedKMeans(filteredSamples, 5);
    
    // 选择最大的聚类作为主导色
    clusters.sort((a, b) => b.length.compareTo(a.length));
    
    if (clusters.isNotEmpty && clusters.first.isNotEmpty) {
      // 对最大聚类进行进一步分析，确保颜色代表性
      final dominantCluster = clusters.first;
      
      // 计算聚类中心
      final clusterCenter = _calculateClusterCenter(dominantCluster);
      
      // 计算聚类内颜色的方差，评估聚类质量
      final variance = _calculateClusterVariance(dominantCluster, clusterCenter);
      
      // 如果方差过大，说明聚类不够紧凑，尝试使用中值滤波获得更稳定的结果
      if (variance > 2000) {
        return _calculateMedianColor(dominantCluster);
      }
      
      return clusterCenter;
    }
    
    // 如果聚类失败，回退到简单的K-means
    return _performKMeansClustering(filteredSamples);
  }
  
  /// 过滤异常颜色值
  List<Color> _filterOutlierColors(List<Color> samples) {
    if (samples.length < 10) return samples;
    
    // 计算亮度和饱和度
    final brightnessList = samples.map((color) {
      return (color.red + color.green + color.blue) / 3;
    }).toList();
    
    final saturationList = samples.map(_calculateSaturation).toList();
    
    // 计算亮度和饱和度的四分位数
    brightnessList.sort();
    saturationList.sort();
    
    final q1BrightnessIndex = (brightnessList.length * 0.25).floor();
    final q3BrightnessIndex = (brightnessList.length * 0.75).floor();
    final q1Brightness = brightnessList[q1BrightnessIndex];
    final q3Brightness = brightnessList[q3BrightnessIndex];
    final iqrBrightness = q3Brightness - q1Brightness;
    
    final q1SaturationIndex = (saturationList.length * 0.25).floor();
    final q3SaturationIndex = (saturationList.length * 0.75).floor();
    final q1Saturation = saturationList[q1SaturationIndex];
    final q3Saturation = saturationList[q3SaturationIndex];
    final iqrSaturation = q3Saturation - q1Saturation;
    
    // 定义异常值边界
    final lowerBrightnessBound = q1Brightness - 1.5 * iqrBrightness;
    final upperBrightnessBound = q3Brightness + 1.5 * iqrBrightness;
    final lowerSaturationBound = q1Saturation - 1.5 * iqrSaturation;
    final upperSaturationBound = q3Saturation + 1.5 * iqrSaturation;
    
    // 过滤异常值
    return samples.where((color) {
      final brightness = (color.red + color.green + color.blue) / 3;
      final saturation = _calculateSaturation(color);
      
      return brightness >= lowerBrightnessBound && 
             brightness <= upperBrightnessBound &&
             saturation >= lowerSaturationBound && 
             saturation <= upperSaturationBound;
    }).toList();
  }
  
  /// 计算聚类方差
  double _calculateClusterVariance(List<Color> cluster, Color center) {
    if (cluster.isEmpty) return 0;
    
    double totalVariance = 0;
    for (final color in cluster) {
      final distance = _colorDistance(color, center);
      totalVariance += distance * distance;
    }
    
    return totalVariance / cluster.length;
  }
  
  /// 计算颜色中值
  Color _calculateMedianColor(List<Color> colors) {
    if (colors.isEmpty) return Colors.grey;
    
    // 分别排序R、G、B通道
    final redValues = colors.map((c) => c.red).toList()..sort();
    final greenValues = colors.map((c) => c.green).toList()..sort();
    final blueValues = colors.map((c) => c.blue).toList()..sort();
    
    // 取中值
    final medianIndex = colors.length ~/ 2;
    final medianRed = redValues[medianIndex];
    final medianGreen = greenValues[medianIndex];
    final medianBlue = blueValues[medianIndex];
    
    return Color.fromARGB(255, medianRed, medianGreen, medianBlue);
  }

  /// 高级K-means聚类算法 - 升级版
  List<List<Color>> _performAdvancedKMeans(List<Color> samples, int k) {
    if (samples.length < k) {
      return [samples];
    }
    
    // 转换颜色到Lab色彩空间进行聚类，以获得更符合人眼感知的结果
    final labSamples = <Map<String, dynamic>>[];
    for (final color in samples) {
      labSamples.add({
        'color': color,
        'lab': _rgbToLab(color.red, color.green, color.blue),
      });
    }
    
    // 初始化聚类中心
    final centers = <Map<String, dynamic>>[];
    final random = Math.Random();
    
    // 使用K-means++初始化 - 确保初始中心点分散
    final firstSample = labSamples[random.nextInt(labSamples.length)];
    centers.add(firstSample);
    
    for (int i = 1; i < k; i++) {
      final distances = <double>[];
      double totalDistance = 0;
      
      for (final sample in labSamples) {
        double minDistance = double.infinity;
        for (final center in centers) {
          final distance = _labDistance(
            sample['lab'] as List<double>, 
            center['lab'] as List<double>
          );
          if (distance < minDistance) {
            minDistance = distance;
          }
        }
        distances.add(minDistance * minDistance);
        totalDistance += minDistance * minDistance;
      }
      
      // 轮盘赌选择法选择下一个中心点
      final threshold = random.nextDouble() * totalDistance;
      double sum = 0;
      int selectedIndex = labSamples.length - 1; // 默认最后一个
      
      for (int j = 0; j < labSamples.length; j++) {
        sum += distances[j];
        if (sum >= threshold) {
          selectedIndex = j;
          break;
        }
      }
      
      centers.add(labSamples[selectedIndex]);
    }
    
    // 迭代聚类 - 增加最大迭代次数以提高精度
    final maxIterations = 15;
    final convergenceThreshold = 2.0; // Lab空间中的收敛阈值
    
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      final clusters = List.generate(k, (index) => <Map<String, dynamic>>[]);
      
      // 分配样本到最近的聚类中心
      for (final sample in labSamples) {
        int closestCenter = 0;
        double minDistance = _labDistance(
          sample['lab'] as List<double>, 
          centers[0]['lab'] as List<double>
        );
        
        for (int i = 1; i < centers.length; i++) {
          final distance = _labDistance(
            sample['lab'] as List<double>, 
            centers[i]['lab'] as List<double>
          );
          
          if (distance < minDistance) {
            minDistance = distance;
            closestCenter = i;
          }
        }
        
        clusters[closestCenter].add(sample);
      }
      
      // 更新聚类中心
      bool changed = false;
      for (int i = 0; i < k; i++) {
        if (clusters[i].isNotEmpty) {
          final newCenter = _calculateLabClusterCenter(clusters[i]);
          
          final distance = _labDistance(
            centers[i]['lab'] as List<double>, 
            newCenter['lab'] as List<double>
          );
          
          if (distance > convergenceThreshold) {
            centers[i] = newCenter;
            changed = true;
          }
        }
      }
      
      if (!changed) {
        // 收敛，返回结果
        final result = <List<Color>>[];
        for (final cluster in clusters) {
          if (cluster.isNotEmpty) {
            final colorCluster = <Color>[];
            for (final item in cluster) {
              colorCluster.add(item['color'] as Color);
            }
            result.add(colorCluster);
          }
        }
        return result;
      }
    }
    
    // 达到最大迭代次数，返回当前结果
    final finalClusters = List.generate(k, (index) => <Color>[]);
    
    for (int i = 0; i < labSamples.length; i++) {
      final sample = labSamples[i];
      int closestCenter = 0;
      double minDistance = _labDistance(
        sample['lab'] as List<double>, 
        centers[0]['lab'] as List<double>
      );
      
      for (int j = 1; j < centers.length; j++) {
        final distance = _labDistance(
          sample['lab'] as List<double>, 
          centers[j]['lab'] as List<double>
        );
        
        if (distance < minDistance) {
          minDistance = distance;
          closestCenter = j;
        }
      }
      
      finalClusters[closestCenter].add(sample['color'] as Color);
    }
    
    return finalClusters.where((cluster) => cluster.isNotEmpty).toList();
  }
  
  /// 计算Lab色彩空间中的聚类中心
  Map<String, dynamic> _calculateLabClusterCenter(List<Map<String, dynamic>> cluster) {
    if (cluster.isEmpty) {
      return {
        'color': Colors.grey,
        'lab': [50.0, 0.0, 0.0],
      };
    }
    
    double totalL = 0, totalA = 0, totalB = 0;
    
    for (final item in cluster) {
      final lab = item['lab'] as List<double>;
      totalL += lab[0];
      totalA += lab[1];
      totalB += lab[2];
    }
    
    final avgL = totalL / cluster.length;
    final avgA = totalA / cluster.length;
    final avgB = totalB / cluster.length;
    
    // 将Lab转回RGB
    final rgb = _labToRgb(avgL, avgA, avgB);
    
    return {
      'color': Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
      'lab': [avgL, avgA, avgB],
    };
  }
  
  /// Lab色彩空间中的距离计算
  double _labDistance(List<double> lab1, List<double> lab2) {
    final dL = lab1[0] - lab2[0];
    final dA = lab1[1] - lab2[1];
    final dB = lab1[2] - lab2[2];
    
    // 使用CIEDE2000色差公式的简化版本
    // 给a和b通道更高的权重，因为它们对色调感知更重要
    return Math.sqrt(dL * dL + 2.5 * dA * dA + 2.5 * dB * dB);
  }
  
  /// Lab转RGB
  List<int> _labToRgb(double L, double a, double b) {
    // Lab到XYZ
    double y = (L + 16) / 116;
    double x = a / 500 + y;
    double z = y - b / 200;
    
    // 应用反函数
    x = x > 0.206893 ? x * x * x : (x - 16 / 116) / 7.787;
    y = y > 0.206893 ? y * y * y : (y - 16 / 116) / 7.787;
    z = z > 0.206893 ? z * z * z : (z - 16 / 116) / 7.787;
    
    // 参考白点D65
    const xn = 0.95047;
    const yn = 1.0;
    const zn = 1.08883;
    
    x = x * xn;
    y = y * yn;
    z = z * zn;
    
    // XYZ到RGB
    double r = x * 3.2406 + y * -1.5372 + z * -0.4986;
    double g = x * -0.9689 + y * 1.8758 + z * 0.0415;
    double b_val = x * 0.0557 + y * -0.2040 + z * 1.0570;
    
    // 线性RGB到sRGB
    r = r > 0.0031308 ? 1.055 * Math.pow(r, 1/2.4) - 0.055 : 12.92 * r;
    g = g > 0.0031308 ? 1.055 * Math.pow(g, 1/2.4) - 0.055 : 12.92 * g;
    b_val = b_val > 0.0031308 ? 1.055 * Math.pow(b_val, 1/2.4) - 0.055 : 12.92 * b_val;
    
    // 限制在0-255范围内
    int ri = (r * 255).round().clamp(0, 255);
    int gi = (g * 255).round().clamp(0, 255);
    int bi = (b_val * 255).round().clamp(0, 255);
    
    return [ri, gi, bi];
  }

  /// 计算聚类中心颜色
  Color _calculateClusterCenter(List<Color> cluster) {
    if (cluster.isEmpty) return Colors.grey;
    
    int totalR = 0, totalG = 0, totalB = 0;
    for (final color in cluster) {
      totalR += color.red;
      totalG += color.green;
      totalB += color.blue;
    }
    
    return Color.fromARGB(
      255,
      (totalR / cluster.length).round(),
      (totalG / cluster.length).round(),
      (totalB / cluster.length).round(),
    );
  }

  /// 计算两个颜色之间的距离
  double _colorDistance(Color a, Color b) {
    final dr = a.red - b.red;
    final dg = a.green - b.green;
    final db = a.blue - b.blue;
    return Math.sqrt(dr * dr + dg * dg + db * db);
  }

  /// 生成智能采样点
  List<Offset> _generateSmartSamplePoints(int width, int height) {
    final points = <Offset>[];
    
    // 九宫格采样策略
    final gridX = [0.2, 0.5, 0.8];
    final gridY = [0.3, 0.5, 0.7];
    
    for (final x in gridX) {
      for (final y in gridY) {
        points.add(Offset(width * x, height * y));
      }
    }
    
    // 如果图片较大，添加更多采样点
    if (width > 800 || height > 800) {
      points.addAll([
        Offset(width * 0.15, height * 0.15),
        Offset(width * 0.85, height * 0.15),
        Offset(width * 0.15, height * 0.85),
        Offset(width * 0.85, height * 0.85),
      ]);
    }
    
    return points;
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
      HapticFeedback.lightImpact(); // 触觉反馈
      _scaleController.forward().then((_) {
        _scaleController.reverse();
      });
      _analyzeSkinColorAtPoint(localPosition, '自定义区域 ${_analysisResults.length + 1}');
    } else if (_analysisMode == AnalysisMode.smartAnalysis) {
      // 智能模式：检查是否点击了颜色指示点
      final clickedPointIndex = _getClickedColorPointIndex(localPosition);
      if (clickedPointIndex != null) {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedColorPointIndex = clickedPointIndex;
        });
        
        // 3秒后自动取消高亮
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _selectedColorPointIndex = null;
            });
          }
        });
      }
    } else if (_analysisMode == AnalysisMode.manualRect) {
      // 框选模式：检查是否点击了现有矩形的拖拽控制点
      if (_rectStartPoint != null && _currentDragPoint != null && !_isSelectingRect) {
        final existingRect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
        final handleIndex = _getHandleIndex(localPosition, existingRect);
        
        if (handleIndex != null) {
          HapticFeedback.mediumImpact(); // 控制点触觉反馈
          _handleAnimationController.forward();
          setState(() {
            _isDraggingHandle = true;
            _draggingHandleIndex = handleIndex;
          });
          return;
        }
        
        // 检查是否点击在现有矩形区域内
        if (existingRect.contains(localPosition)) {
          // 点击在矩形内，不做任何操作（保持选择状态）
          return;
        } else {
          // 点击在矩形外的空白处，取消选择
          HapticFeedback.lightImpact(); // 取消选择的触觉反馈
          setState(() {
            _rectStartPoint = null;
            _currentDragPoint = null;
            _isHoveringHandle = false;
            _hoveringHandleIndex = null;
          });
          return;
        }
      }
      
      // 开始新的框选
      if (!_isSelectingRect && !_isDraggingHandle) {
        HapticFeedback.selectionClick(); // 开始选择的触觉反馈
        _rectAnimationController.forward();
        setState(() {
          _rectStartPoint = localPosition;
          _currentDragPoint = localPosition;
          _isSelectingRect = true;
        });
      }
    }
  }

  /// 处理拖拽开始事件
  void _onPanStart(DragStartDetails details) {
    if (_selectedImage == null) return;

    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    // 检查是否在已选择的区域上开始拖拽
    final regionIndex = _getRegionIndexAtPosition(localPosition);
    
    if (regionIndex != null) {
      // 立即启动长按检测
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted) {
          HapticFeedback.heavyImpact();
          setState(() {
            _isLongPressing = true;
            _isDraggingRegion = true;
            _longPressStartPoint = localPosition;
            _draggingRegionIndex = regionIndex;
            _dragOffset = Offset.zero;
            
            // 重要：取消其他可能的手势状态
            _isSelectingRect = false;
            _isDraggingHandle = false;
          });
          _handleAnimationController.forward();
        }
      });
    } else if (_analysisMode == AnalysisMode.manualRect) {
      // 检查是否点击了现有矩形的拖拽控制点
      if (_rectStartPoint != null && _currentDragPoint != null && !_isSelectingRect) {
        final existingRect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
        final handleIndex = _getHandleIndex(localPosition, existingRect);
        
        if (handleIndex != null) {
          HapticFeedback.mediumImpact(); // 控制点触觉反馈
          _handleAnimationController.forward();
          setState(() {
            _isDraggingHandle = true;
            _draggingHandleIndex = handleIndex;
            
            // 取消长按定时器
            _longPressTimer?.cancel();
          });
          return;
        }
      }
      
      // 开始新的框选（如果不是在拖拽控制点）
      if (!_isDraggingHandle) {
        setState(() {
          _rectStartPoint = localPosition;
          _currentDragPoint = localPosition;
          _isSelectingRect = true;
          
          // 取消长按定时器
          _longPressTimer?.cancel();
        });
        HapticFeedback.selectionClick(); // 开始选择的触觉反馈
        _rectAnimationController.forward();
      }
    }
  }

  /// 处理拖拽更新事件
  void _onPanUpdate(DragUpdateDetails details) {
    if (_selectedImage == null) return;

    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    // 如果移动距离超过阈值，取消长按定时器（防止意外触发）
    if (_longPressTimer != null && !_isDraggingRegion) {
      final moveDistance = (localPosition - (_longPressStartPoint ?? localPosition)).distance;
      if (moveDistance > 15) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
      }
    }
    
    // 处理长按拖拽（优先级最高）
    if (_isDraggingRegion && _draggingRegionIndex != null && _longPressStartPoint != null) {
      // 计算拖拽偏移量
      final newOffset = localPosition - _longPressStartPoint!;
      
      // 边界检查，确保拖拽后的区域不超出图片范围
      final clampedOffset = _clampDragOffset(newOffset, _draggingRegionIndex!);
      
      setState(() {
        _dragOffset = clampedOffset;
      });
      
      // 轻微的触觉反馈（每10像素一次）
      if ((newOffset - (_dragOffset ?? Offset.zero)).distance > 10) {
        HapticFeedback.selectionClick();
      }
      return;
    }
    
    // 边界检查，确保拖拽不超出图片范围
    final clampedPosition = Offset(
      localPosition.dx.clamp(0.0, renderBox.size.width),
      localPosition.dy.clamp(0.0, renderBox.size.height),
    );
    
    if (_isSelectingRect) {
      // 正在创建新的矩形选择
      setState(() {
        _currentDragPoint = clampedPosition;
      });
    } else if (_isDraggingHandle && _draggingHandleIndex != null && _rectStartPoint != null && _currentDragPoint != null) {
      // 正在拖拽现有矩形的控制点
      setState(() {
        switch (_draggingHandleIndex!) {
          case 0: // topLeft
            _rectStartPoint = clampedPosition;
            break;
          case 1: // topRight
            _rectStartPoint = Offset(_rectStartPoint!.dx, clampedPosition.dy);
            _currentDragPoint = Offset(clampedPosition.dx, _currentDragPoint!.dy);
            break;
          case 2: // bottomLeft
            _rectStartPoint = Offset(clampedPosition.dx, _rectStartPoint!.dy);
            _currentDragPoint = Offset(_currentDragPoint!.dx, clampedPosition.dy);
            break;
          case 3: // bottomRight
            _currentDragPoint = clampedPosition;
            break;
        }
      });
    } else if (!_isSelectingRect && !_isDraggingHandle && _rectStartPoint != null && _currentDragPoint != null) {
      // 检查是否悬停在控制点上
      final existingRect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
      final hoveringIndex = _getHandleIndex(clampedPosition, existingRect);
      
      if (hoveringIndex != _hoveringHandleIndex) {
        setState(() {
          _isHoveringHandle = hoveringIndex != null;
          _hoveringHandleIndex = hoveringIndex;
        });
        
        if (hoveringIndex != null) {
          HapticFeedback.selectionClick(); // 悬停反馈
        }
      }
    }
  }

  /// 处理拖拽结束事件
  void _onPanEnd(DragEndDetails details) {
    // 取消长按定时器（如果还在运行）
    _longPressTimer?.cancel();
    _longPressTimer = null;
    
    // 处理长按拖拽结束
    if (_isDraggingRegion && _draggingRegionIndex != null) {
      HapticFeedback.mediumImpact(); // 完成拖拽的触觉反馈
      _handleAnimationController.reverse();
      
      // 应用拖拽偏移到区域
      if (_dragOffset != null && _dragOffset != Offset.zero) {
        _applyDragOffsetToRegion(_draggingRegionIndex!, _dragOffset!);
      }
      
      setState(() {
        _isDraggingRegion = false;
        _isLongPressing = false;
        _draggingRegionIndex = null;
        _longPressStartPoint = null;
        _dragOffset = Offset.zero;
      });
      return;
    }
    
    // 处理矩形选择结束
    if (_isSelectingRect && _rectStartPoint != null && _currentDragPoint != null) {
      final rect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
      
      // 检查矩形是否有效（最小尺寸）
      if (rect.width.abs() > 10 && rect.height.abs() > 10) {
        HapticFeedback.mediumImpact(); // 完成选择的触觉反馈
        
        // 播放完成动画
        _rectAnimationController.reverse();
        
        // 分析矩形区域内的肤色
        _analyzeRectRegion(rect);
      } else {
        // 矩形太小，取消选择
        HapticFeedback.lightImpact();
        setState(() {
          _rectStartPoint = null;
          _currentDragPoint = null;
        });
      }
      
      setState(() {
        _isSelectingRect = false;
      });
      return;
    }
    
    // 处理控制点拖拽结束
    if (_isDraggingHandle && _rectStartPoint != null && _currentDragPoint != null) {
      // 拖拽控制点结束，重新分析区域
      final rect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
      
      HapticFeedback.mediumImpact(); // 完成拖拽的触觉反馈
      _handleAnimationController.reverse();
      
      // 检查调整后的矩形是否有效
      if (rect.width.abs() > 10 && rect.height.abs() > 10) {
        _analyzeRectRegion(rect);
      }
      
      setState(() {
        _isDraggingHandle = false;
        _draggingHandleIndex = null;
      });
      return;
    }
  }

  /// 分析矩形区域的肤色
  Future<void> _analyzeRectRegion(Rect rect) async {
    final center = rect.center;
    await _analyzeSkinColorAtPoint(center, '框选区域 ${_analysisResults.length + 1}');
  }

  /// 长按开始事件处理


  /// 获取指定位置的区域索引
  int? _getRegionIndexAtPosition(Offset position) {
    // 检查框选区域
    if (_rectStartPoint != null && _currentDragPoint != null) {
      final rect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
      if (rect.contains(position)) {
        return 0; // 框选区域索引为0
      }
    }
    
    // 检查智能分析点
    for (int i = 0; i < _smartAnalysisPoints.length; i++) {
      final point = _smartAnalysisPoints[i];
      final pointPosition = point['position'] as Offset;
      final distance = (position - pointPosition).distance;
      
      if (distance <= 20) { // 20像素的点击范围
        return i + 1; // 智能分析点索引从1开始
      }
    }
    
    // 检查手动点击的分析结果
    for (int i = 0; i < _analysisResults.length; i++) {
      final result = _analysisResults[i];
      final distance = (position - result.position).distance;
      
      if (distance <= 20) { // 20像素的点击范围
        return i + 100; // 手动点击结果索引从100开始，避免冲突
      }
    }
    
    return null;
  }

  /// 限制拖拽偏移量，确保不超出图片边界
  Offset _clampDragOffset(Offset offset, int regionIndex) {
    if (_displaySize == null) return offset;
    
    final bounds = _displaySize!;
    
    if (regionIndex == 0) {
      // 框选区域的边界检查
      if (_rectStartPoint != null && _currentDragPoint != null) {
        final rect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
        final newRect = rect.translate(offset.dx, offset.dy);
        
        double clampedDx = offset.dx;
        double clampedDy = offset.dy;
        
        if (newRect.left < 0) clampedDx = -rect.left;
        if (newRect.right > bounds.width) clampedDx = bounds.width - rect.right;
        if (newRect.top < 0) clampedDy = -rect.top;
        if (newRect.bottom > bounds.height) clampedDy = bounds.height - rect.bottom;
        
        return Offset(clampedDx, clampedDy);
      }
    } else if (regionIndex > 0 && regionIndex <= _smartAnalysisPoints.length) {
      // 智能分析点的边界检查
      final pointIndex = regionIndex - 1;
      final point = _smartAnalysisPoints[pointIndex];
      final originalPosition = point['position'] as Offset;
      final newPosition = originalPosition + offset;
      
      final clampedPosition = Offset(
        newPosition.dx.clamp(0.0, bounds.width),
        newPosition.dy.clamp(0.0, bounds.height),
      );
      
      return clampedPosition - originalPosition;
    } else if (regionIndex >= 100) {
      // 手动点击结果的边界检查
      final resultIndex = regionIndex - 100;
      if (resultIndex < _analysisResults.length) {
        final result = _analysisResults[resultIndex];
        final newPosition = result.position + offset;
        
        final clampedPosition = Offset(
          newPosition.dx.clamp(0.0, bounds.width),
          newPosition.dy.clamp(0.0, bounds.height),
        );
        
        return clampedPosition - result.position;
      }
    }
    
    return offset;
  }

  /// 应用拖拽偏移到实际区域
  void _applyDragOffsetToRegion(int regionIndex, Offset offset) {
    if (regionIndex == 0) {
      // 移动框选区域
      if (_rectStartPoint != null && _currentDragPoint != null) {
        setState(() {
          _rectStartPoint = _rectStartPoint! + offset;
          _currentDragPoint = _currentDragPoint! + offset;
        });
        
        // 重新分析移动后的区域
        final rect = Rect.fromPoints(_rectStartPoint!, _currentDragPoint!);
        _analyzeRectRegion(rect);
      }
    } else if (regionIndex > 0 && regionIndex <= _smartAnalysisPoints.length) {
      // 移动智能分析点
      final pointIndex = regionIndex - 1;
      setState(() {
        final point = _smartAnalysisPoints[pointIndex];
        final newPosition = (point['position'] as Offset) + offset;
        _smartAnalysisPoints[pointIndex] = {
          ...point,
          'position': newPosition,
        };
      });
      
      // 重新分析移动后的点
      final newPosition = _smartAnalysisPoints[pointIndex]['position'] as Offset;
      _analyzeSkinColorAtPoint(newPosition, '智能分析点 ${pointIndex + 1}');
    } else if (regionIndex >= 100) {
      // 移动手动点击结果
      final resultIndex = regionIndex - 100;
      if (resultIndex < _analysisResults.length) {
        final oldResult = _analysisResults[resultIndex];
        final newPosition = oldResult.position + offset;
        
        // 重新分析移动后的位置
        _analyzeSkinColorAtPoint(newPosition, oldResult.id);
      }
    }
  }

  /// 检测点击位置是否在拖拽控制点上
  int? _getHandleIndex(Offset tapPoint, Rect rect) {
    const handleRadius = 25.0; // 增大控制点检测半径，提升触摸体验
    
    final corners = [
      rect.topLeft,     // 0
      rect.topRight,    // 1
      rect.bottomLeft,  // 2
      rect.bottomRight, // 3
    ];
    
    // 按距离排序，优先选择最近的控制点
    final distances = <MapEntry<int, double>>[];
    for (int i = 0; i < corners.length; i++) {
      final distance = (tapPoint - corners[i]).distance;
      if (distance <= handleRadius) {
        distances.add(MapEntry(i, distance));
      }
    }
    
    if (distances.isNotEmpty) {
      distances.sort((a, b) => a.value.compareTo(b.value));
      return distances.first.key;
    }
    
    return null;
  }

  /// 检测点击位置是否在颜色指示点上
  int? _getClickedColorPointIndex(Offset tapPoint) {
    const clickRadius = 30.0; // 点击检测半径
    
    for (int i = 0; i < _smartAnalysisPoints.length; i++) {
      final point = _smartAnalysisPoints[i];
      final position = point['position'] as Offset;
      final distance = (tapPoint - position).distance;
      
      if (distance <= clickRadius) {
        return i;
      }
    }
    
    return null;
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
            _analysisResults.insert(0, result);
          });
          // 触发 AnimatedList 插入动画
          _listKey.currentState?.insertItem(0);
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



  /// 高级肤色分析算法 - 进阶版
  SkinColorResult _analyzeSkinTone(Color color, Offset position, String label) {
  final r = color.red;
  final g = color.green;
  final b = color.blue;

  // 色彩空间转换
  final hsv = HSVColor.fromColor(color);
  final labColor = ColorSpaceConverter.rgbToLab(r, g, b);
  final ycbcrColor = ColorSpaceConverter.rgbToYCbCr(r, g, b);

  // 指标
  final hue = hsv.hue;
  final saturation = hsv.saturation;
  final value = hsv.value;
  final L = labColor[0];
  final a = labColor[1];
  final bLab = labColor[2];
  final Y = ycbcrColor[0];
  final Cb = ycbcrColor[1];
  final Cr = ycbcrColor[2];

  // 置信度
  final skinConfidence = ColorSpaceConverter.calculateSkinConfidence(ycbcrColor);

  // ITA
  final ita = (Math.atan((L - 50) / bLab) * 180 / Math.pi).toDouble();

  // 分类
  final skinCategory = SkinToneClassifier.classify(ita);

  // 冷暖
  final warmScore = _calculateWarmScore(hue, a, bLab, Cr);
  final coolScore = _calculateCoolScore(hue, a, bLab, Cb);
  final warmCoolType = TemperatureAnalyzer.analyze(warmScore, coolScore);

  // 偏色
  final colorBias = ColorBiasAnalyzer.analyze(a, bLab);

  // 高级指标
  final advancedMetrics = AdvancedMetricsBuilder.build(
  ita: ita,
  skinConfidence: skinConfidence,
  warmScore: warmScore,
  coolScore: coolScore,
  a: a,
  bLab: bLab,
  saturation: saturation,
  value: value,
  L: L,
  );

  return SkinColorResult(
  id: DateTime.now().millisecondsSinceEpoch.toString(),
  position: position,
  averageColor: color,
  rgbValue: 'RGB($r, $g, $b)',
  hsvValue: 'HSV(${hue.round()}°, ${(saturation * 100).round()}%, ${(value * 100).round()}%)',
  hexValue: '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
  labValue: 'LAB(${L.toStringAsFixed(1)}, ${a.toStringAsFixed(1)}, ${bLab.toStringAsFixed(1)})',
  ycbcrValue: 'YCbCr(${Y.toStringAsFixed(0)}, ${Cb.toStringAsFixed(0)}, ${Cr.toStringAsFixed(0)})',
  toneType: skinCategory.tone,
  warmCoolType: warmCoolType,
  colorBias: colorBias,
  skinCategory: skinCategory.name,
  confidence: skinConfidence,
  emoji: skinCategory.emoji,
  createdAt: DateTime.now(),
  advancedMetrics: advancedMetrics,
  );
  }

  
  /// 计算暖色调评分
  double _calculateWarmScore(double hue, double a, double b_lab, double cr) {
    double score = 0.0;
    
    // 色相评分 (黄色-橙色-红色范围)
    if (hue >= 15 && hue <= 60) {
      score += 0.4; // 黄橙色范围
    } else if (hue >= 340 || hue <= 15) {
      score += 0.3; // 红色范围
    }
    
    // Lab空间b*值评分 (正值表示黄色倾向)
    if (b_lab > 10) {
      score += 0.3 * (b_lab / 30.0).clamp(0.0, 1.0);
    }
    
    // YCbCr空间Cr值评分 (高Cr值表示红色倾向)
    if (cr > 128) {
      score += 0.3 * ((cr - 128) / 45.0).clamp(0.0, 1.0);
    }
    
    return score.clamp(0.0, 1.0);
  }
  
  /// 计算冷色调评分
  double _calculateCoolScore(double hue, double a, double b_lab, double cb) {
    double score = 0.0;
    
    // 色相评分 (蓝色-紫色-粉色范围)
    if (hue >= 180 && hue <= 270) {
      score += 0.4; // 蓝紫色范围
    } else if (hue >= 270 && hue <= 340) {
      score += 0.3; // 紫粉色范围
    }
    
    // Lab空间a*值评分 (负值表示绿色倾向，正值但较小表示粉色倾向)
    if (a < 0) {
      score += 0.2;
    } else if (a > 0 && a < 8 && b_lab < 5) {
      score += 0.2; // 轻微粉色倾向
    }
    
    // YCbCr空间Cb值评分 (高Cb值表示蓝色倾向)
    if (cb > 128) {
      score += 0.4 * ((cb - 128) / 50.0).clamp(0.0, 1.0);
    }
    
    return score.clamp(0.0, 1.0);
  }
  
  /// RGB转Lab色彩空间 - 用于更精确的肤色分析
  List<double> _rgbToLab(int r, int g, int b_value) {
    // 转换为标准RGB
    double r_linear = r / 255.0;
    double g_linear = g / 255.0;
    double b_linear = b_value / 255.0;
    
    // sRGB到线性RGB的转换
    r_linear = r_linear <= 0.04045 ? r_linear / 12.92 : (Math.pow((r_linear + 0.055) / 1.055, 2.4) as double);
    g_linear = g_linear <= 0.04045 ? g_linear / 12.92 : (Math.pow((g_linear + 0.055) / 1.055, 2.4) as double);
    b_linear = b_linear <= 0.04045 ? b_linear / 12.92 : (Math.pow((b_linear + 0.055) / 1.055, 2.4) as double);
    
    // 线性RGB到XYZ的转换
    double x = r_linear * 0.4124 + g_linear * 0.3576 + b_linear * 0.1805;
    double y = r_linear * 0.2126 + g_linear * 0.7152 + b_linear * 0.0722;
    double z = r_linear * 0.0193 + g_linear * 0.1192 + b_linear * 0.9505;
    
    // XYZ到Lab的转换
    // 参考白点D65
    const xn = 0.95047;
    const yn = 1.0;
    const zn = 1.08883;
    
    x = x / xn;
    y = y / yn;
    z = z / zn;
    
    x = x > 0.008856 ? (Math.pow(x, 1/3) as double) : (7.787 * x) + (16 / 116);
    y = y > 0.008856 ? (Math.pow(y, 1/3) as double) : (7.787 * y) + (16 / 116);
    z = z > 0.008856 ? (Math.pow(z, 1/3) as double) : (7.787 * z) + (16 / 116);
    
    final L = (116 * y) - 16;
    final a = 500 * (x - y);
    final b_component = 200 * (y - z);
    
    return [L, a, b_component];
  }

  /// 清除所有分析结果
  void _clearResults() {
    setState(() {
      _analysisResults.clear();
    });
  }

  /// 删除指定分析结果
  void _removeResult(String id) {
    // 找到要删除的项目索引
    final index = _analysisResults.indexWhere((result) => result.id == id);
    if (index == -1) return;
    
    final removedItem = _analysisResults[index];
    
    // 触发 AnimatedList 删除动画
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildAnimatedResultCard(removedItem, index, animation),
      duration: const Duration(milliseconds: 300),
    );
    
    // 从数据源中移除
    setState(() {
      _analysisResults.removeAt(index);
    });
    
    // 显示删除反馈和撤销选项
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除颜色 ${removedItem.colorBias}'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            setState(() {
              _analysisResults.insert(index, removedItem);
            });
            _listKey.currentState?.insertItem(index);
          },
        ),
      ),
    );
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
                            icon: Icons.auto_awesome_rounded,
                            label: '智能',
                            mode: AnalysisMode.smartAnalysis,
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
            // 先更新模式状态
            final previousMode = _analysisMode;
            setState(() {
              _analysisMode = mode;
              // 切换模式时清理状态
              _isSelectingRect = false;
              _rectStartPoint = null;
              _currentDragPoint = null;
            });
            
            // 根据模式执行相应的分析
            if (_selectedImage != null) {
              if (mode == AnalysisMode.faceDetection) {
                // 切换到人脸模式，清除智能分析数据
                setState(() {
                  _smartAnalysisPoints.clear();
                });
                _performFaceDetection();
              } else if (mode == AnalysisMode.smartAnalysis) {
                // 切换到智能模式，清除人脸检测数据并启动扫描动画
                setState(() {
                  _detectedFaces.clear();
                  _rectStartPoint = null;
                  _currentDragPoint = null;
                });
                // 无论是否是首次切换，都启动扫描动画
                _startSmartAnalysisWithAnimation();
              } else {
                // 切换到手动模式，清除所有检测数据
                setState(() {
                  _detectedFaces.clear();
                  _smartAnalysisPoints.clear();
                  if (mode == AnalysisMode.manualRect) {
                    _rectStartPoint = null;
                    _currentDragPoint = null;
                  }
                });
              }
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
      {'icon': '🤖', 'text': '智能提取图片主色调'},
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
                  onPanStart: _onPanStart,
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
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _rectAnimationController, 
                              _handleAnimationController,
                              _scanAnimationController,
                              _colorPointAnimationController,
                            ]),
                            builder: (context, child) {
                              return CustomPaint(
                                painter: AnalysisPainter(
                                  detectedFaces: _detectedFaces,
                                  imageSize: _imageSize,
                                  displaySize: _displaySize,
                                  rectStartPoint: _rectStartPoint,
                                  currentDragPoint: _currentDragPoint,
                                  isSelectingRect: _isSelectingRect,
                                  isDraggingHandle: _isDraggingHandle,
                                  draggingHandleIndex: _draggingHandleIndex,
                                  isHoveringHandle: _isHoveringHandle,
                                  hoveringHandleIndex: _hoveringHandleIndex,
                                  analysisMode: _analysisMode,
                                  rectAnimation: _rectAnimationController,
                                  handleAnimation: _handleAnimationController,
                                  scanAnimation: _scanAnimationController,
                                  colorPointAnimation: _colorPointAnimationController,
                                  smartAnalysisPoints: _smartAnalysisPoints,
                                  isShowingScanAnimation: _isShowingScanAnimation,
                                  selectedColorPointIndex: _selectedColorPointIndex,
                                  showFaceContours: _showFaceContours,
                                  faceContourPaths: _faceContourPaths,
                                  faceContourAnimation: _faceContourAnimation,
                                  landmarkAnimation: _landmarkAnimation,
                                  isDrawingContours: _isDrawingContours,
                                  // 长按拖拽相关参数
                                  isDraggingRegion: _isDraggingRegion,
                                  draggingRegionIndex: _draggingRegionIndex,
                                  dragOffset: _dragOffset,
                                ),
                              );
                            },
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
    return AnimatedList(
      key: _listKey,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      initialItemCount: _analysisResults.length,
      itemBuilder: (context, index, animation) {
        if (index >= _analysisResults.length) return const SizedBox.shrink();
        final result = _analysisResults[index];
        return _buildAnimatedResultCard(result, index, animation);
      },
    );
  }

  /// 构建动画结果卡片
  Widget _buildAnimatedResultCard(SkinColorResult result, int index, Animation<double> animation) {
    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(1.0, 0.0), // 从右侧滑入
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: FadeTransition(
        opacity: animation,
        child: _buildResultCard(result, index),
      ),
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
  final bool isDraggingHandle;
  final int? draggingHandleIndex;
  final bool isHoveringHandle;
  final int? hoveringHandleIndex;
  final AnalysisMode analysisMode;
  final Animation<double>? rectAnimation;
  final Animation<double>? handleAnimation;
  final Animation<double>? scanAnimation;
  final Animation<double>? colorPointAnimation;
  final List<Map<String, dynamic>> smartAnalysisPoints;
  final bool isShowingScanAnimation;
  final int? selectedColorPointIndex;
  
  // 人脸轮廓相关
  final bool showFaceContours;
  final List<Map<String, dynamic>> faceContourPaths;
  final Animation<double>? faceContourAnimation;
  final Animation<double>? landmarkAnimation;
  final bool isDrawingContours;
  
  // 长按拖拽相关
  final bool isDraggingRegion;
  final int? draggingRegionIndex;
  final Offset? dragOffset;

  AnalysisPainter({
    required this.detectedFaces,
    this.imageSize,
    this.displaySize,
    this.rectStartPoint,
    this.currentDragPoint,
    this.isSelectingRect = false,
    this.isDraggingHandle = false,
    this.draggingHandleIndex,
    this.isHoveringHandle = false,
    this.hoveringHandleIndex,
    required this.analysisMode,
    this.rectAnimation,
    this.handleAnimation,
    this.scanAnimation,
    this.colorPointAnimation,
    this.smartAnalysisPoints = const [],
    this.isShowingScanAnimation = false,
    this.selectedColorPointIndex,
    this.showFaceContours = false,
    this.faceContourPaths = const [],
    this.faceContourAnimation,
    this.landmarkAnimation,
    this.isDrawingContours = false,
    // 长按拖拽相关参数
    this.isDraggingRegion = false,
    this.draggingRegionIndex,
    this.dragOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null || displaySize == null) return;

    final scaleX = size.width / imageSize!.width;
    final scaleY = size.height / imageSize!.height;

    // 绘制人脸轮廓和关键点
    if (analysisMode == AnalysisMode.faceDetection && showFaceContours && faceContourPaths.isNotEmpty) {
      _drawFaceContours(canvas, size, scaleX, scaleY);
    }
    
    // 绘制传统人脸框（作为备选）
    if (analysisMode == AnalysisMode.faceDetection && detectedFaces.isNotEmpty && !showFaceContours) {
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

    // 绘制智能分析模式的效果
    if (analysisMode == AnalysisMode.smartAnalysis) {
      if (isShowingScanAnimation && scanAnimation != null) {
        // 绘制扫描动画
        _drawScanAnimation(canvas, size, scanAnimation!);
      } else {
        // 绘制颜色指示点
        _drawSmartAnalysisPoints(canvas, size);
      }
    }

    // 绘制框选区域
    if (isSelectingRect && rectStartPoint != null && currentDragPoint != null) {
      final rect = Rect.fromPoints(rectStartPoint!, currentDragPoint!);
      
      // 动画透明度
      double animationOpacity = 1.0;
      if (rectAnimation != null) {
        animationOpacity = 0.3 + 0.7 * rectAnimation!.value;
      }
      
      final rectPaint = Paint()
        ..color = MorandiTheme.accentPink.withOpacity(animationOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      final rectFillPaint = Paint()
        ..color = MorandiTheme.accentPink.withOpacity(0.15 * animationOpacity)
        ..style = PaintingStyle.fill;

      // 绘制选择区域
      canvas.drawRect(rect, rectFillPaint);
      _drawDashedRect(canvas, rect, rectPaint);
      
      // 只在有效矩形区域时显示尺寸（避免显示0×0）
      final width = rect.width.abs().toInt();
      final height = rect.height.abs().toInt();
      if (width > 5 && height > 5) {
        // 添加背景以提高文字可读性
        final textBg = Paint()
          ..color = Colors.black.withOpacity(0.6 * animationOpacity)
          ..style = PaintingStyle.fill;
        
        final textRect = Rect.fromCenter(
          center: rect.center,
          width: 80,
          height: 24,
        );
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(textRect, const Radius.circular(12)),
          textBg,
        );
        
        _drawText(canvas, '${width}×${height}', rect.center, Colors.white.withOpacity(animationOpacity));
      }
      
      // 绘制角落指示器
      _drawCornerIndicators(canvas, rect, animationOpacity);
    }
    
    // 绘制已完成的矩形选择区域（带拖拽控制点）
    if (!isSelectingRect && rectStartPoint != null && currentDragPoint != null) {
      var startPoint = rectStartPoint!;
      var dragPoint = currentDragPoint!;
      
      // 应用拖拽偏移
      if (isDraggingRegion && draggingRegionIndex == 0 && dragOffset != null) {
        startPoint = startPoint + dragOffset!;
        dragPoint = dragPoint + dragOffset!;
      }
      
      final completedRect = Rect.fromPoints(startPoint, dragPoint);
      
      // 拖拽状态下的特殊视觉效果
      final isDragging = isDraggingRegion && draggingRegionIndex == 0;
      final strokeColor = isDragging ? Colors.cyanAccent : MorandiTheme.warmTone;
      final fillOpacity = isDragging ? 0.2 : 0.12;
      final strokeWidth = isDragging ? 3.0 : 2.0;
      
      final completedRectPaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      final completedFillPaint = Paint()
        ..color = strokeColor.withOpacity(fillOpacity)
        ..style = PaintingStyle.fill;

      // 绘制阴影
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.1)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      
      canvas.drawRect(completedRect.shift(const Offset(2, 2)), shadowPaint);
      
      // 绘制完成的选择区域
      canvas.drawRect(completedRect, completedFillPaint);
      canvas.drawRect(completedRect, completedRectPaint);
      
      // 绘制拖拽控制点
      _drawDragHandles(canvas, completedRect);
      
      // 绘制区域标签
      _drawText(canvas, '已选择区域', completedRect.topCenter + const Offset(0, -20), MorandiTheme.primaryText);
    }
  }

  /// 绘制人脸轮廓和关键点
  void _drawFaceContours(Canvas canvas, Size size, double scaleX, double scaleY) {
    final contourProgress = faceContourAnimation?.value ?? 1.0;
    final landmarkProgress = landmarkAnimation?.value ?? 1.0;
    
    for (final faceData in faceContourPaths) {
      final contours = faceData['contours'] as List<Map<String, dynamic>>;
      final landmarks = faceData['landmarks'] as List<Map<String, dynamic>>;
      
      // 绘制轮廓线条
      for (final contour in contours) {
        final points = contour['points'] as List<Offset>;
        final color = contour['color'] as Color;
        final strokeWidth = contour['strokeWidth'] as double;
        final animationDelay = contour['animationDelay'] as int;
        
        // 计算当前轮廓的动画进度
        final delayProgress = (contourProgress * 2000 - animationDelay) / 500;
        final currentProgress = (delayProgress).clamp(0.0, 1.0);
        
        if (currentProgress > 0 && points.length > 1) {
          _drawAnimatedContourPath(canvas, points, color, strokeWidth, currentProgress, scaleX, scaleY);
        }
      }
      
      // 绘制关键点
      for (final landmark in landmarks) {
        final position = landmark['position'] as Math.Point<int>;
        final color = landmark['color'] as Color;
        final pointSize = landmark['size'] as double;
        final animationDelay = landmark['animationDelay'] as int;
        
        // 计算关键点的动画进度
        final delayProgress = (landmarkProgress * 800 - (animationDelay - 1200)) / 200;
        final currentProgress = (delayProgress).clamp(0.0, 1.0);
        
        if (currentProgress > 0) {
          _drawAnimatedLandmark(canvas, position, color, pointSize, currentProgress, scaleX, scaleY);
        }
      }
      
      // 绘制扫描效果
      if (isDrawingContours) {
        _drawFaceScanEffect(canvas, faceData['boundingBox'] as Rect, scaleX, scaleY);
      }
    }
  }
  
  /// 绘制电影级AI轮廓路径
  void _drawAnimatedContourPath(Canvas canvas, List<Offset> points, Color color, 
      double strokeWidth, double progress, double scaleX, double scaleY) {
    if (points.length < 2) return;
    
    final path = Path();
    final totalPoints = points.length;
    final visiblePoints = (totalPoints * progress).round();
    
    if (visiblePoints > 0) {
      // 构建路径
      final firstPoint = Offset(points[0].dx * scaleX, points[0].dy * scaleY);
      path.moveTo(firstPoint.dx, firstPoint.dy);
      
      for (int i = 1; i < visiblePoints && i < points.length; i++) {
        final point = Offset(points[i].dx * scaleX, points[i].dy * scaleY);
        path.lineTo(point.dx, point.dy);
      }
      
      // 添加部分线段动画
      if (visiblePoints < totalPoints && visiblePoints > 0) {
        final lastCompleteIndex = visiblePoints - 1;
        final nextIndex = visiblePoints;
        if (nextIndex < points.length) {
          final lastPoint = Offset(points[lastCompleteIndex].dx * scaleX, 
                                 points[lastCompleteIndex].dy * scaleY);
          final nextPoint = Offset(points[nextIndex].dx * scaleX, 
                                 points[nextIndex].dy * scaleY);
          
          final segmentProgress = (totalPoints * progress) - visiblePoints + 1;
          final partialPoint = Offset(
            lastPoint.dx + (nextPoint.dx - lastPoint.dx) * segmentProgress,
            lastPoint.dy + (nextPoint.dy - lastPoint.dy) * segmentProgress,
          );
          path.lineTo(partialPoint.dx, partialPoint.dy);
        }
      }
      
      // 多层发光效果 - 外层大光晕
      final outerGlowPaint = Paint()
        ..color = color.withOpacity(0.1)
        ..strokeWidth = strokeWidth * 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawPath(path, outerGlowPaint);
      
      // 中层光晕
      final midGlowPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..strokeWidth = strokeWidth * 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(path, midGlowPaint);
      
      // 内层强光
      final innerGlowPaint = Paint()
        ..color = color.withOpacity(0.6)
        ..strokeWidth = strokeWidth * 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawPath(path, innerGlowPaint);
      
      // 主线条 - 渐变效果
      final mainPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            color.withOpacity(0.8),
            Colors.white.withOpacity(0.9),
            color.withOpacity(0.8),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(path.getBounds())
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, mainPaint);
      
      // 动态扫描线效果
      if (progress < 1.0) {
        _drawScanningEffect(canvas, path, color, progress);
      }
      
      // 绘制节点光点
      _drawPathNodes(canvas, points, color, progress, scaleX, scaleY, visiblePoints);
    }
  }
  
  /// 绘制扫描线效果
  void _drawScanningEffect(Canvas canvas, Path path, Color color, double progress) {
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final scanPosition = metric.length * progress;
      final tangent = metric.getTangentForOffset(scanPosition);
      if (tangent != null) {
        final scanPoint = tangent.position;
        
        // 扫描光点
        final scanPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(scanPoint, 4, scanPaint);
        
        // 扫描尾迹
        final trailPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withOpacity(0.8),
              color.withOpacity(0.4),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 1.0],
          ).createShader(Rect.fromCircle(center: scanPoint, radius: 15))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(scanPoint, 15, trailPaint);
      }
    }
  }
  
  /// 绘制路径节点
  void _drawPathNodes(Canvas canvas, List<Offset> points, Color color, 
      double progress, double scaleX, double scaleY, int visiblePoints) {
    for (int i = 0; i < visiblePoints && i < points.length; i++) {
      final point = Offset(points[i].dx * scaleX, points[i].dy * scaleY);
      final nodeProgress = (i / points.length).clamp(0.0, progress);
      
      if (nodeProgress > 0) {
        // 节点外圈
        final nodePaint = Paint()
          ..color = color.withOpacity(0.3 * nodeProgress)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawCircle(point, 3 * nodeProgress, nodePaint);
        
        // 节点核心
        final corePaint = Paint()
          ..color = Colors.white.withOpacity(0.9 * nodeProgress)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, 1.5 * nodeProgress, corePaint);
      }
    }
  }
  
  /// 绘制电影级AI关键点
  void _drawAnimatedLandmark(Canvas canvas, Math.Point<int> position, Color color, 
      double size, double progress, double scaleX, double scaleY) {
    final center = Offset(position.x.toDouble() * scaleX, position.y.toDouble() * scaleY);
    final animatedSize = size * progress;
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
    
    // 多层光晕效果
    // 外层脉冲光晕
    final pulseRadius = animatedSize * (3 + Math.sin(time * 3) * 0.5);
    final pulsePaint = Paint()
      ..color = color.withOpacity(0.1 * progress * (0.5 + Math.sin(time * 3) * 0.3))
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, pulseRadius, pulsePaint);
    
    // 中层稳定光晕
    final midGlowPaint = Paint()
      ..color = color.withOpacity(0.3 * progress)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, animatedSize * 2.5, midGlowPaint);
    
    // 内层强光
    final innerGlowPaint = Paint()
      ..color = color.withOpacity(0.6 * progress)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center, animatedSize * 1.5, innerGlowPaint);
    
    // 主圆环 - 渐变效果
    final ringPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          color.withOpacity(0.8 * progress),
          Colors.white.withOpacity(0.9 * progress),
          color.withOpacity(0.8 * progress),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: animatedSize))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, animatedSize, ringPaint);
    
    // 核心亮点
    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.95 * progress)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, animatedSize * 0.3, corePaint);
    
    // 旋转光束效果
    _drawRotatingBeams(canvas, center, animatedSize, color, progress, time);
    
    // 数据流效果
    _drawDataStream(canvas, center, animatedSize, color, progress, time);
  }
  
  /// 绘制旋转光束效果
  void _drawRotatingBeams(Canvas canvas, Offset center, double size, Color color, double progress, double time) {
    final beamCount = 4;
    final beamLength = size * 2;
    
    for (int i = 0; i < beamCount; i++) {
      final angle = (time * 2 + i * Math.pi / 2) % (Math.pi * 2);
      final startRadius = size * 0.8;
      final endRadius = startRadius + beamLength;
      
      final startX = center.dx + Math.cos(angle) * startRadius;
      final startY = center.dy + Math.sin(angle) * startRadius;
      final endX = center.dx + Math.cos(angle) * endRadius;
      final endY = center.dy + Math.sin(angle) * endRadius;
      
      final beamPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withOpacity(0.8 * progress),
            Colors.white.withOpacity(0.6 * progress),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 1.0],
        ).createShader(Rect.fromPoints(Offset(startX, startY), Offset(endX, endY)))
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), beamPaint);
    }
  }
  
  /// 绘制数据流效果
  void _drawDataStream(Canvas canvas, Offset center, double size, Color color, double progress, double time) {
    final particleCount = 8;
    final radius = size * 1.5;
    
    for (int i = 0; i < particleCount; i++) {
      final angle = (time * 1.5 + i * Math.pi * 2 / particleCount) % (Math.pi * 2);
      final particleRadius = radius + Math.sin(time * 3 + i) * 10;
      
      final x = center.dx + Math.cos(angle) * particleRadius;
      final y = center.dy + Math.sin(angle) * particleRadius;
      
      final particleSize = 2 + Math.sin(time * 4 + i) * 1;
      
      final particlePaint = Paint()
        ..color = color.withOpacity(0.7 * progress * (0.5 + Math.sin(time * 2 + i) * 0.5))
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
      
      canvas.drawCircle(Offset(x, y), particleSize, particlePaint);
      
      // 连接线
      if (i > 0) {
        final prevAngle = (time * 1.5 + (i-1) * Math.pi * 2 / particleCount) % (Math.pi * 2);
        final prevRadius = radius + Math.sin(time * 3 + (i-1)) * 10;
        final prevX = center.dx + Math.cos(prevAngle) * prevRadius;
        final prevY = center.dy + Math.sin(prevAngle) * prevRadius;
        
        final linePaint = Paint()
          ..color = color.withOpacity(0.3 * progress)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
        
        canvas.drawLine(Offset(prevX, prevY), Offset(x, y), linePaint);
      }
    }
  }
  
  /// 绘制电影级AI人脸扫描效果
  void _drawFaceScanEffect(Canvas canvas, Rect boundingBox, double scaleX, double scaleY) {
    final scaledRect = Rect.fromLTRB(
      boundingBox.left * scaleX,
      boundingBox.top * scaleY,
      boundingBox.right * scaleX,
      boundingBox.bottom * scaleY,
    );
    
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
    
    // 主扫描框 - 多层发光
    _drawGlowingRect(canvas, scaledRect, Colors.cyanAccent, time);
    
    // 动态四角标记
    _drawCornerMarkers(canvas, scaledRect, time);
    
    // 扫描线动画
    _drawScanLines(canvas, scaledRect, time);
    
    // 数据网格
    _drawDataGrid(canvas, scaledRect, time);
    
    // 边缘粒子效果
    _drawEdgeParticles(canvas, scaledRect, time);
    
    // HUD信息显示
    _drawHUDInfo(canvas, scaledRect, time);
  }
  
  /// 绘制发光矩形框
  void _drawGlowingRect(Canvas canvas, Rect rect, Color color, double time) {
    // 外层大光晕
    final outerGlowPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRect(rect, outerGlowPaint);
    
    // 中层光晕
    final midGlowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRect(rect, midGlowPaint);
    
    // 主框线 - 脉冲效果
    final pulseOpacity = 0.6 + Math.sin(time * 4) * 0.3;
    final mainPaint = Paint()
      ..color = color.withOpacity(pulseOpacity)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, mainPaint);
  }
  
  /// 绘制动态四角标记
  void _drawCornerMarkers(Canvas canvas, Rect rect, double time) {
    final cornerLength = 25.0 + Math.sin(time * 3) * 5;
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    
    // 左上角
    canvas.drawLine(
      Offset(rect.left - 5, rect.top),
      Offset(rect.left + cornerLength, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top - 5),
      Offset(rect.left, rect.top + cornerLength),
      cornerPaint,
    );
    
    // 右上角
    canvas.drawLine(
      Offset(rect.right + 5, rect.top),
      Offset(rect.right - cornerLength, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top - 5),
      Offset(rect.right, rect.top + cornerLength),
      cornerPaint,
    );
    
    // 左下角
    canvas.drawLine(
      Offset(rect.left - 5, rect.bottom),
      Offset(rect.left + cornerLength, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom + 5),
      Offset(rect.left, rect.bottom - cornerLength),
      cornerPaint,
    );
    
    // 右下角
    canvas.drawLine(
      Offset(rect.right + 5, rect.bottom),
      Offset(rect.right - cornerLength, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom + 5),
      Offset(rect.right, rect.bottom - cornerLength),
      cornerPaint,
    );
  }
  
  /// 绘制扫描线动画
  void _drawScanLines(Canvas canvas, Rect rect, double time) {
    final scanY = rect.top + (rect.height * ((time * 0.5) % 1.0));
    
    // 主扫描线
    final scanPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.cyanAccent.withOpacity(0.8),
          Colors.white.withOpacity(0.9),
          Colors.cyanAccent.withOpacity(0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(rect.left, scanY - 2, rect.width, 4))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(
      Offset(rect.left, scanY),
      Offset(rect.right, scanY),
      scanPaint,
    );
    
    // 扫描线光晕
    final glowPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.3)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    
    canvas.drawLine(
      Offset(rect.left, scanY),
      Offset(rect.right, scanY),
      glowPaint,
    );
  }
  
  /// 绘制数据网格
  void _drawDataGrid(Canvas canvas, Rect rect, double time) {
    final gridPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.2)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    
    final gridSpacing = 20.0;
    
    // 垂直网格线
    for (double x = rect.left; x <= rect.right; x += gridSpacing) {
      final opacity = 0.1 + Math.sin(time * 2 + x * 0.1) * 0.1;
      gridPaint.color = Colors.cyanAccent.withOpacity(opacity);
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        gridPaint,
      );
    }
    
    // 水平网格线
    for (double y = rect.top; y <= rect.bottom; y += gridSpacing) {
      final opacity = 0.1 + Math.sin(time * 2 + y * 0.1) * 0.1;
      gridPaint.color = Colors.cyanAccent.withOpacity(opacity);
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        gridPaint,
      );
    }
  }
  
  /// 绘制边缘粒子效果
  void _drawEdgeParticles(Canvas canvas, Rect rect, double time) {
    final particleCount = 12;
    final perimeter = 2 * (rect.width + rect.height);
    
    for (int i = 0; i < particleCount; i++) {
      final progress = ((time * 0.3 + i / particleCount) % 1.0);
      final distance = progress * perimeter;
      
      Offset position;
      if (distance < rect.width) {
        // 顶边
        position = Offset(rect.left + distance, rect.top);
      } else if (distance < rect.width + rect.height) {
        // 右边
        position = Offset(rect.right, rect.top + (distance - rect.width));
      } else if (distance < 2 * rect.width + rect.height) {
        // 底边
        position = Offset(rect.right - (distance - rect.width - rect.height), rect.bottom);
      } else {
        // 左边
        position = Offset(rect.left, rect.bottom - (distance - 2 * rect.width - rect.height));
      }
      
      final particlePaint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      
      canvas.drawCircle(position, 2, particlePaint);
      
      // 粒子尾迹
      final trailPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.4)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      
      canvas.drawCircle(position, 4, trailPaint);
    }
  }
  
  /// 绘制HUD信息
  void _drawHUDInfo(Canvas canvas, Rect rect, double time) {
    // 状态指示器
    final statusPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.8 + Math.sin(time * 6) * 0.2)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(rect.right - 15, rect.top - 15),
      3,
      statusPaint,
    );
    
    // 进度条
    final progressWidth = 60.0;
    final progressHeight = 4.0;
    final progressRect = Rect.fromLTWH(
      rect.left,
      rect.bottom + 10,
      progressWidth,
      progressHeight,
    );
    
    // 进度条背景
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(progressRect, bgPaint);
    
    // 进度条填充
    final progress = (time * 0.5) % 1.0;
    final fillRect = Rect.fromLTWH(
      progressRect.left,
      progressRect.top,
      progressRect.width * progress,
      progressRect.height,
    );
    
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.cyanAccent,
          Colors.white,
          Colors.cyanAccent,
        ],
      ).createShader(fillRect)
      ..style = PaintingStyle.fill;
    canvas.drawRect(fillRect, fillPaint);
  }

  /// 绘制拖拽控制点
  void _drawDragHandles(Canvas canvas, Rect rect) {
    const baseHandleRadius = 8.0;
    const hoverHandleRadius = 12.0;
    const activeHandleRadius = 10.0;
    
    // 四个角的控制点
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    
    for (int i = 0; i < corners.length; i++) {
      final corner = corners[i];
      
      // 根据状态确定控制点大小和颜色
      double handleRadius = baseHandleRadius;
      Color handleColor = MorandiTheme.warmTone;
      Color strokeColor = Colors.white;
      double strokeWidth = 2.0;
      
      if (isDraggingHandle && draggingHandleIndex == i) {
        // 正在拖拽的控制点
        handleRadius = activeHandleRadius;
        handleColor = MorandiTheme.accentPink;
        strokeWidth = 3.0;
        
        // 应用动画缩放
        if (handleAnimation != null) {
          handleRadius *= (1.0 + handleAnimation!.value * 0.3);
        }
      } else if (isHoveringHandle && hoveringHandleIndex == i) {
        // 悬停状态的控制点
        handleRadius = hoverHandleRadius;
        handleColor = MorandiTheme.coolTone;
        strokeWidth = 2.5;
      }
      
      final handlePaint = Paint()
        ..color = handleColor
        ..style = PaintingStyle.fill;
        
      final handleStrokePaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      
      // 绘制阴影
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      
      canvas.drawCircle(corner + const Offset(1, 1), handleRadius, shadowPaint);
      
      // 绘制控制点
      canvas.drawCircle(corner, handleRadius, handlePaint);
      canvas.drawCircle(corner, handleRadius, handleStrokePaint);
      
      // 为活跃的控制点添加脉冲效果
      if (isDraggingHandle && draggingHandleIndex == i && handleAnimation != null) {
        final pulsePaint = Paint()
          ..color = MorandiTheme.accentPink.withOpacity(0.3 * (1.0 - handleAnimation!.value))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        
        canvas.drawCircle(corner, handleRadius + handleAnimation!.value * 8, pulsePaint);
      }
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

  /// 绘制角落指示器
  void _drawCornerIndicators(Canvas canvas, Rect rect, double opacity) {
    const indicatorLength = 20.0;
    const indicatorWidth = 3.0;
    
    final indicatorPaint = Paint()
      ..color = MorandiTheme.accentPink.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = indicatorWidth
      ..strokeCap = StrokeCap.round;
    
    // 四个角的L形指示器
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    
    final directions = [
      [const Offset(1, 0), const Offset(0, 1)],   // 右、下
      [const Offset(-1, 0), const Offset(0, 1)],  // 左、下
      [const Offset(1, 0), const Offset(0, -1)],  // 右、上
      [const Offset(-1, 0), const Offset(0, -1)], // 左、上
    ];
    
    for (int i = 0; i < corners.length; i++) {
      final corner = corners[i];
      final dirs = directions[i];
      
      // 绘制水平线
      canvas.drawLine(
        corner,
        corner + dirs[0] * indicatorLength,
        indicatorPaint,
      );
      
      // 绘制垂直线
      canvas.drawLine(
        corner,
        corner + dirs[1] * indicatorLength,
        indicatorPaint,
      );
    }
  }

  /// 绘制扫描动画
  void _drawScanAnimation(Canvas canvas, Size size, Animation<double> animation) {
    final progress = animation.value;

    // 扫描线位置
    final scanY = size.height * progress;

    // 扫描线效果
    final scanLinePaint = Paint()
      ..color = MorandiTheme.coolTone.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(size.width, 0),
        [
          MorandiTheme.coolTone.withOpacity(0.0),
          MorandiTheme.coolTone.withOpacity(0.8),
          MorandiTheme.coolTone.withOpacity(0.0),
        ],
        [0.0, 0.5, 1.0],
      );

    // 绘制横向扫描线
    canvas.drawLine(
      Offset(0, scanY),
      Offset(size.width, scanY),
      scanLinePaint,
    );

    // 网格扫描效果
    final gridPaint = Paint()
      ..color = MorandiTheme.neutralTone.withOpacity(0.3 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final gridSize = 30.0;
    final scannedHeight = size.height * progress;

    // 已扫描区域网格
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, scannedHeight), gridPaint);
    }
    for (double y = 0; y <= scannedHeight; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 扫描进度文字
    final progressText = '扫描中... ${(progress * 100).toInt()}%';
    _drawText(canvas, progressText, Offset(size.width / 2, scanY - 30), MorandiTheme.primaryText);

    // 扫描光晕效果
    final glowPaint = Paint()
      ..color = MorandiTheme.coolTone.withOpacity(0.2)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawRect(Rect.fromLTWH(0, scanY - 5, size.width, 10), glowPaint);
  }

  /// 绘制智能分析颜色指示点
  void _drawSmartAnalysisPoints(Canvas canvas, Size size) {
    if (smartAnalysisPoints.isEmpty) return;
    
    final animationValue = colorPointAnimation?.value ?? 1.0;
    
    for (int i = 0; i < smartAnalysisPoints.length; i++) {
      final point = smartAnalysisPoints[i];
      var position = point['position'] as Offset;
      final result = point['result'] as SkinColorResult;
      final isSkinTone = point['isSkinTone'] as bool;

      // ✅ 统一用 result.hexValue 取色
      final color = Color(int.parse(result.hexValue.replaceFirst('#', '0xff')));

      // 应用拖拽偏移
      final regionIndex = i + 1;
      if (isDraggingRegion && draggingRegionIndex == regionIndex && dragOffset != null) {
        position = position + dragOffset!;
      }
      
      // 延迟动画，让指示点依次出现
      final delayedAnimation = ((animationValue - (i * 0.1)).clamp(0.0, 1.0) / 0.9).clamp(0.0, 1.0);
      
      if (delayedAnimation > 0) {
        // 拖拽状态下的特殊效果
        final isDragging = isDraggingRegion && draggingRegionIndex == regionIndex;
        final dragScale = isDragging ? 1.3 : 1.0;
        final dragOpacity = isDragging ? 1.0 : delayedAnimation;
        
        // 指示点大小
        final pointRadius = 12.0 * delayedAnimation * dragScale;
        final ringRadius = 20.0 * delayedAnimation * dragScale;
        
        // 绘制外圈（呼吸效果）
        final breathingScale = 1.0 + 0.2 * Math.sin(DateTime.now().millisecondsSinceEpoch / 500.0);
        final ringColor = isDragging ? Colors.cyanAccent : (isSkinTone ? MorandiTheme.warmTone : MorandiTheme.coolTone);
        final outerRingPaint = Paint()
          ..color = ringColor.withOpacity(0.3 * dragOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isDragging ? 3.0 : 2.0;
        
        canvas.drawCircle(position, ringRadius * breathingScale, outerRingPaint);
        
        // 绘制内圈填充
        final innerFillPaint = Paint()
          ..color = color.withOpacity(0.8 * delayedAnimation)
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(position, pointRadius, innerFillPaint);
        
        // 绘制边框
        final borderPaint = Paint()
          ..color = Colors.white.withOpacity(delayedAnimation)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        
        canvas.drawCircle(position, pointRadius, borderPaint);
        
        // // 绘制颜色类型标签
        // final labelText = isSkinTone ? result.emoji : '🎨';
        // _drawText(canvas, labelText, position, Colors.white.withOpacity(delayedAnimation));
        
        // 绘制连接线到颜色信息
        if (delayedAnimation > 0.5) {
          final lineOpacity = (delayedAnimation - 0.5) * 2;
          final isSelected = selectedColorPointIndex == i;
          
          // 高亮效果
          final highlightMultiplier = isSelected ? 1.5 : 1.0;
          final bgOpacity = isSelected ? 0.9 : 0.7;
          
          final linePaint = Paint()
            ..color = (isSelected ? MorandiTheme.accentPink : MorandiTheme.secondaryText)
                .withOpacity(0.5 * lineOpacity * highlightMultiplier)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.0 : 1.0;
          
          // 连接到右侧信息区域
          final infoPosition = Offset(size.width - 80, 50 + i * 40);
          canvas.drawLine(position, infoPosition, linePaint);
          
          // 计算文字尺寸以自适应背景框 - 显示高级肤色信息
          final colorInfo = isSelected
              ? '${result.skinCategory}\n'
              '${result.warmCoolType}\n'
              '${result.colorBias}\n'
              : '${result.skinCategory}\n${result.warmCoolType}';
          final colorInfoTemp = isSelected
              ? '${result.skinCategory}\n'
              '${result.warmCoolType}\n'
              '${result.colorBias}\n'
              '${result.hexValue}\n'
              'Confidence: ${(result.confidence * 100).toStringAsFixed(0)}%'
              : '${result.skinCategory}\n${result.warmCoolType}';

          
          final textPainter = TextPainter(
            text: TextSpan(
              text: colorInfo,
              style: TextStyle(
                color: Colors.white,
                fontSize: isSelected ? 10 : 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                height: 1.3,
              ),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          textPainter.layout();
          
          // 自适应宽度：文字宽度 + 颜色块宽度 + 间距
          final adaptiveWidth = textPainter.width + 35 + 16; // 35是颜色块和间距，16是左右padding
          final adaptiveHeight = Math.max(32.0, textPainter.height + 12);
          
          // 绘制颜色信息背景
          final infoBgPaint = Paint()
            ..color = (isSelected ? MorandiTheme.accentPink : Colors.black)
                .withOpacity(bgOpacity * lineOpacity)
            ..style = PaintingStyle.fill;
          
          final infoRect = Rect.fromCenter(
            center: infoPosition,
            width: adaptiveWidth,
            height: adaptiveHeight,
          );
          
          // 高亮时添加外发光效果
          if (isSelected) {
            final glowPaint = Paint()
              ..color = MorandiTheme.accentPink.withOpacity(0.3 * lineOpacity)
              ..style = PaintingStyle.fill
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
            
            canvas.drawRRect(
              RRect.fromRectAndRadius(infoRect.inflate(4), const Radius.circular(20)),
              glowPaint,
            );
          }
          
          canvas.drawRRect(
            RRect.fromRectAndRadius(infoRect, const Radius.circular(16)),
            infoBgPaint,
          );
          
          // 绘制颜色指示块
          final colorBlockPaint = Paint()
            ..color = color.withOpacity(lineOpacity)
            ..style = PaintingStyle.fill;
          
          final colorBlockSize = isSelected ? 22.0 : 20.0;
          final colorBlockRect = Rect.fromCenter(
            center: Offset(infoPosition.dx - adaptiveWidth/2 + 18, infoPosition.dy),
            width: colorBlockSize,
            height: colorBlockSize,
          );
          
          canvas.drawRRect(
            RRect.fromRectAndRadius(colorBlockRect, const Radius.circular(4)),
            colorBlockPaint,
          );
          
          // 绘制颜色块边框
          final colorBlockBorderPaint = Paint()
            ..color = Colors.white.withOpacity(0.8 * lineOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.0 : 1.0;
          
          canvas.drawRRect(
            RRect.fromRectAndRadius(colorBlockRect, const Radius.circular(4)),
            colorBlockBorderPaint,
          );
          
          // 绘制颜色信息文字
          final textPosition = Offset(
            infoPosition.dx - adaptiveWidth/2 + 35 + textPainter.width/2, 
            infoPosition.dy
          );
          
          textPainter.paint(
            canvas, 
            textPosition - Offset(textPainter.width/2, textPainter.height/2)
          );
        }
      }
    }
    
    // 绘制智能分析完成标签
    if (animationValue > 0.8) {
      final labelOpacity = (animationValue - 0.8) * 5;
      _drawText(canvas, '✨ 智能色彩分析完成', Offset(size.width / 2, 30), MorandiTheme.primaryText.withOpacity(labelOpacity));
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