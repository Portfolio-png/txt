enum NodeRunStatus { pending, active, done, skipped }

extension NodeRunStatusX on NodeRunStatus {
  String get value {
    switch (this) {
      case NodeRunStatus.pending:
        return 'pending';
      case NodeRunStatus.active:
        return 'active';
      case NodeRunStatus.done:
        return 'done';
      case NodeRunStatus.skipped:
        return 'skipped';
    }
  }

  String get label {
    switch (this) {
      case NodeRunStatus.pending:
        return 'Pending';
      case NodeRunStatus.active:
        return 'Active';
      case NodeRunStatus.done:
        return 'Done';
      case NodeRunStatus.skipped:
        return 'Skipped';
    }
  }
}

NodeRunStatus parseNodeRunStatus(String? value) {
  switch (value) {
    case 'active':
      return NodeRunStatus.active;
    case 'done':
      return NodeRunStatus.done;
    case 'skipped':
      return NodeRunStatus.skipped;
    default:
      return NodeRunStatus.pending;
  }
}
