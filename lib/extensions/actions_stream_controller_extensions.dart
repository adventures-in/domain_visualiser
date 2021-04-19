import 'dart:async';

import 'package:domain_visualiser/actions/problems/add_problem_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';

extension StreamControllerExt on StreamController<ReduxAction> {
  void addProblem(dynamic error, StackTrace trace) => add(AddProblemAction(
      errorString: error.toString(), traceString: trace.toString()));
}
