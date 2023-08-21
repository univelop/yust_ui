/// This record class is used in alert service, if the result is a string.
class AlertResult {
  bool confirmed;
  String? result;

  AlertResult(this.confirmed, this.result);
}

/// This record class is used in alert service for the showCheckListDialog
/// method.
class AlertCheckListResult {
  bool confirmed;
  List<String> result;

  AlertCheckListResult(this.confirmed, this.result);
}
