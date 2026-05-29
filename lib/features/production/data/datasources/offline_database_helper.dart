import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class OfflineStageLog {
  final int? id;
  final String runId;
  final String stageId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String syncStatus; // 'pending', 'failed'

  const OfflineStageLog({
    this.id,
    required this.runId,
    required this.stageId,
    required this.payload,
    required this.createdAt,
    required this.syncStatus,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'run_id': runId,
      'stage_id': stageId,
      'payload': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory OfflineStageLog.fromMap(Map<String, dynamic> map) {
    return OfflineStageLog(
      id: map['id'] as int?,
      runId: map['run_id'] as String,
      stageId: map['stage_id'] as String,
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      createdAt: DateTime.parse(map['created_at'] as String),
      syncStatus: map['sync_status'] as String,
    );
  }
}

class OfflineSyncDbHelper {
  OfflineSyncDbHelper._privateConstructor();
  static final OfflineSyncDbHelper instance = OfflineSyncDbHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(directory.path, 'paper_production_offline.db');
    return await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE factories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            code TEXT NOT NULL,
            location TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE shop_floors (
            id TEXT PRIMARY KEY,
            factory_id TEXT NOT NULL,
            name TEXT NOT NULL,
            code TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (factory_id) REFERENCES factories (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_stage_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            stage_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pipeline_templates (
            id TEXT PRIMARY KEY,
            shop_floor_id TEXT,
            name TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (shop_floor_id) REFERENCES shop_floors (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE pipeline_runs (
            id TEXT PRIMARY KEY,
            template_id TEXT NOT NULL,
            status TEXT NOT NULL,
            start_time TEXT,
            end_time TEXT,
            good_yield INTEGER DEFAULT 0,
            setup_scrap INTEGER DEFAULT 0,
            parent_reel_consumed REAL DEFAULT 0.0,
            data TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE pipeline_templates (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              data TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE pipeline_runs (
              id TEXT PRIMARY KEY,
              template_id TEXT NOT NULL,
              status TEXT NOT NULL,
              start_time TEXT,
              end_time TEXT,
              good_yield INTEGER DEFAULT 0,
              setup_scrap INTEGER DEFAULT 0,
              parent_reel_consumed REAL DEFAULT 0.0,
              data TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE factories (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              code TEXT NOT NULL,
              location TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE shop_floors (
              id TEXT PRIMARY KEY,
              factory_id TEXT NOT NULL,
              name TEXT NOT NULL,
              code TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY (factory_id) REFERENCES factories (id) ON DELETE CASCADE
            )
          ''');
          await db.execute('ALTER TABLE pipeline_templates ADD COLUMN shop_floor_id TEXT');
        }
      },
    );
  }

  Future<int> insertLog(OfflineStageLog log) async {
    final db = await database;
    return await db.insert('offline_stage_logs', log.toMap());
  }

  Future<List<OfflineStageLog>> getPendingLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'offline_stage_logs',
      where: "sync_status = ? OR sync_status = ?",
      whereArgs: ['pending', 'failed'],
    );
    return List.generate(maps.length, (i) {
      return OfflineStageLog.fromMap(maps[i]);
    });
  }

  Future<int> deleteLog(int id) async {
    final db = await database;
    return await db.delete(
      'offline_stage_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateLogStatus(int id, String status) async {
    final db = await database;
    return await db.update(
      'offline_stage_logs',
      {'sync_status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @visibleForTesting
  static void setMockDatabase(Database? db) {
    _database = db;
  }
}
