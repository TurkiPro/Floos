import 'package:flutter/material.dart';

const Map<String, IconData> _icons = {
  'food': Icons.restaurant,
  'transport': Icons.directions_bus,
  'shopping': Icons.shopping_bag,
  'bills': Icons.receipt_long,
  'health': Icons.medical_services,
  'entertainment': Icons.movie,
  'home': Icons.home,
  'other': Icons.category,
  'salary': Icons.payments,
  'extra_income': Icons.add_card,
  'investment': Icons.trending_up,
};

IconData iconForKey(String key) => _icons[key] ?? Icons.category;

/// Keys offered when building/editing a category.
const List<String> availableIconKeys = [
  'food',
  'transport',
  'shopping',
  'bills',
  'health',
  'entertainment',
  'home',
  'other',
  'salary',
  'extra_income',
  'investment',
];
