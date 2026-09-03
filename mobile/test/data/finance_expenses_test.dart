import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';

/// Finance rework — Phase 8: the outgoing side (Expenses).
///
/// Mirrors the expense half of src/services/finance/supabase-finance.service.ts
/// (`listExpenseCategories` / `listExpenses` / `createExpense` / `voidExpense`)
/// and src/features/finance/types.ts (`ExpenseCategory` / `ExpenseRow` /
/// `ExpensePage`). Backend: supabase/migrations/0046_finance_expenses.sql.
///
/// Same testing shape as finance_repository_source_test.dart — this project
/// has no fake Supabase client, so the RPC-contract cases are static checks on
/// the repository source and the row-mapping cases are real calls against the
/// models.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/finance_repository.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  group('ExpenseRow.fromJson', () {
    test('maps every snake_case field from a list_expenses row', () {
      final row = ExpenseRow.fromJson({
        'id': 'exp-1',
        'category_id': 'cat-9',
        'category_name': 'Utilities',
        'amount_minor': 4000000,
        'currency': 'INR',
        'payment_method': 'Bank Transfer',
        'spent_on': '2026-08-14',
        'vendor': 'State Electricity Board',
        'reference': 'INV-2231',
        'notes': 'August bill',
        'status': 'RECORDED',
        'created_at': '2026-08-14T09:30:00Z',
        'total_count': 12,
      });

      expect(row.id, 'exp-1');
      expect(row.categoryId, 'cat-9');
      expect(row.categoryName, 'Utilities');
      expect(row.amountMinor, 4000000);
      expect(row.currency, 'INR');
      expect(row.paymentMethod, 'Bank Transfer');
      expect(row.spentOn, '2026-08-14');
      expect(row.vendor, 'State Electricity Board');
      expect(row.reference, 'INV-2231');
      expect(row.notes, 'August bill');
      expect(row.status, 'RECORDED');
    });

    test('a voided row keeps its VOID status and tolerates null optional fields', () {
      final row = ExpenseRow.fromJson({
        'id': 'exp-2',
        'category_id': 'cat-1',
        'category_name': 'Other',
        'amount_minor': 150000,
        'currency': 'INR',
        'payment_method': null,
        'spent_on': '2026-08-02',
        'vendor': null,
        'reference': null,
        'notes': null,
        'status': 'VOID',
      });

      expect(row.status, 'VOID');
      expect(row.paymentMethod, isNull);
      expect(row.vendor, isNull);
      expect(row.reference, isNull);
      expect(row.notes, isNull);
    });

    test('status stays the backend vocabulary verbatim, never re-derived here', () {
      expect(
        ExpenseRow.fromJson(_minimalRow('RECORDED')).isVoid,
        isFalse,
      );
      expect(
        ExpenseRow.fromJson(_minimalRow('VOID')).isVoid,
        isTrue,
      );
    });
  });

  group('ExpensePage', () {
    test('totalCount is the server row\'s own total_count, never expenses.length', () {
      final page = ExpensePage.fromRows([
        _minimalRow('RECORDED', totalCount: 40),
        _minimalRow('RECORDED', totalCount: 40),
      ]);

      expect(page.expenses.length, 2);
      expect(page.totalCount, 40);
    });

    test('an empty result is a real zero, not a missing count', () {
      final page = ExpensePage.fromRows(const []);
      expect(page.expenses, isEmpty);
      expect(page.totalCount, 0);
    });
  });

  group('ExpenseCategory.fromJson', () {
    test('maps id and name', () {
      final category = ExpenseCategory.fromJson({'id': 'cat-3', 'name': 'Maintenance'});
      expect(category.id, 'cat-3');
      expect(category.name, 'Maintenance');
    });
  });

  group('FinanceRepository.listExpenseCategories', () {
    test('reads the expense_categories table directly, shared defaults plus this facility', () {
      expect(source, contains("from('expense_categories')"));
      expect(source, contains('facility_id.is.null,facility_id.eq.'));
      expect(source, contains("eq('is_active', true)"));
      expect(source, contains("order('sort_order')"));
    });
  });

  group('FinanceRepository.listExpenses', () {
    test('calls list_expenses with the shared date-range args plus category/limit/offset', () {
      expect(source, contains("'list_expenses',"));
      expect(source, contains('..._dateRangeArgs('));
      expect(source, contains("'p_category_id':"));
      expect(source, contains("'p_limit': input.limit ?? 25"));
      expect(source, contains("'p_offset': input.offset ?? 0"));
    });

    test('the page total is the server row\'s total_count, not the fetched length', () {
      expect(source, contains('ExpensePage.fromRows('));
      expect(source, isNot(contains('totalCount: expenses.length')));
    });
  });

  group('FinanceRepository.createExpense', () {
    test('calls create_expense with every p_-prefixed argument the RPC takes', () {
      expect(source, contains("'create_expense',"));
      for (final param in const [
        "'p_facility_id':",
        "'p_category_id':",
        "'p_amount_minor':",
        "'p_spent_on':",
        "'p_payment_method':",
        "'p_vendor':",
        "'p_reference':",
        "'p_notes':",
      ]) {
        expect(source, contains(param), reason: 'create_expense must send $param');
      }
    });

    test('never sends an amount the client computed — the minor-unit value is passed straight through', () {
      // The caller hands createExpense an already-computed minor-unit int; the
      // repository must not do rupee<->paise arithmetic of its own.
      expect(source, isNot(contains('* 100')));
      expect(source, isNot(contains('/ 100')));
    });
  });

  group('FinanceRepository.voidExpense', () {
    test('calls void_expense with the expense id and an optional reason', () {
      expect(source, contains("'void_expense',"));
      expect(source, contains("'p_expense_id':"));
      expect(source, contains("'p_reason':"));
    });

    test('voids, never deletes — no delete path exists in the repository', () {
      expect(source, isNot(contains('.delete()')));
    });
  });

  group('FinanceRepository still does no revenue math after Phase 8', () {
    test('the expense methods add no fold/reduce/sum over amounts', () {
      for (final forbidden in const ['fold(', 'reduce(', '.sum', 'amountMinor +', 'amount_minor +']) {
        expect(source, isNot(contains(forbidden)),
            reason: 'every total must come from a backend RPC field');
      }
    });

    test('every thrown error is still the app\'s own AppException, via _mapError', () {
      final thrown = RegExp(r'throw ([A-Za-z_][\w.]*)')
          .allMatches(source)
          .map((m) => m.group(1))
          .toSet();
      expect(thrown, {'AppException', '_mapError'});
    });
  });
}

Map<String, dynamic> _minimalRow(String status, {int? totalCount}) => {
      'id': 'exp',
      'category_id': 'cat',
      'category_name': 'Other',
      'amount_minor': 1000,
      'currency': 'INR',
      'payment_method': null,
      'spent_on': '2026-08-01',
      'vendor': null,
      'reference': null,
      'notes': null,
      'status': status,
      'total_count': totalCount ?? 1,
    };
