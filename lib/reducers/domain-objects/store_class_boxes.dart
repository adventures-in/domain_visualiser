import 'package:codraw/actions/domain-objects/store_class_boxes_action.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class StoreClassBoxesReducer
    extends TypedReducer<AppState, StoreClassBoxesAction> {
  StoreClassBoxesReducer()
      : super((state, action) => state.copyWith(classBoxes: action.boxes));
}
