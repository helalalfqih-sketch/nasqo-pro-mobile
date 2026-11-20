/// Model for customer tailored dimensions, sizes, and customizations.
class CustomerMeasurement {
  const CustomerMeasurement({
    this.id,
    required this.customerName,
    this.phone = '',
    required this.date,
    this.itemType = 'ثوب رجالي',
    this.length = 0.0,
    this.shoulder = 0.0,
    this.sleeve = 0.0,
    this.chest = 0.0,
    this.neck = 0.0,
    this.waist = 0.0,
    this.notes = '',
  });

  final int? id;
  final String customerName;
  final String phone;
  final String date;
  final String itemType;
  final double length;
  final double shoulder;
  final double sleeve;
  final double chest;
  final double neck;
  final double waist;
  final String notes;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'customerName': customerName,
        'phone': phone,
        'date': date,
        'itemType': itemType,
        'length': length,
        'shoulder': shoulder,
        'sleeve': sleeve,
        'chest': chest,
        'neck': neck,
        'waist': waist,
        'notes': notes,
      };

  factory CustomerMeasurement.fromMap(Map<String, Object?> map) =>
      CustomerMeasurement(
        id: map['id'] as int?,
        customerName: map['customerName'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        date: map['date'] as String? ?? '',
        itemType: map['itemType'] as String? ?? 'ثوب رجالي',
        length: (map['length'] as num?)?.toDouble() ?? 0.0,
        shoulder: (map['shoulder'] as num?)?.toDouble() ?? 0.0,
        sleeve: (map['sleeve'] as num?)?.toDouble() ?? 0.0,
        chest: (map['chest'] as num?)?.toDouble() ?? 0.0,
        neck: (map['neck'] as num?)?.toDouble() ?? 0.0,
        waist: (map['waist'] as num?)?.toDouble() ?? 0.0,
        notes: map['notes'] as String? ?? '',
      );

  CustomerMeasurement copyWith({
    int? id,
    String? customerName,
    String? phone,
    String? date,
    String? itemType,
    double? length,
    double? shoulder,
    double? sleeve,
    double? chest,
    double? neck,
    double? waist,
    String? notes,
  }) =>
      CustomerMeasurement(
        id: id ?? this.id,
        customerName: customerName ?? this.customerName,
        phone: phone ?? this.phone,
        date: date ?? this.date,
        itemType: itemType ?? this.itemType,
        length: length ?? this.length,
        shoulder: shoulder ?? this.shoulder,
        sleeve: sleeve ?? this.sleeve,
        chest: chest ?? this.chest,
        neck: neck ?? this.neck,
        waist: waist ?? this.waist,
        notes: notes ?? this.notes,
      );
}
