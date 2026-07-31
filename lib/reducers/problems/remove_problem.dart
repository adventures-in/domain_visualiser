import 'package:codraw/actions/problems/remove_problem_action.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/models/navigation/page_data/page_data.dart';
import 'package:redux/redux.dart';

class RemoveProblemReducer extends TypedReducer<AppState, RemoveProblemAction> {
  RemoveProblemReducer()
      : super((state, action) => state.copyWith(
            problems: state.problems.remove(action.problem),
            pagesData:
                state.pagesData.remove(ProblemPageData(action.problem))));
}
