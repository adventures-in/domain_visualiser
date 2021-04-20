import 'package:domain_visualiser/actions/problems/add_problem_action.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
import 'package:redux/redux.dart';

extension StoreExt on Store<AppState> {
  dynamic dispatchProblem(dynamic error, StackTrace trace) =>
      dispatch(AddProblemAction(
          errorString: error.toString(), traceString: trace.toString()));
}
