/// A 股连续竞价时段（一期写死，不含集合竞价）
library;

class TradingSession {
  TradingSession._();

  /// [now] 视为本地墙钟；内部按东八区墙钟语义使用（设备时区请设为中国或自行换算）。
  /// 一期日历：周六日直接非交易；法定节假日仍可能误判（见已知差异表）。
  static bool isContinuousAuction(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final t = TimeOfDaySec.fromDateTime(now);
    final morning = t.isInRange(
      const TimeOfDaySec(9, 30, 0),
      const TimeOfDaySec(11, 30, 0),
    );
    final afternoon = t.isInRange(
      const TimeOfDaySec(13, 0, 0),
      const TimeOfDaySec(15, 0, 0),
    );
    return morning || afternoon;
  }

  static String statusMessage(DateTime now) {
    if (isContinuousAuction(now)) return '交易时段（连续竞价）';
    return '非交易时间';
  }
}

class TimeOfDaySec {
  final int hour;
  final int minute;
  final int second;

  const TimeOfDaySec(this.hour, this.minute, this.second);

  factory TimeOfDaySec.fromDateTime(DateTime dt) =>
      TimeOfDaySec(dt.hour, dt.minute, dt.second);

  int get totalSeconds => hour * 3600 + minute * 60 + second;

  bool isInRange(TimeOfDaySec start, TimeOfDaySec endInclusive) {
    final v = totalSeconds;
    return v >= start.totalSeconds && v <= endInclusive.totalSeconds;
  }
}
