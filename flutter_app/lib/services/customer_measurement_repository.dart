import 'package:sqflite/sqflite.dart';
import '../models/customer_measurement.dart';
import 'local_database.dart';

class CustomerMeasurementRepository {
  CustomerMeasurementRepository(this.database);
  final LocalDatabase database;

  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS customer_measurements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customerName TEXT NOT NULL,
      phone TEXT NOT NULL,
      date TEXT NOT NULL,
      itemType TEXT NOT NULL,
      length REAL NOT NULL,
      shoulder REAL NOT NULL,
      sleeve REAL NOT NULL,
      chest REAL NOT NULL,
      neck REAL NOT NULL,
      waist REAL NOT NULL,
      notes TEXT NOT NULL
    )
  ''');

  Future<void> initSchema() async {
    final db = await database.database;
    await createSchema(db);
  }

  Future<List<CustomerMeasurement>> loadAll() async {
    final db = await database.database;
    await createSchema(db);
    final rows = await db.query('customer_measurements', orderBy: 'id DESC');
    return rows.map(CustomerMeasurement.fromMap).toList();
  }

  Future<int> count() async {
    final db = await database.database;
    await createSchema(db);
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM customer_measurements'),
    );
    return count ?? 0;
  }

  Future<CustomerMeasurement> save(CustomerMeasurement measurement) async {
    final db = await database.database;
    await createSchema(db);
    final map = measurement.toMap();
    if (measurement.id == null) {
      final id = await db.insert('customer_measurements', map);
      return measurement.copyWith(id: id);
    } else {
      await db.update(
        'customer_measurements',
        map,
        where: 'id = ?',
        whereArgs: [measurement.id],
      );
      return measurement;
    }
  }

  Future<void> delete(int id) async {
    final db = await database.database;
    await createSchema(db);
    await db.delete('customer_measurements', where: 'id = ?', whereArgs: [id]);
  }
}
