import 'package:domain_visualiser/actions/problems/add_problem_action.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:redux/redux.dart';

class AddProblemReducer extends TypedReducer<AppState, AddProblemAction> {
  AddProblemReducer()
      : super((state, action) => state.copyWith(
            problems: state.problems.add(action.problem),
            pagesData: state.pagesData.add(ProblemPageData(action.problem))));
}
