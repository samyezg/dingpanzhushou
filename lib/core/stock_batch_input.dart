/// 盯盘页「添加股票」批量输入分段规则。
///
/// 分隔符：英文/中文逗号、英文/中文分号、顿号、空格、斜杠、换行、制表符。
/// **不**以 `.` 分段，以便保留 `600519.SH`。
library;

/// 单次「添加」操作允许解析的最大段数
const int kMaxStockBatchSegments = 20;

/// 分隔符正则（不含 `.`）
final RegExp kStockInputDelimiter = RegExp(r'[,，;；、\r\n\t /]+');

List<String> splitStockInputSegments(String raw) {
  return raw
      .split(kStockInputDelimiter)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

const String kStockInputHelperText =
    '名称、6 位代码或 代码.SH/SZ；多只用逗号、顿号或换行分隔。'
    '示例：601138.SH,600584';
