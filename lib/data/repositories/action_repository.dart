import '../models/action_item_model.dart';

abstract class ActionRepository {
  Future<List<ActionItemModel>> fetchActionItems({String? responsibleRole});
  Future<List<String>> fetchDismissedActionIds();
  Future<void> dismissAction(String actionId);
  Future<void> resolveAction(String actionId, {String? notes});
  Future<void> createActionItem(ActionItemModel item);
}
