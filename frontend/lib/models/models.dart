class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String organizationId;
  final String organizationName;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.organizationId,
    required this.organizationName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? '',
      organizationId: json['organization_id'] ?? '',
      organizationName: json['organization_name'] ?? '',
    );
  }
}

class Product {
  final String id;
  final String name;
  final String genericName;
  final String productCode;
  final String dosageForm;
  final String strength;
  final String? description;

  Product({
    required this.id,
    required this.name,
    required this.genericName,
    required this.productCode,
    required this.dosageForm,
    required this.strength,
    this.description,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      genericName: json['generic_name'] ?? '',
      productCode: json['product_code'] ?? '',
      dosageForm: json['dosage_form'] ?? '',
      strength: json['strength'] ?? '',
      description: json['description'],
    );
  }
}

class Batch {
  final String id;
  final String productId;
  final String batchNumber;
  final String manufacturingDate;
  final String expiryDate;
  final int quantityManufactured;
  final String status;

  Batch({
    required this.id,
    required this.productId,
    required this.batchNumber,
    required this.manufacturingDate,
    required this.expiryDate,
    required this.quantityManufactured,
    required this.status,
  });

  factory Batch.fromJson(Map<String, dynamic> json) {
    return Batch(
      id: json['id'] ?? '',
      productId: json['product_id'] ?? '',
      batchNumber: json['batch_number'] ?? '',
      manufacturingDate: json['manufacturing_date'] ?? '',
      expiryDate: json['expiry_date'] ?? '',
      quantityManufactured: json['quantity_manufactured'] ?? 0,
      status: json['status'] ?? 'active',
    );
  }
}

class Shipment {
  final String id;
  final String shipmentReference;
  final String senderOrgId;
  final String receiverOrgId;
  final String status;
  final int declaredQuantity;
  final int? receivedQuantity;
  final String? notes;
  final String createdAt;

  Shipment({
    required this.id,
    required this.shipmentReference,
    required this.senderOrgId,
    required this.receiverOrgId,
    required this.status,
    required this.declaredQuantity,
    this.receivedQuantity,
    this.notes,
    required this.createdAt,
  });

  factory Shipment.fromJson(Map<String, dynamic> json) {
    return Shipment(
      id: json['id'] ?? '',
      shipmentReference: json['shipment_reference'] ?? '',
      senderOrgId: json['sender_org_id'] ?? '',
      receiverOrgId: json['receiver_org_id'] ?? '',
      status: json['status'] ?? 'draft',
      declaredQuantity: json['declared_quantity'] ?? 0,
      receivedQuantity: json['received_quantity'],
      notes: json['notes'],
      createdAt: json['created_at'] ?? '',
    );
  }
}

