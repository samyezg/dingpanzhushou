import 'dart:convert';



import 'package:shared_preferences/shared_preferences.dart';



class AlertRecord {

  final DateTime at;

  final String tsCode;

  final String title;

  final String body;

  /// false = 仅记录（未推系统通知）；旧数据缺省视为 true

  final bool notified;



  AlertRecord({

    required this.at,

    required this.tsCode,

    required this.title,

    required this.body,

    this.notified = true,

  });



  Map<String, dynamic> toJson() => {

        'at': at.toIso8601String(),

        'ts_code': tsCode,

        'title': title,

        'body': body,

        'notified': notified,

      };



  factory AlertRecord.fromJson(Map<String, dynamic> j) => AlertRecord(

        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),

        tsCode: j['ts_code']?.toString() ?? '',

        title: j['title']?.toString() ?? '',

        body: j['body']?.toString() ?? '',

        notified: j['notified'] is bool ? j['notified'] as bool : true,

      );

}



class AlertHistoryStore {

  static const _k = 'alert_history_v1';

  static const _max = 200;



  SharedPreferences? _prefs;



  Future<void> init() async {

    _prefs = await SharedPreferences.getInstance();

  }



  Future<List<AlertRecord>> load() async {

    final prefs = _prefs ?? await SharedPreferences.getInstance();

    final raw = prefs.getString(_k);

    if (raw == null || raw.isEmpty) return [];

    final list = jsonDecode(raw) as List<dynamic>;

    return list

        .map((e) => AlertRecord.fromJson(Map<String, dynamic>.from(e as Map)))

        .toList();

  }



  Future<void> add(AlertRecord r) async {

    final prefs = _prefs ?? await SharedPreferences.getInstance();

    final cur = await load();

    cur.insert(0, r);

    while (cur.length > _max) {

      cur.removeLast();

    }

    await prefs.setString(

      _k,

      jsonEncode(cur.map((e) => e.toJson()).toList()),

    );

  }

}


