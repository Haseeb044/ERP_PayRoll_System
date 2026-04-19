import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class CategoryBreakdown extends Equatable {
  final String categoryName;
  final double amount;
  final Color color;

  const CategoryBreakdown({
    required this.categoryName,
    required this.amount,
    required this.color,
  });

  @override
  List<Object?> get props => [categoryName, amount, color];
}

class DeductionItem extends Equatable {
  final String label;
  final double amount;
  final int count;
  final Color color;

  const DeductionItem({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
  });

  @override
  List<Object?> get props => [label, amount, count, color];
}

class FinancialReportModel extends Equatable {
  final double totalRevenue;
  final double totalExpense;
  final double netProfit;
  final double totalNetPay;
  final double totalCompanyExpense;
  final double recoverableAmount;
  final double recoverableJournals;
  final double recoverableFines;
  final double nonRecoverableExpense;
  final double recoverableOutstanding;
  final double recoverableCollected;
  final double recoverableCreated;
  final double extraEarningsTotal;
  final List<CategoryBreakdown> expenseBreakdown;
  final List<CategoryBreakdown> extraEarningsBreakdown;
  final List<DeductionItem> deductions;
  final List<Map<String, dynamic>> realTimeDeductions;
  final Map<String, double> agingData;

  const FinancialReportModel({
    required this.totalRevenue,
    required this.totalExpense,
    required this.netProfit,
    this.totalNetPay = 0,
    this.totalCompanyExpense = 0,
    required this.recoverableAmount,
    this.recoverableJournals = 0,
    this.recoverableFines = 0,
    this.nonRecoverableExpense = 0,
    this.recoverableOutstanding = 0,
    this.recoverableCollected = 0,
    this.recoverableCreated = 0,
    this.extraEarningsTotal = 0,
    required this.expenseBreakdown,
    this.extraEarningsBreakdown = const [],
    this.deductions = const [],
    this.realTimeDeductions = const [],
    this.agingData = const {},
  });

  @override
  List<Object?> get props => [
    totalRevenue,
    totalExpense,
    netProfit,
    totalNetPay,
    totalCompanyExpense,
    recoverableAmount,
    recoverableJournals,
    recoverableFines,
    nonRecoverableExpense,
    recoverableOutstanding,
    recoverableCollected,
    recoverableCreated,
    extraEarningsTotal,
    expenseBreakdown,
    extraEarningsBreakdown,
    deductions,
    realTimeDeductions,
    agingData,
  ];
}
