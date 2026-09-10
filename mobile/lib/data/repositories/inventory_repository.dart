import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/inventory.dart';

/// Inventory & Vendors — mirrors src/services/inventory/supabase-inventory.service.ts.
///
/// A read/write layer over the RPCs in migrations 0078-0081. Every RPC
/// self-enforces the caller's permission (has_permission), no-negative-stock,
/// and the purchase/payment separation — this class only maps rows and errors.
/// Money is in integer minor units (paise) throughout.
class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  AppException _map(Object e) {
    if (e is AppException) return e;
    final msg = e is PostgrestException ? e.message : e.toString();
    final code = e is PostgrestException ? e.code : null;
    if (code == '42501' || msg.contains('permission')) {
      return AppException(AppErrorCode.unauthorized, msg);
    }
    if (code == '23505' || msg.contains('already exists') || msg.contains('already in use')) {
      return AppException(AppErrorCode.databaseError, msg);
    }
    if (code == 'P0002' || msg.contains('not found')) {
      return AppException(AppErrorCode.databaseError, msg);
    }
    // Server-side business rules raise plain messages (insufficient stock,
    // can't receive more than pending, PO already received, …) — keep them.
    if (e is PostgrestException) return AppException(AppErrorCode.databaseError, msg);
    return AppException(AppErrorCode.network);
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List<dynamic>? ?? const []).map((r) => (r as Map).cast<String, dynamic>()).toList();

  Map<String, dynamic> _obj(dynamic data) => (data as Map).cast<String, dynamic>();

  // ── Overview ────────────────────────────────────────────────────────────
  Future<InventoryOverview> getOverview(String facilityId) async {
    try {
      final data = await _client.rpc('get_inventory_overview', params: {'p_facility_id': facilityId});
      return InventoryOverview.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Items ───────────────────────────────────────────────────────────────
  Future<ItemPage> listItems({
    required String facilityId,
    String? search,
    String? categoryId,
    ItemStatus? status,
    StockStatus? stockStatus,
    String? vendorId,
    String sort = 'name',
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_inventory_items', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_category_id': categoryId,
        'p_status': status?.toJson(),
        'p_stock_status': switch (stockStatus) {
          StockStatus.inStock => 'IN_STOCK',
          StockStatus.lowStock => 'LOW_STOCK',
          StockStatus.outOfStock => 'OUT_OF_STOCK',
          null => null,
        },
        'p_vendor_id': vendorId,
        'p_sort': sort,
        'p_limit': limit,
        'p_offset': offset,
      });
      return ItemPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<ItemDetail> getItem(String itemId) async {
    try {
      final data = await _client.rpc('get_inventory_item', params: {'p_item_id': itemId});
      return ItemDetail.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> createItem({
    required String facilityId,
    required String name,
    required String sku,
    String? categoryId,
    String unit = 'piece',
    int reorderLevel = 0,
    String? brand,
    String? description,
    int? defaultUnitCostMinor,
    String? preferredVendorId,
    int openingStock = 0,
  }) async {
    try {
      final row = await _client.rpc('create_inventory_item', params: {
        'p_facility_id': facilityId,
        'p_name': name,
        'p_sku': sku,
        'p_category_id': categoryId,
        'p_unit': unit,
        'p_reorder_level': reorderLevel,
        'p_brand': brand,
        'p_description': description,
        'p_default_unit_cost_minor': defaultUnitCostMinor,
        'p_preferred_vendor_id': preferredVendorId,
        'p_opening_stock': openingStock,
      });
      return _obj(row)['id'] as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateItem({
    required String itemId,
    String? name,
    String? sku,
    String? categoryId,
    String? unit,
    int? reorderLevel,
    String? brand,
    String? description,
    int? defaultUnitCostMinor,
    String? preferredVendorId,
    ItemStatus? status,
  }) async {
    try {
      await _client.rpc('update_inventory_item', params: {
        'p_item_id': itemId,
        'p_name': name,
        'p_sku': sku,
        'p_category_id': categoryId,
        'p_unit': unit,
        'p_reorder_level': reorderLevel,
        'p_brand': brand,
        'p_description': description,
        'p_default_unit_cost_minor': defaultUnitCostMinor,
        'p_preferred_vendor_id': preferredVendorId,
        'p_status': status?.toJson(),
      });
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Stock movements ─────────────────────────────────────────────────────
  Future<void> recordMovement({
    required String itemId,
    required MovementType type,

    /// Signed. STOCK_OUT is normalised to a negative value server-side, but the
    /// caller passes what it means (negative for out, delta for adjustment).
    required int quantity,
    String? reason,
    String? notes,
    int? unitCostMinor,
    String referenceType = 'manual',
    String? referenceId,
  }) async {
    try {
      await _client.rpc('record_stock_movement', params: {
        'p_item_id': itemId,
        'p_movement_type': type.toJson(),
        'p_quantity': quantity,
        'p_reason': reason,
        'p_notes': notes,
        'p_unit_cost_minor': unitCostMinor,
        'p_reference_type': referenceType,
        'p_reference_id': referenceId,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<StockMovementPage> listMovements({
    required String facilityId,
    MovementType? type,
    String? itemId,
    int limit = 25,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_stock_movements', params: {
        'p_facility_id': facilityId,
        'p_movement_type': type?.toJson(),
        'p_item_id': itemId,
        'p_from': null,
        'p_to': null,
        'p_performed_by': null,
        'p_limit': limit,
        'p_offset': offset,
      });
      return StockMovementPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Categories ──────────────────────────────────────────────────────────
  Future<List<InventoryCategory>> listCategories(String facilityId) async {
    try {
      final rows = await _client.rpc('list_inventory_categories', params: {'p_facility_id': facilityId});
      return _rows(rows).map(InventoryCategory.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> createCategory({required String facilityId, required String name, String? description}) async {
    try {
      await _client.rpc('create_inventory_category', params: {
        'p_facility_id': facilityId,
        'p_name': name,
        'p_description': description,
        'p_sort_order': 0,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateCategory({required String categoryId, String? name, String? description, bool? isActive}) async {
    try {
      await _client.rpc('update_inventory_category', params: {
        'p_category_id': categoryId,
        'p_name': name,
        'p_description': description,
        'p_is_active': isActive,
        'p_sort_order': null,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Vendors ─────────────────────────────────────────────────────────────
  Future<VendorPage> listVendors({
    required String facilityId,
    String? search,
    VendorStatus? status,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_vendors', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_status': status?.toJson(),
        'p_limit': limit,
        'p_offset': offset,
      });
      return VendorPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<VendorDetail> getVendor(String vendorId) async {
    try {
      final data = await _client.rpc('get_vendor', params: {'p_vendor_id': vendorId});
      return VendorDetail.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> createVendor({
    required String facilityId,
    required String name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? gstNumber,
    String? panNumber,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('create_vendor', params: {
        'p_facility_id': facilityId,
        'p_name': name,
        'p_contact_person': contactPerson,
        'p_phone': phone,
        'p_email': email,
        'p_address': address,
        'p_gst_number': gstNumber,
        'p_pan_number': panNumber,
        'p_notes': notes,
      });
      return _obj(row)['id'] as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateVendor({
    required String vendorId,
    String? name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? gstNumber,
    String? panNumber,
    String? notes,
    VendorStatus? status,
  }) async {
    try {
      await _client.rpc('update_vendor', params: {
        'p_vendor_id': vendorId,
        'p_name': name,
        'p_contact_person': contactPerson,
        'p_phone': phone,
        'p_email': email,
        'p_address': address,
        'p_gst_number': gstNumber,
        'p_pan_number': panNumber,
        'p_notes': notes,
        'p_status': status?.toJson(),
      });
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Purchase orders ─────────────────────────────────────────────────────
  Future<PurchaseOrderPage> listPurchaseOrders({
    required String facilityId,
    String? vendorId,
    PoStatus? status,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_purchase_orders', params: {
        'p_facility_id': facilityId,
        'p_vendor_id': vendorId,
        'p_status': status?.toJson(),
        'p_payment_status': null,
        'p_from': null,
        'p_to': null,
        'p_limit': limit,
        'p_offset': offset,
      });
      return PurchaseOrderPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<PurchaseOrderDetail> getPurchaseOrder(String poId) async {
    try {
      final data = await _client.rpc('get_purchase_order', params: {'p_po_id': poId});
      return PurchaseOrderDetail.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> createPurchaseOrder({
    required String facilityId,
    required String vendorId,
    required List<({String itemId, int quantity, int unitCostMinor, int taxMinor, int discountMinor})> lines,
    String? orderDate,
    String? expectedDelivery,
    String? reference,
    String? notes,
  }) async {
    try {
      final id = await _client.rpc('create_purchase_order', params: {
        'p_facility_id': facilityId,
        'p_vendor_id': vendorId,
        'p_lines': lines
            .map((l) => {
                  'itemId': l.itemId,
                  'quantity': l.quantity,
                  'unitCostMinor': l.unitCostMinor,
                  'taxMinor': l.taxMinor,
                  'discountMinor': l.discountMinor,
                })
            .toList(),
        'p_order_date': orderDate,
        'p_expected_delivery': expectedDelivery,
        'p_reference': reference,
        'p_notes': notes,
        'p_invoice_path': null,
      });
      return id as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> placePurchaseOrder(String poId) async {
    try {
      await _client.rpc('place_purchase_order', params: {'p_po_id': poId});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> receivePurchaseOrder(String poId, List<({String lineId, int quantity})> receipts) async {
    try {
      await _client.rpc('receive_purchase_order', params: {
        'p_po_id': poId,
        'p_receipts': receipts.map((r) => {'lineId': r.lineId, 'quantity': r.quantity}).toList(),
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> cancelPurchaseOrder(String poId, String reason) async {
    try {
      await _client.rpc('cancel_purchase_order', params: {'p_po_id': poId, 'p_reason': reason});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> recordPurchasePayment({
    required String poId,
    required int amountMinor,
    String? paidOn,
    String? paymentMethod,
    String? reference,
    String? note,
  }) async {
    try {
      await _client.rpc('record_purchase_payment', params: {
        'p_po_id': poId,
        'p_amount_minor': amountMinor,
        'p_paid_on': paidOn,
        'p_payment_method': paymentMethod,
        'p_reference': reference,
        'p_note': note,
      });
    } catch (e) {
      throw _map(e);
    }
  }
}
