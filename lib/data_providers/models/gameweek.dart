/// Maps to schema `gameweeks`. Drives the Deadline Timer trigger system
/// (plan section 3) — `deadlineTime` is the single source of truth for
/// the 48h / 6h / 90min alert thresholds.
class Gameweek {
  final int id;
  final int number;
  final DateTime deadlineTime;
  final bool isCurrent;
  final bool isNext;
  final bool finished;

  const Gameweek({
    required this.id,
    required this.number,
    required this.deadlineTime,
    required this.isCurrent,
    required this.isNext,
    required this.finished,
  });

  Duration timeUntilDeadline({DateTime? now}) =>
      deadlineTime.difference(now ?? DateTime.now().toUtc());

  factory Gameweek.fromFplJson(Map<String, dynamic> json) {
    return Gameweek(
      id: json['id'] as int,
      number: json['id'] as int,
      deadlineTime: DateTime.parse(json['deadline_time'] as String).toUtc(),
      isCurrent: json['is_current'] as bool? ?? false,
      isNext: json['is_next'] as bool? ?? false,
      finished: json['finished'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'deadline_time': deadlineTime.toIso8601String(),
        'is_current': isCurrent,
        'is_next': isNext,
        'finished': finished,
      };
}
