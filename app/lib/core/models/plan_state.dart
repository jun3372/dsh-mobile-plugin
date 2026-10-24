/// 0.2.1 `plan` 投影：只表达计划协作状态，不携带计划正文。
class PlanState {
  final bool active;
  final bool pending;

  const PlanState({this.active = false, this.pending = false});

  static PlanState? fromValue(Object? value) {
    if (value is! Map) return null;
    return PlanState(
      active: value['active'] == true,
      pending: value['pending'] == true,
    );
  }
}
