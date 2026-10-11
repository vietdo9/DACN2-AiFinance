import 'package:flutter/material.dart';

class CategoryModel {
  final String code;
  final String name;
  final String type;
  final String icon;
  final Color color;

  CategoryModel({
    required this.code,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    Color parseColor(String? hex) {
      if (hex == null || !hex.startsWith('#')) return const Color(0xFF4F46E5);
      try {
        final buffer = StringBuffer();
        if (hex.length == 7) buffer.write('ff');
        buffer.write(hex.replaceFirst('#', ''));
        return Color(int.parse(buffer.toString(), radix: 16));
      } catch (_) {
        return const Color(0xFF4F46E5);
      }
    }

    return CategoryModel(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'expense',
      icon: json['icon'] ?? 'category',
      color: parseColor(json['color']),
    );
  }

  IconData get iconData {
    switch (code) {
      case 'AN_UONG':
        return Icons.restaurant;
      case 'DI_LAI':
        return Icons.directions_car;
      case 'MUA_SAM':
        return Icons.shopping_bag;
      case 'HOA_DON':
        return Icons.receipt_long;
      case 'NHA_O':
        return Icons.home;
      case 'GIAI_TRI':
        return Icons.sports_esports;
      case 'SUC_KHOE':
        return Icons.medical_services;
      case 'HOC_TAP':
        return Icons.school;
      case 'TIET_KIEM_DAU_TU':
        return Icons.savings;
      case 'THU_NHAP':
        return Icons.payments;
      default:
        return Icons.category;
    }
  }
}
