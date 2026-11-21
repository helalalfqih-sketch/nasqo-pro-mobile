/// Base-10 arithmetic for reconciling the numeric values returned by SQLite.
/// Input is the round-trippable decimal representation of each source number.
class BackupDecimal {
  const BackupDecimal._(this.units, this.scale);
  final BigInt units;
  final int scale;
  factory BackupDecimal.from(num value) {
    if (!value.isFinite) throw const FormatException('قيمة عددية غير صالحة.');
    final parts = value.toString().toLowerCase().split('e');
    final digits = parts.first.split('.');
    final exponent = parts.length == 2 ? int.parse(parts.last) : 0;
    final places = (digits.length == 2 ? digits.last.length : 0) - exponent;
    final n = BigInt.parse(digits.join());
    return places < 0
        ? BackupDecimal._(n * BigInt.from(10).pow(-places), 0)
        : BackupDecimal._(n, places);
  }
  BackupDecimal operator +(BackupDecimal other) {
    final places = scale > other.scale ? scale : other.scale;
    return BackupDecimal._(
        units * BigInt.from(10).pow(places - scale) +
            other.units * BigInt.from(10).pow(places - other.scale),
        places);
  }

  BackupDecimal operator *(BackupDecimal other) =>
      BackupDecimal._(units * other.units, scale + other.scale);
  @override
  String toString() {
    if (units == BigInt.zero) return '0';
    final digits = units.abs().toString().padLeft(scale + 1, '0');
    final at = digits.length - scale;
    final fraction = digits.substring(at).replaceFirst(RegExp(r'0+$'), '');
    return '${units.isNegative ? "-" : ""}${digits.substring(0, at)}${fraction.isEmpty ? "" : ".$fraction"}';
  }
}
