import 'package:codraw/actions/problems/add_problem_action.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/models/navigation/page_data/page_data.dart';
import 'package:redux/redux.dart';

class AddProblemReducer extends TypedReducer<AppState, AddProblemAction> {
  AddProblemReducer()
      : super((state, action) => state.copyWith(
            problems: state.problems.add(action.problem),
            pagesData: state.pagesData.add(ProblemPageData(action.problem))));
}
