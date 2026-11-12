/// 签到提交结果。
class SignResult {
  const SignResult({required this.success, this.message, this.statusName});

  final bool success;
  final String? message;

  /// 服务端返回的状态名，如「已签到」「迟到」。
  final String? statusName;
}

/// 从点名花名册里读到的数字口令。
class NumberCodeLookup {
  const NumberCodeLookup({this.code, this.message});

  /// 4 位口令；为 null 表示没读到。
  final String? code;

  /// 读不到时的原因，可以直接给用户看。
  final String? message;

  bool get found => code != null;
}

/// 点名花名册的统计：到课人数 / 总人数（外加可能读到的数字口令）。
class RosterInfo {
  const RosterInfo({
    required this.total,
    required this.signed,
    this.numberCode,
  });

  final int total;
  final int signed;
  final String? numberCode;

  /// 「过半」：严格多于一半。24/47 算过半，23/47 不算。
  bool get isMajoritySigned => total > 0 && signed * 2 > total;
}

