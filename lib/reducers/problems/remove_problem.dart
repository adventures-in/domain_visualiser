import 'package:domain_visualiser/actions/problems/remove_problem_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:redux/redux.dart';

class RemoveProblemReducer extends TypedReducer<AppState, RemoveProblemAction> {
  RemoveProblemReducer()
      : super((state, action) => state.copyWith(
            problems: state.problems.remove(action.problem),
            pagesData:
                state.pagesData.remove(ProblemPageData(action.problem))));
}
