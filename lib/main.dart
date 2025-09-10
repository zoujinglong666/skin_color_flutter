import 'dart:io';
import 'dart:math' as Math;
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
  smartAnalysis, // 智能分析模式
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
  bool _isDraggingHandle = false;
  int? _draggingHandleIndex; // 0=topLeft, 1=topRight, 2=bottomLeft, 3=bottomRight
  bool _isHoveringHandle = false;
  int? _hoveringHandleIndex;
  
  // 动画控制器
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _rectAnimationController;
  late AnimationController _handleAnimationController;
  
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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _rectAnimationController.dispose();
    _handleAnimationController.dispose();
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

  /// 智能分析模式 - 分析图片唯一主色 (升级版)
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
        // 自适应区域采样策略：根据图像特征选择采样区域
        final allSamples = <Color>[];
        final regionSamples = <String, List<Color>>{};
        
        // 图像分区采样 - 将图像分为9个区域，分别采样
        final regionWidth = image.width / 3;
        final regionHeight = image.height / 3;
        
        // 降采样以提高性能，但保持足够的采样密度
        final stepX = Math.max(1, (image.width / 150).round());
        final stepY = Math.max(1, (image.height / 150).round());
        
        // 计算每个区域的颜色样本
        for (int regionY = 0; regionY < 3; regionY++) {
          for (int regionX = 0; regionX < 3; regionX++) {
            final regionKey = '$regionX-$regionY';
            regionSamples[regionKey] = [];
            
            final startX = (regionX * regionWidth).round();
            final startY = (regionY * regionHeight).round();
            final endX = ((regionX + 1) * regionWidth).round();
            final endY = ((regionY + 1) * regionHeight).round();
            
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
                  
                  // 增强的颜色过滤 - 使用HSV空间进行更精确的过滤
                  final hsv = HSVColor.fromColor(color);
                  final brightness = (color.red + color.green + color.blue) / 3;
                  final saturation = hsv.saturation;
                  
                  // 肤色范围过滤 - 基于研究的肤色范围
                  final isInSkinToneRange = _isLikelySkinTone(color);
                  
                  // 过滤条件：亮度适中、饱和度合理、可能是肤色
                  if (brightness > 50 && brightness < 220 && 
                      saturation > 0.05 && saturation < 0.85) {
                    regionSamples[regionKey]!.add(color);
                    allSamples.add(color);
                  }
                }
              }
            }
          }
        }
        
        // 分析每个区域的颜色分布
        final regionAnalysis = <String, Map<String, dynamic>>{};
        for (final entry in regionSamples.entries) {
          if (entry.value.isNotEmpty) {
            final dominantColor = _extractDominantColor(entry.value);
            final labColor = _rgbToLab(dominantColor.red, dominantColor.green, dominantColor.blue);
            
            regionAnalysis[entry.key] = {
              'color': dominantColor,
              'count': entry.value.length,
              'lab': labColor,
              'isSkinTone': _isLikelySkinTone(dominantColor),
            };
          }
        }
        
        // 智能选择最可能的肤色区域
        Color? selectedColor;
        String regionDescription = '图片主色调';
        
        // 首先尝试找到肤色区域
        final skinToneRegions = regionAnalysis.entries
            .where((e) => e.value['isSkinTone'] == true)
            .toList();
        
        if (skinToneRegions.isNotEmpty) {
          // 按样本数量排序，选择样本最多的肤色区域
          skinToneRegions.sort((a, b) => 
              (b.value['count'] as int).compareTo(a.value['count'] as int));
          selectedColor = skinToneRegions.first.value['color'] as Color;
          regionDescription = '检测到的肤色';
        } else if (allSamples.isNotEmpty) {
          // 如果没有明显的肤色区域，使用全图聚类
          selectedColor = _extractDominantColor(allSamples);
        }
        
        // 显示分析结果
        if (selectedColor != null && _displaySize != null) {
          final centerPoint = Offset(
            _displaySize!.width / 2,
            _displaySize!.height / 2,
          );
          
          final result = _analyzeSkinTone(selectedColor, centerPoint, regionDescription);
          
          setState(() {
            _analysisResults.add(result);
          });
        }
      }
    } catch (e) {
      print('智能分析失败: $e');
    }

    setState(() {
      _isAnalyzing = false;
    });
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

  /// 处理拖拽更新事件
  void _onPanUpdate(DragUpdateDetails details) {
    if (_selectedImage == null) return;

    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
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
    } else if (_isDraggingHandle && _rectStartPoint != null && _currentDragPoint != null) {
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
    }
  }

  /// 分析矩形区域的肤色
  Future<void> _analyzeRectRegion(Rect rect) async {
    final center = rect.center;
    await _analyzeSkinColorAtPoint(center, '框选区域 ${_analysisResults.length + 1}');
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

  /// 分析肤色色调 - 升级版算法
  SkinColorResult _analyzeSkinTone(Color color, Offset position, String label) {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    
    // 转换为HSV
    final hsv = HSVColor.fromColor(color);
    final hue = hsv.hue;
    final saturation = hsv.saturation;
    final value = hsv.value;
    
    // 转换为Lab色彩空间进行更精确的分析
    final labColor = _rgbToLab(r, g, b);
    final a = labColor[1]; // a轴: 负值为绿色，正值为红色
    final b_lab = labColor[2]; // b轴: 负值为蓝色，正值为黄色
    
    // 计算色彩特征比例
    final redYellowRatio = r / (g + 1); // 避免除零
    final yellowRatio = (r + g) / (b + 1);
    final redBlueRatio = r / (b + 1);
    
    // ITA值计算 (Individual Typology Angle) - 肤色分类的专业指标
    final L = labColor[0];
    final ITA = (Math.atan((L - 50) / b_lab) * 180 / Math.pi).toDouble();
    
    // 肤色分类逻辑 - 升级版
    String toneType;
    String warmCoolType;
    String emoji;
    
    // 基于ITA值的肤色分类
    if (ITA > 55) {
      // 非常白皙
      toneType = '白皙肤色';
      emoji = '✨';
      
      if (a > 8) {
        warmCoolType = '暖白皙';
      } else if (a < 0) {
        warmCoolType = '冷白皙';
      } else {
        warmCoolType = '中性白皙';
      }
    } else if (ITA > 41) {
      // 浅色肤色
      toneType = '浅色肤色';
      emoji = '🌟';
      
      if (a > 10 && b_lab > 15) {
        warmCoolType = '暖浅色调';
      } else if (a < 8) {
        warmCoolType = '冷浅色调';
      } else {
        warmCoolType = '中性浅色调';
      }
    } else if (ITA > 28) {
      // 中等肤色
      toneType = '中等肤色';
      emoji = '🌼';
      
      if (b_lab > 18 && a > 10) {
        warmCoolType = '暖中性调';
      } else if (b_lab < 15 || a < 8) {
        warmCoolType = '冷中性调';
      } else {
        warmCoolType = '中性调';
      }
    } else if (ITA > 10) {
      // 小麦色
      toneType = '小麦肤色';
      emoji = '🌞';
      
      if (b_lab > 20) {
        warmCoolType = '暖小麦色';
      } else {
        warmCoolType = '中性小麦色';
      }
    } else {
      // 深色肤色
      toneType = '深色肤色';
      emoji = '🌹';
      
      if (b_lab > 15) {
        warmCoolType = '暖深色调';
      } else {
        warmCoolType = '中性深色调';
      }
    }
    
    // 细化冷暖色调判断 - 基于色相和Lab值的综合分析
    if (warmCoolType.contains('中性')) {
      // 进一步细分中性调
      if ((hue >= 20 && hue <= 40) && yellowRatio > 1.9) {
        warmCoolType = warmCoolType.replaceAll('中性', '暖');
      } else if ((hue >= 340 || hue <= 10) && redBlueRatio > 1.5) {
        warmCoolType = warmCoolType.replaceAll('中性', '冷');
      }
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
                _performFaceDetection();
              } else if (mode == AnalysisMode.smartAnalysis) {
                _performSmartAnalysis();
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
                            animation: Listenable.merge([_rectAnimationController, _handleAnimationController]),
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
  final bool isDraggingHandle;
  final int? draggingHandleIndex;
  final bool isHoveringHandle;
  final int? hoveringHandleIndex;
  final AnalysisMode analysisMode;
  final Animation<double>? rectAnimation;
  final Animation<double>? handleAnimation;

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

    // 绘制智能分析模式的扫描效果
    if (analysisMode == AnalysisMode.smartAnalysis) {
      final scanPaint = Paint()
        ..color = MorandiTheme.neutralTone.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final scanFillPaint = Paint()
        ..color = MorandiTheme.neutralTone.withOpacity(0.05)
        ..style = PaintingStyle.fill;

      // 绘制全图扫描网格
      final gridSize = 40.0;
      for (double x = 0; x < size.width; x += gridSize) {
        for (double y = 0; y < size.height; y += gridSize) {
          final rect = Rect.fromLTWH(x, y, gridSize, gridSize);
          canvas.drawRect(rect, scanFillPaint);
        }
      }
      
      // 绘制边框
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        scanPaint,
      );
      
      // 绘制中心标记
      final center = Offset(size.width / 2, size.height / 2);
      canvas.drawCircle(
        center,
        20,
        Paint()..color = MorandiTheme.neutralTone.withOpacity(0.3)..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        20,
        Paint()..color = MorandiTheme.neutralTone..style = PaintingStyle.stroke..strokeWidth = 2,
      );
      
      // 绘制智能分析标签
      _drawText(canvas, '智能主色提取', Offset(size.width / 2, 25), MorandiTheme.primaryText);
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
      final completedRect = Rect.fromPoints(rectStartPoint!, currentDragPoint!);
      
      final completedRectPaint = Paint()
        ..color = MorandiTheme.warmTone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final completedFillPaint = Paint()
        ..color = MorandiTheme.warmTone.withOpacity(0.12)
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